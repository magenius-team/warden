ARG PHP_VERSION
FROM docker.io/magenius/php-fpm:${PHP_VERSION}-magento2
USER root

RUN set -eux \
    && PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2 | awk -F '.' '{print $1$2}') \
    && yum --enablerepo=remi-php${PHP_VERSION} install -y php-pecl-xdebug \
    && yum clean all \
    && rm -rf /var/cache/yum

COPY debug/etc/*.ini /etc/
COPY debug/etc/php.d/*.ini /etc/php.d/

USER www-data
