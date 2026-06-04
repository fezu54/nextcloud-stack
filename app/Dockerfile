FROM nextcloud:33-apache

RUN apt-get update && apt-get install -y --no-install-recommends \
    ocrmypdf \
    tesseract-ocr-eng \
    tesseract-ocr-deu \
    iproute2 \
    libfuse2 \
    && rm -rf /var/lib/apt/lists/*
