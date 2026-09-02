#!/bin/bash

set -Eeuo pipefail

environment="${1:-prod}"
project_dir="/home/code/dolibarr"
output_dir="${project_dir}/output/dolibarr"
config_file="${project_dir}/config/dolibarr/${environment}.ini"
application_config_file="${project_dir}/config/dolibarr/${environment}.conf.php"

if [[ ! "${environment}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
	echo "Invalid build environment: ${environment}" >&2
	exit 1
fi

if [ ! -d "${project_dir}/htdocs" ]; then
	echo "Dolibarr source directory was not found: ${project_dir}/htdocs" >&2
	exit 1
fi

if [ ! -f "${config_file}" ]; then
	echo "PHP ini configuration was not found: ${config_file}" >&2
	exit 1
fi

if [ ! -f "${application_config_file}" ]; then
	echo "Dolibarr application configuration was not found: ${application_config_file}" >&2
	exit 1
fi

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

cp -r "${project_dir}/htdocs" "${output_dir}/"
cp "${config_file}" "${output_dir}/php.ini"
cp "${application_config_file}" "${output_dir}/config.php"

rm -f \
	"${output_dir}/htdocs/conf/conf.php" \
	"${output_dir}/htdocs/conf/conf.php.mysql" \
	"${output_dir}/htdocs/conf/conf.php.old" \
	"${output_dir}/htdocs/conf/conf.php.postgres"

cp "${project_dir}/build/dolibarr/Dockerfile" "${output_dir}/Dockerfile"
cp "${project_dir}/build/dolibarr/entrypoint" "${output_dir}/entrypoint"

echo "Prepared Dolibarr ${environment} image context at ${output_dir}"
