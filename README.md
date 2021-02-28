# nextcloud-stack
This is my personal docker-compose stack to deploy Nextcloud on a self hosted machine. It includes https://github.com/b3vis/docker-borgmatic to create hot backups of the nextcloud volume (config, data, themes) and dumps of the running MariaDB.
# Usage
1. Clone this repository
2. Create a .env file with following content:
```bash
COMPOSE_PROJECT_NAME=nextcloud
MYSQL_ROOT_PASSWOR={YOUR_SECRET_ROOT_PASSWORD}
DNS_ADDRESS={YOUR_DNS_ADDRESS}
LETSENCRYPT_EMAIL={YOUR_EMAIL_ADDRESS}
TZ={YOUR_TIMEZONE}  # cat /etc/timezone
BORG_PASSPHRASE={YOUR_SECURE_BORG_PASSWORD} # encrypts your backups, useful to upload the archive to services like AWS Glacier
VOLUME_TARGET={PATH_TO_YOUR_BACKUP_FOLDER}
```
3. Create a db.env file with following content:
```bash
MYSQL_PASSWORD={YOUR_SECRET_USER_PASSWORD}
MYSQL_USER={YOUR_SQL_USER_NAME}
MYSQL_DATABASE=nextcloud
```
4. Start or update stack with 
```
docker-compse build --pull
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
# pico cms
The docker-compose file mounts pico cms theme into the the app container. If you don't use it, simply remove it from the `app` declaration in the docker-compose file.

# backups
The stack will automatically back up your running nextlcoud instance with the help of [borg](https://borgbackup.readthedocs.io/en/stable/index.html)/[borgmatic](https://torsion.org/borgmatic/). Per default, it will create a new backup every day at 1am. If you want to change this, adapt the [crontab.txt](https://github.com/fezu54/nextcloud-stack/blob/main/backup/borgmatic.d/crontab.txt) in this repository.

⚠️ It's important to save your borg repo key and the borgmatic passphrase somewhere secure. You'll need it to restore the backups.
## Nextcloud maintenance mode
This stack is not setting Nextcloud to [maintenance mode](https://docs.nextcloud.com/server/latest/admin_manual/maintenance/backup.html#maintenance-mode). If you want to enusre that no data is modified while backups are taken, you can set Nextcloud to maintenance mode via crontab before the backups are taken and release it once the backups are done.
## restore backups
1. Run an interactive shell: docker-compose -f docker-compose.yml -f docker-compose.restore.yml run borgmatic_backuo
2. Fuse-mount the backup: borg mount /mnt/borg-repository <mount_point>
3. Restore your files:
* Extract volume data: https://torsion.org/borgmatic/docs/how-to/extract-a-backup/
* Restore database: https://torsion.org/borgmatic/docs/how-to/backup-your-databases/#database-restoration
* General information about Nextcloud restore: https://docs.nextcloud.com/server/latest/admin_manual/maintenance/restore.html
5. Finally unmount and exit: borg umount <mount_point> && exit.

In case Borg fails to create/acquire a lock: borg break-lock /mnt/repository
