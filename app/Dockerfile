FROM nextcloud:35-apache

RUN apt-get update && apt-get install -y --no-install-recommends \
    ocrmypdf \
    tesseract-ocr-eng \
    tesseract-ocr-deu \
    iproute2 \
    libfuse2 \
    && rm -rf /var/lib/apt/lists/*

# Schedule automatic Nextcloud app updates twice daily (at 02:00 and 14:00)
RUN echo '' >> /var/spool/cron/crontabs/www-data \
    && echo '0 2,14 * * * php -f /var/www/html/occ app:update --all' >> /var/spool/cron/crontabs/www-data

