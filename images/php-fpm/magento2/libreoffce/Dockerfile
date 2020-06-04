ARG PHP_VERSION
FROM docker.io/magenius/php-fpm:${PHP_VERSION}-magento2
USER root

RUN yum install -y libreoffice \
    && yum clean all \
    && rm -rf /var/cache/yum

USER www-data
