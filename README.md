# nextcloud-stack
This is my personal docker-compose stack to deploy Nextcloud on a self hosted machine. 
# Usage
1. Clone this repository
2. Create a .env file with following content:
```bash
COMPOSE_PROJECT_NAME=nextcloud
MYSQL_ROOT_PASSWOR={YOUR_SECRET_ROOT_PASSWORD}
DNS_ADDRESS={YOUR_DNS_ADDRESS}
LETSENCRYPT_EMAIL={YOUR_EMAIL_ADDRESS}
```
3. Create a db.env file with following content:
```bash
MYSQL_PASSWORD={YOUR_SECRET_USER_PASSWORD}
MYSQL_USER={YOUR_SQL_USER_NAME}
MYSQL_DATABASE=nextcloud
```
4. Start or update stack with 
```
docker-compose up -d
```

# pico cms
The docker-compose file mounts pico cms theme into the the app container. If you don't use it, simply remove it from the `app` declaration in the docker-compose file.
