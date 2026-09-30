#!/bin/bash
# Part 2: create a 256M RAM disk (safe to run twice)
sudo mkdir -p "/mnt/${SVC_NAME}_tmp"
if mountpoint -q "/mnt/${SVC_NAME}_tmp"; then
  echo "Already mounted. Nothing to do."
else
  sudo mount -t tmpfs -o size=256M tmpfs "/mnt/${SVC_NAME}_tmp"
  echo "Mounted."
fi
sudo chown "$SVC_NAME:$SVC_NAME" "/mnt/${SVC_NAME}_tmp"
df -h "/mnt/${SVC_NAME}_tmp"
