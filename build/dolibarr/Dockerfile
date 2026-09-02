# syntax=docker/dockerfile:1

FROM hkccr.ccs.tencentyun.com/kol-base/box:v1.0.2

WORKDIR /var/www/html

COPY htdocs/ /var/www/html/
COPY config.php /var/www/html/conf/conf.php
COPY php.ini /usr/local/etc/php/conf.d/dolibarr.ini
COPY entrypoint /usr/local/bin/dolibarr-entrypoint

RUN mkdir -p /var/www/html/conf /var/www/documents \
    && chown -R root:root /var/www/html \
    && chown -R www-data:www-data /var/www/html/conf /var/www/documents \
    && chmod 750 /var/www/html/conf \
    && chmod +x /usr/local/bin/dolibarr-entrypoint

EXPOSE 80

ENTRYPOINT ["dolibarr-entrypoint"]
CMD ["apache2-foreground"]
