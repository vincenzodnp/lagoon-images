ARG IMAGE_REPO

FROM ${IMAGE_REPO:-lagoon}/mariadb as mariadb
FROM ${IMAGE_REPO:-lagoon}/commons as commons

FROM alpine:3.12.7

LABEL org.opencontainers.image.authors="The Lagoon Authors" maintainer="The Lagoon Authors"
LABEL org.opencontainers.image.source="https://github.com/uselagoon/lagoon-images" repository="https://github.com/uselagoon/lagoon-images"

RUN apk update \
    && apk upgrade \
    && apk add --no-cache bash curl ca-certificates grep ncdu openssl perl perl-doc rsync sed socat tar \
        mariadb-mytop \
        mongodb-tools \
        mysql-client \
        postgresql-client \
        redis \
    && update-ca-certificates \
    && rm -rf /var/cache/apk/* \
    && wget https://raw.githubusercontent.com/major/MySQLTuner-perl/master/mysqltuner.pl -O mysqltuner.pl \
    && chmod +x mysqltuner.pl

# Copy commons files
COPY --from=commons /lagoon /lagoon
COPY --from=commons /bin/fix-permissions /bin/ep /bin/docker-sleep /bin/wait-for /bin/
COPY --from=commons /sbin/tini /sbin/
COPY --from=commons /home /home

COPY --from=mariadb /usr/bin/my_print_defaults /usr/bin/my_print_defaults
