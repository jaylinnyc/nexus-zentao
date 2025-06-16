# ZenTao Deployment Project

This project manages the deployment of ZenTao 12.3 (a project management software) on a production server using Docker and Docker Compose. The setup integrates with Traefik for reverse proxy, uses a dedicated MySQL instance for data storage, and is automated via a Jenkins pipeline for continuous deployment.

## Project Overview

The ZenTao deployment is configured to:
- Run ZenTao 12.3 on a Docker host, accessible at `https://pm.nexuslearning.org/zentao/`.
- Use Traefik for HTTPS routing via an external network (`traefik-net`).
- Store all ZenTao data in `~/mydata/zentao` on the production server.
- Include a dedicated MySQL container (`zentao-db`) for the ZenTao database.
- Automate deployment with a Jenkins pipeline, using a `Jenkinsfile` to transfer and apply `docker-compose.yaml`.

The project was migrated from a Z-Box installation to Docker to enable easier upgrades and scalability.

## ZenTao Data Structure

ZenTao stores its data in a combination of file-based and database components. The data is organized as follows, mapped to the external volume `~/mydata/zentao` on the production server:

- **ZenTao Application Files** (`~/mydata/zentao/zentao-files`):
  - Mounted to `/opt/zbox/app/zentao` in the ZenTao container.
  - Contains the core ZenTao PHP application, including modules, templates, and logic.
  - Example contents: `module/`, `www/`, `config.php`.
  - Purpose: Provides the application codebase, which is read-only except during upgrades.

- **Configuration Files** (`~/mydata/zentao/config`):
  - Mounted to `/opt/zbox/app/zentao/config` in the ZenTao container.
  - Stores ZenTao configuration, including database connection settings.
  - Key file: `my.php` (defines database host, user, password, etc.).
  - Purpose: Customizes ZenTao behavior and connectivity.

- **Attachments** (`~/mydata/zentao/upload`):
  - Mounted to `/opt/zbox/app/zentao/www/data/upload` in the ZenTao container.
  - Stores user-uploaded files (e.g., task attachments, bug reports).
  - Structure: Subdirectories (e.g., `1/`, `2/`) containing files named by timestamp or ID.
  - Purpose: Persists user-uploaded content.

- **MySQL Database Data** (`~/mydata/zentao/mysql-data`):
  - Mounted to `/var/lib/mysql` in the `zentao-db` container.
  - Contains the MySQL data files for the `zentao` database.
  - Includes tables like `zt_project`, `zt_task`, `zt_bug`, etc.
  - Purpose: Stores all structured data (projects, tasks, users, etc.).

The backup process (via `backup_zentao.sh`) captures these directories and a database dump (`zentao.sql`) to ensure full data recovery.

## How to Run the ZenTao Application

### Prerequisites
- **Production Server**:
  - Docker and Docker Compose installed (`sudo apt-get install docker.io docker-compose`).
  - Traefik running with the `traefik-net` network (`docker network ls | grep traefik-net`).
  - Directory `~/mydata/zentao` created (`mkdir -p ~/mydata/zentao`).
  - SSH access configured with a user (e.g., `user@docker-host-ip`).
- **SCM Repository**:
  - Contains `docker-compose.yaml` and `Jenkinsfile`.
  - Accessible by Jenkins for pipeline execution.
- **Jenkins**:
  - SSH Agent plugin installed.
  - SSH credential (`jenkins-docker`) configured for production server access.
- **DNS**:
  - `pm.nexuslearning.org` resolves to the production server’s IP or is handled by Traefik.

### Manual Deployment
To run ZenTao manually (e.g., for testing or initial setup):

1. **Prepare Data**:
   - Ensure ZenTao data is in `~/mydata/zentao` (`zentao-files`, `config`, `upload`, `mysql-data`).
   - If migrating from a backup, use `load_zentao_backup.sh` (see previous instructions) to extract and load data:
     ```bash
     ./load_zentao_backup.sh
     ```

2. **Copy Docker Compose**:
   - Place `docker-compose.yaml` in `~/mydata/zentao` on the production server:
     ```bash
     scp docker-compose.yaml user@docker-host-ip:~/mydata/zentao/
     ```

3. **Start Containers**:
   - SSH into the production server:
     ```bash
     ssh user@docker-host-ip
     ```
   - Navigate to the directory and run:
     ```bash
     cd ~/mydata/zentao
     docker-compose up -d
     ```

4. **Verify**:
   - Check container status:
     ```bash
     docker-compose ps
     ```
   - View logs:
     ```bash
     docker logs zentao
     docker logs zentao-db
     ```
   - Access ZenTao at `https://pm.nexuslearning.org/zentao/` and log in (default: `admin`/`123456` unless changed).
   - Verify projects, tasks, and attachments are intact.

### Automated Deployment (Jenkins)
The Jenkins pipeline automates deployment:

1. **Configure Jenkins**:
   - Create a pipeline job.
   - Set the SCM repository URL and credentials.
   - Point to the `Jenkinsfile` in the repository root.
   - Ensure the `jenkins-docker` SSH credential is configured.

2. **Update Jenkinsfile**:
   - Edit `prodUser` and `prodHost` in the `Jenkinsfile` (e.g., `user` and `docker-host-ip`).
   - Commit and push to the repository:
     ```bash
     git commit -m "Update Jenkinsfile"
     git push
     ```

3. **Run Pipeline**:
   - Trigger the pipeline manually or via a webhook.
   - The pipeline will:
     - Check out `docker-compose.yaml` and `Jenkinsfile`.
     - Transfer `docker-compose.yaml` to `~/mydata/zentao`.
     - Pull images and deploy ZenTao and `zentao-db`.

4. **Verify**:
   - Monitor Jenkins console output.
   - Access `https://pm.nexuslearning.org/zentao/` to confirm the deployment.

## How to Upgrade to a Later Version

To upgrade ZenTao (e.g., from 12.3 to 12.4 or later):

### Prerequisites
- **Backup**: Create a full backup using `backup_zentao.sh` (see previous instructions):
  ```bash
  ./backup_zentao.sh
  ```
  Store the backup (e.g., `zentao-backup-2025-06-15_2119.tar.gz`) securely.
- **Release Notes**: Check the ZenTao website (https://www.zentao.pm/download.html) for release notes and upgrade requirements.
- **Docker Image**: Verify the `idoop/zentao` image supports the target version (e.g., `idoop/zentao:12.4.stable`).

### Steps
1. **Update Docker Compose**:
   - Edit `docker-compose.yaml` in the SCM repository:
     - Change the `zentao` service’s image tag (e.g., `image: idoop/zentao:12.4.stable`).
     - Update the `ZENTAO_VER` environment variable (e.g., `ZENTAO_VER=12.4.stable`).
     - Example:
       ```yaml
       services:
         zentao:
           image: idoop/zentao:12.4.stable
           environment:
             - ZENTAO_VER=12.4.stable
             - BIND_ADDRESS=false
       ```
   - Commit and push:
     ```bash
     git commit -m "Upgrade ZenTao to 12.4"
     git push
     ```

2. **Run Jenkins Pipeline**:
   - Trigger the Jenkins pipeline.
   - The pipeline will:
     - Transfer the updated `docker-compose.yaml` to `~/mydata/zentao`.
     - Pull the new image (`idoop/zentao:12.4.stable`).
     - Recreate containers with `docker-compose up -d --force-recreate`.

3. **Run Upgrade Script**:
   - Access the upgrade page:
     - Open `https://pm.nexuslearning.org/upgrade.php` in a browser.
     - Log in as an admin (e.g., `admin`/`123456` unless changed).
     - Follow the on-screen prompts to complete the database and file upgrades.
   - If prompted to create an `ok.txt` file:
     ```bash
     ssh user@docker-host-ip "docker exec zentao touch /opt/zbox/app/zentao/www/ok.txt"
     ```

4. **Verify Upgrade**:
   - Check the ZenTao version in the admin panel (`https://pm.nexuslearning.org/zentao/admin.php`).
   - Test core features (projects, tasks, bugs, attachments).
   - View logs for errors:
     ```bash
     ssh user@docker-host-ip "docker logs zentao && docker logs zentao-db"
     ```

5. **Clean Up**:
   - If the upgrade is successful, remove old backups or unused images:
     ```bash
     ssh user@docker-host-ip "docker image prune"
     ```
   - Keep at least one recent backup until the upgrade is fully validated.

### Incremental Upgrades
- Upgrade one minor version at a time (e.g., 12.3 → 12.4 → 12.5) to minimize risks.
- Refer to the ZenTao upgrade manual (https://www.zentao.pm/book/zentaomanual/free-open-source-project-management-software-upgradezentao-18.html) for version-specific instructions.
- If issues arise, restore the backup using `load_zentao_backup.sh` and retry.

## Troubleshooting
- **Traefik Issues**:
  - If `pm.nexuslearning.org` fails, check Traefik logs:
    ```bash
    ssh user@docker-host-ip "docker logs traefik"
    ```
  - Verify `traefik-net` and DNS configuration.
- **MySQL Errors**:
  - If `zentao-db` fails, check logs:
    ```bash
    ssh user@docker-host-ip "docker logs zentao-db"
    ```
  - Test connectivity:
    ```bash
    ssh user@docker-host-ip "docker exec zentao-db mysql -u root -p123456 -e 'SHOW DATABASES;'"
    ```
- **Permissions**:
  - Fix data directory permissions:
    ```bash
    ssh user@docker-host-ip "chown -R 1000:1000 ~/mydata/zentao"
    ```
- **Jenkins**:
  - If the pipeline fails, check the console output for SCP or SSH errors.
  - Verify the `jenkins-docker` credential and SSH access:
    ```bash
    ssh user@docker-host-ip "whoami"
    ```
- **Support**: Contact ZenTao support at `support@zentao.pm` or check community resources (https://www.zentao.pm).

## Security Notes
- Change default credentials (`admin`/`123456` for ZenTao, `root`/`123456` for MySQL):
  ```bash
  ssh user@docker-host-ip "docker exec zentao-db mysql -u root -p123456 -e \"SET PASSWORD FOR 'root'@'%' = PASSWORD('new-password');\""
  ```
- Consider using Docker secrets for the MySQL password in `docker-compose.yaml`.
- Restrict SSH access to the production server with key-based authentication.