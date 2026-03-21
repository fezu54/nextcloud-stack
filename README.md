# nextcloud-stack
This is my personal docker-compose stack to deploy Nextcloud on a self hosted machine. It includes https://github.com/b3vis/docker-borgmatic to create hot backups of the nextcloud volume (config, data, themes) and dumps of the running MariaDB.

## Vaultwarden
In addition to Nextcloud, this stack also deploys [Vaultwarden](https://github.com/dani-garcia/vaultwarden) to store your passwords and secrets. It is configured to use the standard SQLIte database which is also included in the borgmatic backup.
Other than that, currently only the `attachments` folder is included as well. For more information about backup and restore, check the [Vaultwarden documentation](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault).

## rclone configuration
[Rclone](https://rclone.org/) is used to automatically upload your local backups to a cloud provider. It can be configured via environment variables: https://rclone.org/docs/#environment-variables. The exact configuration depends on your cloud provider.

## ntfy (Notifications)
[ntfy](https://ntfy.sh/) is used to send notifications about backup status. To prevent unauthorized access to your notification topics, authentication should be enabled.

### Setup Authentication
1. Start the stack: `docker compose up -d`
2. Create an admin user (you will be prompted for a password):
   ```bash
   docker compose exec ntfy ntfy user add --role=admin your_username
   ```
3. Generate an access token for the backup service:
   ```bash
   docker compose exec ntfy ntfy token add your_username
   ```
4. Copy the generated token and add it to your `.env` file as `NTFY_TOKEN`.

### Smartphone App
To receive notifications on your mobile device, install the `ntfy` app:
- **Android (Google Play):** [ntfy - PUT/POST to your phone](https://play.google.com/store/apps/details?id=io.heckel.ntfy)
- **Android (F-Droid):** [ntfy on F-Droid](https://f-droid.org/packages/io.heckel.ntfy/)
- **iOS (Apple App Store):** [ntfy on the App Store](https://apps.apple.com/app/ntfy/id1625396347)

Once installed, add your self-hosted server in the app settings to start receiving notifications from your stack.

# Usage
1. Clone this repository
2. Create a .env file with following content:
```bash
COMPOSE_PROJECT_NAME=nextcloud
MYSQL_ROOT_PASSWORD={YOUR_SECRET_ROOT_PASSWORD}
DNS_ADDRESS={YOUR_DNS_ADDRESS}
VAULTWARDEN_PREFIX={YOUR_VAULTWARDEN_SUBDOMAIN}
VAULTWARDEN_ADMIN_TOKEN={YOUR_VAULTWARDEN_ADMIN_TOKEN}
NEXTCLOUD_PREFIX={YOUR_NEXTCLOUD_SUBDOMAIN}
LETSENCRYPT_EMAIL={YOUR_EMAIL_ADDRESS}
TZ={YOUR_TIMEZONE}  # cat /etc/timezone
BORG_PASSPHRASE={YOUR_SECURE_BORG_PASSWORD} # encrypts your backups, useful to upload the archive to services like AWS Glacier
VOLUME_TARGET={PATH_TO_YOUR_BACKUP_FOLDER}
NTFY_PREFIX={YOUR_NTFY_SUBDOMAIN}
NTFY_TOPIC={YOUR_NTFY_TOPIC}
NTFY_TOKEN={YOUR_NTFY_ACCESS_TOKEN}

# Check https://rclone.org/docs/#configure or your cloud provider documentation
RCLONE_CONFIG_NEXTCLOUD_TYPE=
RCLONE_CONFIG_NEXTCLOUD_PROVIDER=
RCLONE_CONFIG_NEXTCLOUD_ACL=
RCLONE_CONFIG_NEXTCLOUD_ACCESS_KEY_ID=
RCLONE_CONFIG_NEXTCLOUD_SECRET_ACCESS_KEY=
RCLONE_CONFIG_NEXTCLOUD_ENDPOINT=
```
3. Create a db.env file with following content:
```bash
MYSQL_PASSWORD={YOUR_SECRET_USER_PASSWORD}
MYSQL_USER={YOUR_SQL_USER_NAME}
MYSQL_DATABASE=nextcloud
```
4. Start or update stack with 
```
docker-compose build --pull
docker-compose up -d
```
5. Initialize the borg repository
```bash
docker exec nextcloud_borgmatic_backup_1 sh -c "borgmatic --init --encryption repokey-blake2"
```
6. Export borg repo key (to your backup folder)
```bash
docker exec nextcloud_borgmatic_backup_1 sh -c "borg key export /mnt/borg-repository /mnt/borg-repository/key-export.txt"
```
# Backups
The stack will automatically back up your running nextlcoud instance with the help of [borg](https://borgbackup.readthedocs.io/en/stable/index.html)/[borgmatic](https://torsion.org/borgmatic/). Per default, it will create a new backup every day at 1am. If you want to change this, adapt the [crontab.txt](https://github.com/fezu54/nextcloud-stack/blob/main/backup/borgmatic.d/crontab.txt) in this repository.

⚠️ It's important to save your borg repo key and the borgmatic passphrase somewhere secure. You'll need it to restore the backups.
## Nextcloud maintenance mode
This stack is not setting Nextcloud to [maintenance mode](https://docs.nextcloud.com/server/latest/admin_manual/maintenance/backup.html#maintenance-mode). If you want to enusre that no data is modified while backups are taken, you can set Nextcloud to maintenance mode via crontab before the backups are taken and release it once the backups are done.
## Restore backups
1. Run an interactive shell: `docker-compose -f docker-compose.yml -f docker-compose.restore.yml run borgmatic_backup_1`
2. Fuse-mount the backup: `borg mount /mnt/borg-repository <mount_point>`
3. Restore your files:
* Extract volume data: https://torsion.org/borgmatic/docs/how-to/extract-a-backup/
* Restore database: https://torsion.org/borgmatic/docs/how-to/backup-your-databases/#database-restoration
* General information about Nextcloud restore: https://docs.nextcloud.com/server/latest/admin_manual/maintenance/restore.html
5. Finally unmount and exit: `borg umount <mount_point> && exit.`

In case Borg fails to create/acquire a lock: `borg break-lock /mnt/repository`

