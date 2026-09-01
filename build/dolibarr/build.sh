#!/bin/bash

set -Eeuo pipefail

environment="${1:-prod}"
project_dir="/home/code/dolibarr"
output_dir="${project_dir}/output/dolibarr"

if [[ ! "${environment}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
	echo "Invalid build environment: ${environment}" >&2
	exit 1
fi

if [ ! -d "${project_dir}/htdocs" ]; then
	echo "Dolibarr source directory was not found: ${project_dir}/htdocs" >&2
	exit 1
fi

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

rsync -a \
	--exclude='/conf/conf.php' \
	--exclude='/conf/conf.php.mysql' \
	--exclude='/conf/conf.php.old' \
	--exclude='/conf/conf.php.postgres' \
	"${project_dir}/htdocs/" "${output_dir}/htdocs/"

cp "${project_dir}/build/dolibarr/Dockerfile" "${output_dir}/Dockerfile"
cp "${project_dir}/build/dolibarr/entrypoint" "${output_dir}/entrypoint"

echo "Prepared Dolibarr source image context at ${output_dir}"

