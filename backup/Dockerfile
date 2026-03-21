ARG BORGMATIC_VERSION
FROM alpine:3.20 as builder

ARG RCLONE_VERSION

RUN apk add --no-cache \
    curl \
    unzip

RUN curl -O https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip

RUN unzip -j rclone-${RCLONE_VERSION}-linux-amd64.zip
RUN chmod 0755 rclone

FROM ghcr.io/borgmatic-collective/borgmatic:${BORGMATIC_VERSION}
RUN apk add --no-cache curl openssl

COPY --from=builder /rclone /usr/local/bin/rclone
RUN chmod +x /usr/local/bin/rclone
