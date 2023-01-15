FROM alpine:3.17.0 as builder
RUN apk add --no-cache curl
RUN curl -O https://raw.githubusercontent.com/simplepush/send-encrypted/master/simplepush.sh
RUN chmod 0700 simplepush.sh

FROM b3vis/borgmatic:1.7.5
COPY --from=builder simplepush.sh /usr/local/bin/

