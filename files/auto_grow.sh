#!/bin/bash
#
# EBS Auto-Grow Script (IMDSv2 aware)
# • Increases the root EBS volume by +20 % when disk usage ≥ THRESHOLD %.
# • Logs to /var/log/ebs-monitor.log.
# Requirements: awscli v2, growpart (cloud-utils-growpart), resize2fs.

### CONFIG
MOUNT_POINT="/"          # filesystem to monitor
THRESHOLD=90             # trigger percentage
GROWTH_PERCENTAGE=20     # how much to grow (percent)
LOG_FILE="/var/log/ebs-monitor.log"
DATE=$(date "+%Y-%m-%d %H:%M:%S")

### 1 — Check disk usage
USAGE=$(df -h "$MOUNT_POINT" | awk 'NR==2 {gsub("%",""); print $5}')
echo "$DATE - Usage is ${USAGE}% on $MOUNT_POINT" >> "$LOG_FILE"
[ "$USAGE" -lt "$THRESHOLD" ] && exit 0

echo "$DATE - Threshold exceeded. Starting EBS grow process." >> "$LOG_FILE"

### 2 — Fetch IMDSv2 token
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
if [ -z "$TOKEN" ]; then
  echo "$DATE - ❌ ERROR: Cannot obtain IMDSv2 token" >> "$LOG_FILE"
  exit 1
fi

### 3 — Get instance-ID and region
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
                 http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
               http://169.254.169.254/latest/dynamic/instance-identity/document \
        | grep region | awk -F\" '{print $4}')
if [ -z "$INSTANCE_ID" ] || [ -z "$REGION" ]; then
  echo "$DATE - ❌ ERROR: Blank IMDS data. ID:'$INSTANCE_ID' REGION:'$REGION'" >> "$LOG_FILE"
  exit 1
fi

### 4 — Identify attached volume
VOLUME_ID=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-id "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId" \
  --output text)
[ -z "$VOLUME_ID" ] && { echo "$DATE - ❌ ERROR: No volume ID"; exit 1; }

### 5 — Current size & target size
CURRENT_SIZE=$(aws ec2 describe-volumes \
  --region "$REGION" \
  --volume-ids "$VOLUME_ID" \
  --query "Volumes[0].Size" \
  --output text)
[[ ! "$CURRENT_SIZE" =~ ^[0-9]+$ ]] && { echo "$DATE - ❌ ERROR: Size fetch failed"; exit 1; }

TARGET_SIZE=$(( CURRENT_SIZE + (CURRENT_SIZE * GROWTH_PERCENTAGE / 100) ))
echo "$DATE - Increasing volume $VOLUME_ID from ${CURRENT_SIZE}GiB to ${TARGET_SIZE}GiB" >> "$LOG_FILE"

### 6 — Modify volume & wait
aws ec2 modify-volume --region "$REGION" --volume-id "$VOLUME_ID" --size "$TARGET_SIZE" >> "$LOG_FILE" 2>&1
aws ec2 wait volume-modification-completed --region "$REGION" --volume-id "$VOLUME_ID"

### 7 — Grow partition & filesystem
growpart /dev/xvda 1   >> "$LOG_FILE" 2>&1
resize2fs /dev/xvda1   >> "$LOG_FILE" 2>&1

echo "$DATE - ✅ Resize complete." >> "$LOG_FILE"
### END auto_grow.sh ##############################################
