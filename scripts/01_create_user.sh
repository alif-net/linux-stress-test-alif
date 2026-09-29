#!/bin/bash
#part 1 : create the service user (safe to run twice)

if id "$SVC_NAME" >/dev/null 2>&1; then 
	echo "User $SVC_NAME already exists. Nothing to do."
else 
	sudo useradd -r -m -s /usr/sbin/nologin "$SVC_NAME"
	echo "User $SVC_NAME created."
	
fi 

id "$SVC_NAME"
