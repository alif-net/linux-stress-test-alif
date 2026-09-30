# Observations

## What I observed under load
When the 256M tmpfs filled up, the write failed cleanly with "No space left on device"
and the server kept working, so the size cap worked. During the combined test,
stress-ng used almost 100% of both CPUs and available memory dropped from ___ to ___.
dmesg showed ___ (no OOM kill / an OOM kill).

## What I would do differently on a real production server
I would not stress-test production; I would use a copy (staging). I would use
monitoring alerts (like CloudWatch) instead of watching by hand. I kept "ubuntu"
in AllowUsers because the service account cannot log in, so without it nobody
could reach the server.
