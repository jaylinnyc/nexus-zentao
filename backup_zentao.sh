#!/bin/bash

# Script to back up ZenTao 12.3 from production (Z-Box) to local computer using rsync and scp
# Execute this script locally on your computer
# Updated for MySQL port 4306 as confirmed

# Configuration (adjust these variables as needed)
PROD_HOST="ec2-user@nexuslearning.org" # SSH user and production server IP/hostname
PROD_ZBOX_PATH="/opt/zbox"            # Z-Box installation path on production
LOCAL_BACKUP_DIR="$HOME/Downloads/zentao-backup" # Local directory to store backup
MYSQL_USER="root"                     # MySQL user
MYSQL_PASS="123456"                   # MySQL password
MYSQL_HOST="127.0.0.1"                # MySQL host
MYSQL_PORT="4306"                     # MySQL port (confirmed)
TEMP_SQL_FILE="/tmp/zentao_backup_$(date +%F_%H%M%S).sql" # Temp file on production

# Ensure local backup directory exists
mkdir -p "$LOCAL_BACKUP_DIR" || { echo "Failed to create local backup directory"; exit 1; }

# Step 1: Dump MySQL database on production and transfer it
echo "Dumping MySQL database..."
ssh "$PROD_HOST" "mysqldump -u $MYSQL_USER -p$MYSQL_PASS -h $MYSQL_HOST -P $MYSQL_PORT zentao > $TEMP_SQL_FILE" || {
    echo "Failed to dump MySQL database"
    exit 1
}

# Transfer the database dump to local machine
echo "Transferring database dump..."
scp "$PROD_HOST:$TEMP_SQL_FILE" "$LOCAL_BACKUP_DIR/zentao.sql" || {
    echo "Failed to transfer database dump"
    ssh "$PROD_HOST" "rm -f $TEMP_SQL_FILE"
    exit 1
}

# Clean up temporary SQL file on production
ssh "$PROD_HOST" "rm -f $TEMP_SQL_FILE" || echo "Warning: Could not delete temp SQL file"

# Step 2: Rsync ZenTao files
echo "Backing up ZenTao files..."
rsync -avz --progress "$PROD_HOST:$PROD_ZBOX_PATH/app/zentao" "$LOCAL_BACKUP_DIR/zentao-files" || {
    echo "Failed to rsync ZenTao files"
    exit 1
}

# Step 3: Rsync MySQL data
echo "Backing up MySQL data directory..."
rsync -avz --progress "$PROD_HOST:$PROD_ZBOX_PATH/data/mysql/zentao" "$LOCAL_BACKUP_DIR/mysql-data" || {
    echo "Failed to rsync MySQL data"
    exit 1
}

# Step 4: Rsync configuration files
echo "Backing up configuration files..."
rsync -avz --progress "$PROD_HOST:$PROD_ZBOX_PATH/app/zentao/config" "$LOCAL_BACKUP_DIR/config" || {
    echo "Failed to rsync configuration files"
    exit 1
}

# Step 5: Rsync attachments
echo "Backing up attachments..."
rsync -avz --progress "$PROD_HOST:$PROD_ZBOX_PATH/app/zentao/www/data/upload" "$LOCAL_BACKUP_DIR/upload" || {
    echo "Failed to rsync attachments"
    exit 1
}

# Step 6: Compress the backup locally
echo "Compressing backup..."
tar -czf "$LOCAL_BACKUP_DIR/zentao-backup-$(date +%F_%H%M%S).tar.gz" -C "$LOCAL_BACKUP_DIR" zentao-files mysql-data config upload zentao.sql || {
    echo "Failed to compress backup"
    exit 1
}

# Optional: Remove uncompressed files to save local space
read -p "Delete uncompressed backup files to save space? (y/n): " confirm
if [ "$confirm" = "y" ]; then
    rm -rf "$LOCAL_BACKUP_DIR/zentao-files" "$LOCAL_BACKUP_DIR/mysql-data" \
           "$LOCAL_BACKUP_DIR/config" "$LOCAL_BACKUP_DIR/upload" "$LOCAL_BACKUP_DIR/zentao.sql"
    echo "Uncompressed files deleted"
fi

echo "Backup completed successfully! Compressed backup is at $LOCAL_BACKUP_DIR"