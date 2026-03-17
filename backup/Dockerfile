ARG BORGMATIC_VERSION
FROM alpine:3.20 as builder                                                                                                                                                                      

ARG RCLONE_VERSION

RUN apk add --no-cache \
    curl \
    unzip

RUN curl -L -o simplepush.sh https://raw.githubusercontent.com/simplepush/send-encrypted/master/simplepush.sh \
    && echo "e2970d22510ee2f7e6033100ef71e9f6531080a3df4bb6952172730ba866f94f  simplepush.sh" | sha256sum -c -

RUN curl -O https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip \
    && echo "00a1d8cb85552b7b07bb0416559b2e78fcf9c6926662a52682d81b5f20c90535  rclone-${RCLONE_VERSION}-linux-amd64.zip" | sha256sum -c -
 
RUN unzip -j rclone-${RCLONE_VERSION}-linux-amd64.zip
RUN chmod 0755 simplepush.sh
RUN chmod 0755 rclone
 
FROM ghcr.io/borgmatic-collective/borgmatic:${BORGMATIC_VERSION}
# Install dependencies for simplepush.sh (bash, curl, openssl)
RUN apk add --no-cache bash curl openssl

COPY --from=builder /simplepush.sh /usr/local/bin/simplepush.sh
COPY --from=builder /rclone /usr/local/bin/rclone

# Ensure the scripts are executable in the final image
RUN chmod +x /usr/local/bin/simplepush.sh /usr/local/bin/rclone
