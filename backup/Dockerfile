ARG BORGMATIC_VERSION
FROM alpine:3.17.0 as builder                                                                                                                                                                      

ARG RCLONE_VERSION

RUN apk add --no-cache \
    curl \
    unzip
RUN curl -O https://raw.githubusercontent.com/simplepush/send-encrypted/master/simplepush.sh
RUN curl -O https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip
 
RUN unzip -j rclone-${RCLONE_VERSION}-linux-amd64.zip
RUN chmod 0700 simplepush.sh
RUN chmod 0700 rclone
 
FROM b3vis/borgmatic:${BORGMATIC_VERSION}
COPY --from=builder simplepush.sh /usr/local/bin/
COPY --from=builder rclone /usr/local/bin/
