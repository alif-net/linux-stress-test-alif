#!/bin/bash
# Part 8: remove everything in reverse order (safe to run twice)
sudo pkill -u "$SVC_NAME" 2>/dev/null
sudo crontab -r -u "$SVC_NAME" 2>/dev/null
sudo rm -f "/etc/logrotate.d/$SVC_NAME"
sudo rm -f "/usr/local/bin/${SVC_NAME}_monitor.sh"
sudo rm -f "/usr/local/bin/${SVC_NAME}_cleanup_old_files.sh"
sudo umount "/mnt/${SVC_NAME}_tmp" 2>/dev/null
sudo rmdir "/mnt/${SVC_NAME}_tmp" 2>/dev/null
sudo rm -rf "/var/log/$SVC_NAME"
sudo userdel -r "$SVC_NAME" 2>/dev/null
echo "Cleanup done. Checking:"
id "$SVC_NAME"
mount | grep "$SVC_NAME"
ps -u "$SVC_NAME"
