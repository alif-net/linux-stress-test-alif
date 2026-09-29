#!/bin/bash
# Part 3: stress test. Use: --disk, --cpu, --mem or --all
DIR="/mnt/${SVC_NAME}_tmp"

disk() {
  for i in $(seq 1 20); do
    dd if=/dev/urandom of="$DIR/file_$i.dat" bs=1M count=10
    df -h "$DIR"
  done
}
cpu() { sudo -u "$SVC_NAME" stress-ng --cpu 2 --timeout 30s --temp-path /tmp; }
mem() { sudo -u "$SVC_NAME" stress-ng --vm 1 --vm-bytes 200M --timeout 30s --temp-path /tmp; }

case "$1" in
  --disk) disk ;;
  --cpu)  cpu ;;
  --mem)  mem ;;
  --all)  cpu & mem & disk; wait ;;
  *) echo "Use: $0 --disk | --cpu | --mem | --all" ;;
esac
