FROM nextcloud:28-apache 
# Dependencies for facerecognition app
# ARG BUILD_DEPS="gnupg2 wget unzip libx11-dev libbz2-dev cmake"

# Build and install dlib
#RUN apt-get update ; \
#    apt-get install -y $BUILD_DEPS

#ARG DLIB_BRANCH=v19.24.2
#RUN wget -c -q https://github.com/davisking/dlib/archive/refs/tags/$DLIB_BRANCH.tar.gz \
#&& tar xf $DLIB_BRANCH.tar.gz \
#&& mv dlib-* dlib \
#&& cd dlib/dlib \
#&& mkdir build \
#&& cd build \
#&& cmake -DBUILD_SHARED_LIBS=ON .. -D CMAKE_BUILD_TYPE=Release \
#&& make \
#&& make install \
#&& cd ../../.. \
#&& rm -r dlib \
#&& rm $DLIB_BRANCH.tar.gz

# Build and install PDLib on builder
#ARG PDLIB_BRANCH=master
#RUN wget -c -q https://github.com/goodspb/pdlib/archive/$PDLIB_BRANCH.zip \
#&& mkdir -p /usr/src/php/ext/ \
#&& unzip -d /usr/src/php/ext/ $PDLIB_BRANCH.zip \
#&& rm $PDLIB_BRANCH.zip

#RUN docker-php-ext-install pdlib-$PDLIB_BRANCH

# Clean up build deps
#RUN apt-get autoremove -y $BUILD_DEPS

# Proceed with other Nextcloud stuff
RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ffmpeg \
				imagemagick \
				ghostscript \
        libmagickcore-6.q16-6-extra \
        procps \
        smbclient \
        supervisor \
        libreoffice \
        ocrmypdf \
        tesseract-ocr-eng \
        tesseract-ocr-deu \
    ; \
    rm -rf /var/lib/apt/lists/*

RUN set -ex; \
    \
    savedAptMark="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libbz2-dev \
        libc-client-dev \
        libkrb5-dev \
        libsmbclient-dev \
    ; \
    \
    docker-php-ext-configure imap --with-kerberos --with-imap-ssl; \
    docker-php-ext-install \
        bz2 \
        imap \
    ; \
    pecl install smbclient; \
    docker-php-ext-enable smbclient; \
    \
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); print so }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p \
    /var/log/supervisord \
    /var/run/supervisord \
;

COPY supervisord.conf /

ENV NEXTCLOUD_UPDATE=1

CMD ["/usr/bin/supervisord", "-c", "/supervisord.conf"]
