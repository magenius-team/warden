ARG PHP_VERSION
FROM docker.io/wardenenv/php-fpm:${PHP_VERSION}-magento1
USER root

RUN set -eux \
    && dnf install -y php-pecl-xdebug \
    && dnf clean all \
    && rm -rf /var/cache/dnf

COPY debug/etc/*.ini /etc/
COPY debug/etc/php.d/*.ini /etc/php.d/

USER www-data
