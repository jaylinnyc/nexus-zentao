#!/bin/bash

# Script to extract and load ZenTao backup data locally
# Execute this script on the host computer where the backup files are located

# Configuration (adjust these variables as needed)
BACKUP_FILE="$HOME/Downloads/zentao-backup/zentao-backup-*.tar.gz" # Path to backup tar.gz file (wildcards for latest)
MYSQL_DUMP_FILE="$HOME/Downloads/zentao-backup/zentao.sql"        # Path to MySQL dump file
DOCKER_DATA_DIR="$HOME/mydata/zentao"                            # Local data directory
COMPOSE_DIR="$DOCKER_DATA_DIR"                                   # Directory with docker-compose.yaml
MYSQL_CONTAINER="zentao-mysql"                                   # MySQL container name
MYSQL_USER="root"                                                # MySQL user
MYSQL_PASS="123456"                                              # MySQL password
MYSQL_PORT="3306"                                                # MySQL port inside container

# Step 1: Find the latest backup file
BACKUP_FILE=$(ls -t $BACKUP_FILE | head -n 1)
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: No backup tar.gz file found at $BACKUP_FILE"
    exit 1
fi
echo "Using backup file: $BACKUP_FILE"

# Step 2: Verify MySQL dump file exists
if [ ! -f "$MYSQL_DUMP_FILE" ]; then
    echo "Error: MySQL dump file not found at $MYSQL_DUMP_FILE"
    exit 1
fi
echo "Using MySQL dump file: $MYSQL_DUMP_FILE"

# Step 3: Create data directory and check if non-empty
echo "Creating data directory..."
mkdir -p "$DOCKER_DATA_DIR" || {
    echo "Failed to create data directory"
    exit 1
}
if [ -d "$DOCKER_DATA_DIR" ] && [ "$(ls -A "$DOCKER_DATA_DIR")" ]; then
    echo "Warning: $DOCKER_DATA_DIR is not empty. Continuing may overwrite existing data."
    read -p "Proceed? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Aborting to prevent overwrite."
        exit 1
    fi
fi

# Step 4: Extract backup locally
echo "Extracting backup..."
tar -xzf "$BACKUP_FILE" -C "$DOCKER_DATA_DIR" || {
    echo "Failed to extract backup"
    exit 1
}
# Move extracted files to correct locations (adjust based on tar structure)
mv "$DOCKER_DATA_DIR/zentao-files" "$DOCKER_DATA_DIR/zentao-files" 2>/dev/null
mv "$DOCKER_DATA_DIR/mysql-data" "$DOCKER_DATA_DIR/mysql-data" 2>/dev/null
mv "$DOCKER_DATA_DIR/config" "$DOCKER_DATA_DIR/config" 2>/dev/null
mv "$DOCKER_DATA_DIR/upload" "$DOCKER_DATA_DIR/upload" 2>/dev/null

# Step 5: Start Docker Compose (MySQL only)
echo "Starting MySQL container..."
cd "$COMPOSE_DIR" || {
    echo "Failed to navigate to $COMPOSE_DIR"
    exit 1
}
docker-compose up -d zentao-db || {
    echo "Failed to start MySQL container"
    exit 1
}

# Step 6: Wait for MySQL to be ready
echo "Waiting for MySQL to be ready..."
for i in {1..30}; do
    docker exec "$MYSQL_CONTAINER" mysqladmin -u "$MYSQL_USER" -p"$MYSQL_PASS" ping && break
    sleep 2
done
if [ $i -eq 30 ]; then
    echo "MySQL not ready after 60 seconds"
    exit 1
fi

# Step 7: Import database dump with safety check
echo "Importing database dump..."
if docker exec "$MYSQL_CONTAINER" mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "use zentao" 2>/dev/null; then
    echo "Backing up existing database..."
    docker exec "$MYSQL_CONTAINER" mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" zentao > "$DOCKER_DATA_DIR/zentao-backup-$(date +%F-%H%M%S).sql" || {
        echo "Warning: Failed to back up existing database, proceeding anyway"
    }
    echo "Warning: Database 'zentao' already exists. Importing will overwrite it."
    read -p "Proceed? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Aborting to prevent database overwrite."
        exit 1
    fi
fi
docker cp "$MYSQL_DUMP_FILE" "$MYSQL_CONTAINER:/zentao.sql" || {
    echo "Failed to copy database dump to container"
    exit 1
}
docker exec "$MYSQL_CONTAINER" mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" zentao < /zentao.sql || {
    echo "Failed to import database"
    exit 1
}

# Step 8: Set permissions
echo "Setting permissions..."
chown -R 1000:1000 "$DOCKER_DATA_DIR/zentao-files" "$DOCKER_DATA_DIR/config" "$DOCKER_DATA_DIR/upload" "$DOCKER_DATA_DIR/mysql-data" || {
    echo "Failed to set permissions"
    exit 1
}

# Step 9: Start full Docker Compose
echo "Starting full ZenTao setup..."
cd "$COMPOSE_DIR" || {
    echo "Failed to navigate to $COMPOSE_DIR"
    exit 1
}
docker-compose up -d || {
    echo "Failed to start ZenTao"
    exit 1
}

echo "Data loaded successfully! Access ZenTao at http://localhost/zentao/"