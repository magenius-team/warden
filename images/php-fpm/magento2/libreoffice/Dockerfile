ARG ENV_SOURCE_IMAGE="wardenenv/php-fpm"
ARG PHP_VERSION
FROM ${ENV_SOURCE_IMAGE}:${PHP_VERSION}-magento2
USER root

RUN dnf install -y libreoffice-base \
    && dnf clean all \
    && rm -rf /var/cache/dnf

USER www-data
