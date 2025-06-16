#!/bin/bash

# Script to transfer, extract, and load ZenTao backup data to Docker host
# Execute this script locally on your computer

# Configuration (adjust these variables as needed)
BACKUP_FILE="$HOME/Downloads/zentao-backup/zentao-backup-*.tar.gz" # Path to backup file (wildcards for latest)
DOCKER_HOST="jay@10.10.5.180"                           # SSH user and Docker host IP/hostname
DOCKER_DATA_DIR="~/mydata/zentao"                       # Data directory on Docker host
COMPOSE_DIR="$DOCKER_DATA_DIR"                           # Directory with docker-compose.yaml
MYSQL_CONTAINER="zentao-mysql"                           # MySQL container name
MYSQL_USER="root"                                        # MySQL user
MYSQL_PASS="123456"                                      # MySQL password
MYSQL_PORT="3306"                                        # MySQL port inside container

# Step 1: Find the latest backup file
BACKUP_FILE=$(ls -t $BACKUP_FILE | head -n 1)
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: No backup file found in ~/zentao-backup"
    exit 1
fi
echo "Using backup file: $BACKUP_FILE"

# Step 2: Transfer backup to Docker host
echo "Transferring backup to Docker host..."
scp "$BACKUP_FILE" "$DOCKER_HOST:$DOCKER_DATA_DIR/" || {
    echo "Failed to transfer backup"
    exit 1
}

# Step 3: Extract backup on Docker host
echo "Extracting backup on Docker host..."
ssh "$DOCKER_HOST" << EOF
    mkdir -p $DOCKER_DATA_DIR
    tar -xzf $DOCKER_DATA_DIR/$(basename "$BACKUP_FILE") -C $DOCKER_DATA_DIR
    mv $DOCKER_DATA_DIR/zentao-files $DOCKER_DATA_DIR/zentao-files
    mv $DOCKER_DATA_DIR/mysql-data $DOCKER_DATA_DIR/mysql-data
    mv $DOCKER_DATA_DIR/config $DOCKER_DATA_DIR/config
    mv $DOCKER_DATA_DIR/upload $DOCKER_DATA_DIR/upload
    rm $DOCKER_DATA_DIR/$(basename "$BACKUP_FILE")
EOF
if [ $? -ne 0 ]; then
    echo "Failed to extract backup"
    exit 1
fi

# Step 4: Start Docker Compose (MySQL only)
echo "Starting MySQL container..."
ssh "$DOCKER_HOST" << EOF
    cd $COMPOSE_DIR
    docker-compose up -d mysql
EOF
if [ $? -ne 0 ]; then
    echo "Failed to start MySQL container"
    exit 1
fi

# Step 5: Wait for MySQL to be ready
echo "Waiting for MySQL to be ready..."
for i in {1..30}; do
    ssh "$DOCKER_HOST" "docker exec $MYSQL_CONTAINER mysqladmin -u $MYSQL_USER -p$MYSQL_PASS ping" && break
    sleep 2
done
if [ $i -eq 30 ]; then
    echo "MySQL not ready after 60 seconds"
    exit 1
fi

# Step 6: Import database dump
echo "Importing database dump..."
scp "$BACKUP_FILE" "$DOCKER_HOST:/tmp/zentao-backup.tar.gz" || {
    echo "Failed to transfer backup for database import"
    exit 1
}
ssh "$DOCKER_HOST" << EOF
    mkdir -p /tmp/zentao-backup
    tar -xzf /tmp/zentao-backup.tar.gz -C /tmp/zentao-backup zentao.sql
    docker cp /tmp/zentao-backup/zentao.sql $MYSQL_CONTAINER:/zentao.sql
    docker exec $MYSQL_CONTAINER mysql -u $MYSQL_USER -p$MYSQL_PASS zentao < /zentao.sql
    rm -rf /tmp/zentao-backup /tmp/zentao-backup.tar.gz
EOF
if [ $? -ne 0 ]; then
    echo "Failed to import database"
    exit 1
fi

# Step 7: Set permissions
echo "Setting permissions..."
ssh "$DOCKER_HOST" "chown -R 1000:1000 $DOCKER_DATA_DIR/zentao-files $DOCKER_DATA_DIR/config $DOCKER_DATA_DIR/upload $DOCKER_DATA_DIR/mysql-data" || {
    echo "Failed to set permissions"
    exit 1
}

# Step 8: Start full Docker Compose
echo "Starting full ZenTao setup..."
ssh "$DOCKER_HOST" << EOF
    cd $COMPOSE_DIR
    docker-compose up -d
EOF
if [ $? -ne 0 ]; then
    echo "Failed to start ZenTao"
    exit 1
fi

echo "Data loaded successfully! Access ZenTao at https://pm.nexuslearning.org/zentao/"