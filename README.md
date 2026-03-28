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

## 1. Secret Management (Vaultwarden)
This stack is designed to be deployed securely using your local **Vaultwarden** (via `rbw`). Instead of keeping sensitive `.env` files on your server, create a single item in your vault (e.g., named `.env` in a "Nextcloud stack" folder) and add all your variables to its **Note** field in `KEY=VALUE` format:

```text
COMPOSE_PROJECT_NAME=nextcloud
MYSQL_ROOT_PASSWORD=...
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
MYSQL_PASSWORD=...
DNS_ADDRESS=...
VAULTWARDEN_PREFIX=...
NEXTCLOUD_PREFIX=...
LETSENCRYPT_EMAIL=...
TZ=...
BORG_PASSPHRASE=...
VOLUME_TARGET=...
NTFY_PREFIX=...
NTFY_TOPIC=...
NTFY_TOKEN=...

# rclone config
RCLONE_CONFIG_NEXTCLOUD_TYPE=...
...
```

## 2. Deploy the Stack
Use the provided `deploy.sh` script to sync your files and inject secrets from your vault directly into the remote server's memory.

```bash
# Unlock your local vault first
rbw unlock

# Run the deployment script
./deploy.sh \
  --user your_ssh_user \
  --host your_server_ip \
  --path ~/nextcloud-stack \
  --item .env \
  --folder "Nextcloud stack"
```

The script will:
1. Fetch secrets from your local `rbw`.
2. Sync the stack files to your remote server via `rsync`.
3. Pull the latest images.
4. Rebuild custom images (like backup/proxy) with the latest patches.
5. Start/Restart the containers with the injected secrets.

## 3. Initializing the Stack
If this is a fresh installation:
1. Initialize the borg repository:
   ```bash
   ssh your_ssh_user@your_server_ip "cd ~/nextcloud-stack && docker compose exec borgmatic_backup borgmatic --init --encryption repokey-blake2"
   ```
2. Export the borg repo key:
   ```bash
   ssh your_ssh_user@your_server_ip "cd ~/nextcloud-stack && docker compose exec borgmatic_backup borg key export /mnt/borg-repository /mnt/borg-repository/key-export.txt"
   ```

## 4. First Time Setup (Bootstrap)
If you are deploying this stack for the very first time (and don't have a Vaultwarden account yet):

1.  **Run in New Mode:**
    ```bash
    ./deploy.sh --user your_user --host your_ip --path ~/nextcloud-stack --new
    ```
    Enter your desired passwords and config when prompted.
2.  **Create Vaultwarden Account:**
    Once the stack is up, go to `https://vault.yourdomain.com` and register your account.
3.  **Connect rbw Locally:**
    ```bash
    rbw config set base_url https://vault.yourdomain.com
    rbw login
    ```
4.  **Migrate Secrets:**
    Create a new item in your vault named `.env` and paste the variables you used in step 1 into the **Notes** field.
5.  **Future Deploys:**
    From now on, you can just use the standard command without the `--new` flag.

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

