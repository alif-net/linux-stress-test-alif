# Linux Load Testing & Hardening — Service Environment on AWS EC2

End-to-end Linux operations project: provision a dedicated environment for a new internal service, push it under real load, secure access, automate monitoring and log management, then tear everything down without leaving a trace.

## Project Information

| Item | Details |
|---|---|
| **Author** | Shajjad Alif |
| **Focus** | Linux administration · SSH security · automation · observability |
| **Service account** | `bgdsvc_alif` |
| **Environment** | AWS EC2 `t3.micro` (2 vCPU, ~1 GB RAM) · Ubuntu 24.04 LTS · eu-central-1 (Frankfurt) |
| **Hostname** | `linux-stress-test` |
| **Completed** | September 30, 2026 |

## Overview

The project covers the full lifecycle of a service environment on a cloud server:

- Create a dedicated, non-login **service account** (least privilege)
- Give it fast, **size-capped RAM storage** with `tmpfs`
- **Stress test** disk, CPU and memory — separately and all at once
- Grant **key-based SSH access** to the service account
- **Harden SSH** (custom port, no root login, no passwords, allow-list)
- **Automate monitoring** and nightly cleanup with `cron`
- Keep logs under control with **`logrotate`**
- **Clean up** everything in reverse order with an idempotent script

## Workflow

```text
Identity        →  service account (no login shell)
      │
Resources       →  256M tmpfs scratch space
      │
Load            →  disk · CPU · memory · all together
      │
Access          →  SSH key authentication
      │
Security        →  SSH hardening on port 2222
      │
Automation      →  cron: monitor every 5 min, cleanup nightly
      │
Log hygiene     →  logrotate: daily, keep 5, compress
      │
Teardown        →  reverse-order cleanup + verification
```

## Repository Structure

```text
linux-stress-test-alif/
├── README.md
├── observations.md                      # what I observed under load
├── scripts/
│   ├── 01_create_user.sh                # Part 1 — idempotent user creation
│   ├── 02_setup_tmpfs.sh                # Part 2 — idempotent 256M tmpfs
│   ├── 03_stress_and_populate.sh        # Part 3 — --disk | --cpu | --mem | --all
│   ├── 04_cleanup.sh                    # Part 8 — idempotent reverse-order cleanup
│   ├── bgdsvc_alif_monitor.sh           # Part 6 — runs every 5 minutes via cron
│   └── bgdsvc_alif_cleanup_old_files.sh # Part 6 — runs nightly at 02:00 via cron
└── screenshots/                         # 11 screenshots, one per required result
```

## Quick Start

**Prerequisites:** Ubuntu with `sudo`, plus `stress-ng`, OpenSSH server, `cron` and `logrotate`.

```bash
sudo apt update && sudo apt install -y stress-ng
export SVC_NAME=bgdsvc_alif
chmod +x scripts/*.sh

./scripts/01_create_user.sh              # create the service account
./scripts/02_setup_tmpfs.sh              # mount the 256M RAM disk
./scripts/03_stress_and_populate.sh --all   # run disk + CPU + memory load together
./scripts/04_cleanup.sh                  # remove everything, in reverse order
```

Every script is **idempotent** — running it a second time is safe and changes nothing.

---

## Part 1 — Service Account

```bash
sudo useradd -r -m -s /usr/sbin/nologin "$SVC_NAME"
```

- `-r` system account · `-m` home directory (needed later for SSH keys) · `-s /usr/sbin/nologin` nobody can log in as it
- The script checks `id "$SVC_NAME"` first, so a second run prints *"already exists. Nothing to do."*

**Why:** a service should never run as root or as a personal user. If it is compromised, the attacker only gets a small, non-interactive account.

## Part 2 — tmpfs Scratch Space

```bash
sudo mount -t tmpfs -o size=256M tmpfs "/mnt/${SVC_NAME}_tmp"
```

- RAM-backed, so reads and writes are very fast (~280 MB/s in my test)
- `size=256M` is the safety cap — without it, tmpfs can grow until it eats all RAM and takes down the whole machine
- The script uses `mountpoint -q` to avoid mounting twice

## Part 3 — Stress Testing

| Test | Command (core) | Result |
|---|---|---|
| **Disk** | 20 × `dd … bs=1M count=10` into the tmpfs | Filled to **200M / 256M (79%)**; beyond the cap `dd` failed cleanly with *"No space left on device"* — the server stayed healthy |
| **CPU** | `stress-ng --cpu 2 --timeout 30s` | Both vCPUs pinned near 100% while running |
| **Memory** | `stress-ng --vm 1 --vm-bytes 200M --timeout 30s` | Available memory dropped while running, recovered afterwards |
| **All at once** | `03_stress_and_populate.sh --all` | See [`observations.md`](observations.md) for before / during / after numbers |
| **OOM check** | `sudo dmesg \| grep -i oom` | Empty — the kernel never had to kill a process |

Load runs as the service user (`sudo -u "$SVC_NAME"`), because in real life the pressure comes from the service, not from the admin.

## Part 4 — SSH Key Access

```bash
ssh-keygen -t ed25519 -f ~/.ssh/${SVC_NAME}_key
# public key → /home/$SVC_NAME/.ssh/authorized_keys   (dir 700, file 600)
```

Connecting as the service account authenticates with the key, then shows *"This account is currently not available."* — proof that **both** protections work: the key is accepted, and the no-login shell still blocks an interactive session.

## Part 5 — SSH Hardening

| Setting | Value | Why |
|---|---|---|
| `Port` | `2222` | Avoids the constant automated scans on port 22 |
| `PermitRootLogin` | `no` | Root is the most valuable target |
| `PasswordAuthentication` | `no` | Keys cannot be guessed; passwords can |
| `AllowUsers` | `bgdsvc_alif ubuntu` | Only listed accounts may connect |

- Port **2222 was opened in the AWS Security Group first**, then tested, before relying on it — changing the port first would have locked me out
- `ubuntu` stays in `AllowUsers` because the service account cannot open a shell; without it, nobody could administer the server
- Config validated with `sudo sshd -t` before restarting. On Ubuntu 24.04 SSH is socket-activated, so `daemon-reload` + restarting `ssh.socket` were required for the new port

## Part 6 — Cron Automation

```cron
*/5 * * * * /usr/local/bin/bgdsvc_alif_monitor.sh
0 2 * * *   /usr/local/bin/bgdsvc_alif_cleanup_old_files.sh
```

| Job | Schedule | What it does |
|---|---|---|
| Monitor | every 5 minutes | Appends a timestamp, `free -h`, `df -h` of the tmpfs and the service's processes to `/var/log/bgdsvc_alif/monitor.log` |
| Cleanup | daily at 02:00 | Deletes tmpfs files older than 1 day so the scratch space does not fill with stale runs |

Both jobs live in the **service account's** crontab, so they run with its limited permissions — not as root.

## Part 7 — Log Rotation

`/etc/logrotate.d/bgdsvc_alif`:

```text
/var/log/bgdsvc_alif/*.log {
    daily
    rotate 5
    compress
    missingok
    notifempty
    size 10M
    create 0640 bgdsvc_alif bgdsvc_alif
}
```

| Directive | Effect |
|---|---|
| `daily` / `size 10M` | Rotate every day, or as soon as the log passes 10 MB |
| `rotate 5` | Keep only the 5 most recent old logs |
| `compress` | Gzip rotated logs to save space |
| `missingok` / `notifempty` | No error if the log is missing; skip empty logs |
| `create 0640 …` | Recreate an empty log owned by the service account |

Tested with `sudo logrotate -f` → the folder then held a fresh `monitor.log` plus the compressed `monitor.log.1.gz`.

## Part 8 — Reverse-Order Cleanup

Build order was **user → storage → load → access → automation**, so teardown runs backwards:

1. Kill the service's processes (`pkill -u`)
2. Remove the crontab, logrotate rule and both `/usr/local/bin` scripts
3. Unmount and remove the tmpfs (impossible while a process still holds a file open)
4. Delete the logs
5. Delete the user (impossible while it still owns running processes)

Verification: `id` → *no such user* · `mount | grep` → nothing · `ps -u` → *user name does not exist*.
Errors from steps that already ran are silenced with `2>/dev/null`, so the script is safe to re-run after a partial failure.

---

## Evidence (Screenshots)

| # | File | Shows |
|---:|---|---|
| 0 | `00_svc_name.png` | `echo $SVC_NAME` — the name used throughout |
| 1 | `01_id_created.png` | `id` right after creating the account |
| 2 | `02_df_before.png` | Empty 256M tmpfs |
| 3 | `02_df_after.png` | tmpfs filled to 200M / 79% |
| 4 | `03_free_before.png` | Memory before the combined stress test |
| 5 | `03_free_during.png` | Memory during the combined stress test |
| 6 | `03_free_after.png` | Memory after the combined stress test |
| 7 | `03_dmesg_oom.png` | OOM check — empty, no process was killed |
| 8 | `04_ssh_success.png` | Key-based login on port 2222 (`Authenticated … using "publickey"`) |
| 9 | `05_crontab_l.png` | Both cron jobs scheduled |
| 10 | `06_cleanup_verify.png` | Final verification: account, mount and processes all gone |

## Troubleshooting Notes

| Symptom | Cause | Fix |
|---|---|---|
| `stress-ng: aborting: temp-path '.' must be readable and writeable` | Run as the service user from my home directory, where it has no write access — least privilege working as intended | Added `--temp-path /tmp` |
| `ssh: connect … port 22: Connection refused` after Part 5 | SSH now listens on 2222 only | Connect with `-p 2222` (port was already open in the Security Group) |
| `unexpected EOF while looking for matching '"'` in the monitor script | A missing closing quote after pasting | Found with `bash -n script.sh`, fixed the line |
| `chown: Operation not permitted` | Changing ownership of a root-owned folder without `sudo` | Re-ran with `sudo` |

Lesson: *"Connection refused"* means nothing is listening on that port; *"Connection timed out"* means a firewall or Security Group is dropping the traffic. Knowing the difference points straight at the cause.

## Tools & Concepts

| Tool / Concept | Used for |
|---|---|
| `useradd` / `userdel` / `id` / `getent` | Creating, verifying and removing the service account |
| `tmpfs`, `mount` / `umount`, `mountpoint`, `df` | RAM-backed storage with a hard size cap |
| `dd`, `stress-ng`, `free`, `top`, `dmesg` | Generating load and observing its effect |
| `ssh-keygen`, `authorized_keys`, `sshd_config`, `sshd -t` | Key-based access and SSH hardening |
| `systemctl`, `ss -tlnp` | Restarting SSH and confirming the listening port |
| `crontab` | Scheduled monitoring and cleanup |
| `logrotate` | Log rotation, compression and retention |
| `pkill`, `find -mtime` | Process and file cleanup |
| AWS EC2 + Security Groups | Cloud server and network-level firewall |
| Git + GitHub CLI (`gh`) | One commit per part, pushed from the server |

## Security Notes

- No private keys are committed — `.gitignore` excludes `*_key`
- No real public IPs or DNS names appear in the scripts or screenshots
- The service account has no login shell and no password; access is key-only

## Key Takeaways

**Configure → Secure → Automate → Monitor → Stress test → Troubleshoot → Verify → Clean up**

The same pattern applies whether the target is a test VM, a production EC2 instance or a Kubernetes pod: give the service its own identity, give it bounded resources, find its breaking point on purpose, lock down access, let the system watch itself, keep logs from growing forever — and be able to remove it all cleanly.
