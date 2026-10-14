FROM magento2-integration-integration-php:latest

USER root
RUN pecl install xdebug-3.5.0 && docker-php-ext-enable xdebug
COPY composer.json composer.lock /opt/apih-coverage/
RUN COMPOSER_ALLOW_SUPERUSER=1 composer install --working-dir=/opt/apih-coverage \
    --no-dev --no-interaction --prefer-dist --no-progress
COPY coverage.ini /usr/local/etc/php/conf.d/zz-apih-coverage.ini
