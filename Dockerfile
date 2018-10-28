FROM nimlang/nim:0.19.0-alpine

RUN nimble -y install commandeer
RUN nimble -y install parsetoml

RUN apk add --no-cache clang
# RUN apk add --no-cache openssl-dev
# RUN apk add --no-cache --repository http://dl-3.alpinelinux.org/alpine/edge/testing/ --allow-untrusted openssl-dev
RUN apk add --no-cache libressl-dev

RUN cat /etc/alpine-release
RUN clang --version
RUN nim --version

WORKDIR /src
