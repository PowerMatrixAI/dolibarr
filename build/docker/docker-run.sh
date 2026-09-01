#!/usr/bin/env bash

set -Eeuo pipefail

: "${PHP_INI_DIR:=/usr/local/etc/php}"
: "${PHP_INI_DATE_TIMEZONE:=UTC}"
: "${PHP_INI_MEMORY_LIMIT:=256M}"
: "${PHP_INI_UPLOAD_MAX_FILESIZE:=32M}"
: "${PHP_INI_POST_MAX_SIZE:=32M}"
: "${PHP_INI_MAX_EXECUTION_TIME:=120}"
: "${DOLIBARR_DOCUMENTS_DIR:=/var/www/documents}"

documents_dir="${DOLIBARR_DOCUMENTS_DIR}"
conf_dir="/var/www/html/conf"
conf_file="${conf_dir}/conf.php"
php_ini_file="${PHP_INI_DIR}/conf.d/dolibarr.ini"

mkdir -p "${documents_dir}" "${conf_dir}"

if [ ! -e "${conf_file}" ]; then
	touch "${conf_file}"
fi

chown -R www-data:www-data "${documents_dir}" "${conf_dir}"
chmod 750 "${conf_dir}"
chmod 640 "${conf_file}"

cat > "${php_ini_file}" <<EOF
date.timezone = ${PHP_INI_DATE_TIMEZONE}
memory_limit = ${PHP_INI_MEMORY_LIMIT}
upload_max_filesize = ${PHP_INI_UPLOAD_MAX_FILESIZE}
post_max_size = ${PHP_INI_POST_MAX_SIZE}
max_execution_time = ${PHP_INI_MAX_EXECUTION_TIME}
EOF

# Enable Dolibarr's environment-driven installer only when requested.
if [ "${DOLI_AUTO_INSTALL:-0}" = "1" ] \
	&& [ ! -e /var/www/html/install/install.forced.php ] \
	&& [ -e /var/www/html/install/install.forced.sample.php ]; then
	cp /var/www/html/install/install.forced.sample.php /var/www/html/install/install.forced.php
fi

if [ "$#" -eq 0 ]; then
	set -- apache2-foreground
fi

exec "$@"
