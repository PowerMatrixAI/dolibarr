#!/usr/bin/env bash

set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
docker_dir="${project_dir}/build/docker"

version_major="$(sed -n "s/^[[:space:]]*define('DOL_MAJOR_VERSION',[[:space:]]*'\([^']*\)').*/\1/p" "${project_dir}/htdocs/version.inc.php")"
version_minor="$(sed -n "s/^[[:space:]]*define('DOL_MINOR_VERSION',[[:space:]]*'\([^']*\)').*/\1/p" "${project_dir}/htdocs/version.inc.php")"

if [ -z "${version_major}" ] || [ -z "${version_minor}" ]; then
	echo "Unable to read Dolibarr version from htdocs/version.inc.php" >&2
	exit 1
fi

environment="${DOLIBARR_ENVIRONMENT:-prod}"
version="${DOLIBARR_VERSION:-${version_major}.${version_minor}}"
php_build_jobs="${PHP_BUILD_JOBS:-2}"
registry="${DOCKER_REGISTRY:-}"
repository="${DOCKER_REPOSITORY:-kol-base}"
output_dir="${OUTPUT_DIR:-${project_dir}/output}"
no_cache=0
push=0
run=0

usage() {
	cat <<EOF
Usage: $0 [options]

Build the Dolibarr package and runtime images.

Options:
  -e ENV                 Build environment label (default: prod)
  -v VERSION             Image/source version (default: version.inc.php)
  -r REGISTRY            Optional image registry
  -n REPOSITORY          Base image repository (default: kol-base)
  -o DIRECTORY           Export directory (default: ./output)
  -p                     Push both images after building
  --run                  Recreate and start the runtime container
  --no-cache             Build without Docker cache
  -h, --help             Show this help

Runtime options are read from the environment:
  HOST_PORT, CONTAINER_NAME, DOLI_AUTO_INSTALL, DOLI_DATABASE,
  DOLI_DB_SERVER, DOLI_DB_PASSWORD, DOLI_ROOT_PASSWORD
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		-e)
			[ "$#" -ge 2 ] || { echo "-e requires a value" >&2; exit 1; }
			environment="$2"
			shift 2
			;;
		-v)
			[ "$#" -ge 2 ] || { echo "-v requires a value" >&2; exit 1; }
			version="$2"
			shift 2
			;;
		-r)
			[ "$#" -ge 2 ] || { echo "-r requires a value" >&2; exit 1; }
			registry="${2%/}"
			shift 2
			;;
		-n)
			[ "$#" -ge 2 ] || { echo "-n requires a value" >&2; exit 1; }
			repository="${2#/}"
			shift 2
			;;
		-o)
			[ "$#" -ge 2 ] || { echo "-o requires a value" >&2; exit 1; }
			output_dir="$2"
			shift 2
			;;
		-p)
			push=1
			shift
			;;
		--run)
			run=1
			shift
			;;
		--no-cache)
			no_cache=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 1
			;;
	esac
done

if [[ ! "${environment}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
	echo "Invalid environment: ${environment}" >&2
	exit 1
fi

if [[ ! "${version}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
	echo "Invalid version: ${version}" >&2
	exit 1
fi

if [[ ! "${php_build_jobs}" =~ ^[1-9][0-9]*$ ]]; then
	echo "Invalid PHP_BUILD_JOBS: ${php_build_jobs}" >&2
	exit 1
fi

if [ -n "${registry}" ]; then
	image_root="${registry%/}/${repository#/}"
else
	image_root="${repository#/}"
fi

package_image="${image_root}/package:${version}"
box_image="${image_root}/box:${version}"
container_name="${CONTAINER_NAME:-dolibarr-box}"
host_port="${HOST_PORT:-8080}"
conf_volume="${DOLIBARR_CONF_VOLUME:-dolibarr-conf}"
documents_volume="${DOLIBARR_DOCUMENTS_VOLUME:-dolibarr-documents}"

if ! command -v docker >/dev/null 2>&1; then
	echo "Docker CLI is required" >&2
	exit 1
fi

if ! docker info >/dev/null 2>&1; then
	echo "Docker daemon is not running" >&2
	exit 1
fi

build_options=()
if [ "${no_cache}" -eq 1 ]; then
	build_options+=(--no-cache)
fi

echo "Building package image: ${package_image}"
docker build "${build_options[@]}" \
	--build-arg "DOLIBARR_ENVIRONMENT=${environment}" \
	--build-arg "PHP_BUILD_JOBS=${php_build_jobs}" \
	--build-arg "DOLIBARR_VERSION=${version}" \
	-f "${docker_dir}/Dockerfile_package" \
	-t "${package_image}" \
	"${project_dir}"

mkdir -p "${output_dir}"
package_container="dolibarr-package-export-$$"
cleanup() {
	docker rm -f "${package_container}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker create --name "${package_container}" "${package_image}" >/dev/null
docker cp "${package_container}:/package/dolibarr-${version}.tar.gz" "${output_dir}/"
cleanup
trap - EXIT

echo "Building runtime image: ${box_image}"
docker build "${build_options[@]}" \
	--build-arg "PHP_BUILD_JOBS=${php_build_jobs}" \
	--build-arg "DOLIBARR_VERSION=${version}" \
	-f "${docker_dir}/Dockerfile_box" \
	-t "${box_image}" \
	"${project_dir}"

if [ "${push}" -eq 1 ]; then
	echo "Pushing package image: ${package_image}"
	docker push "${package_image}"
	echo "Pushing runtime image: ${box_image}"
	docker push "${box_image}"
fi

if [ "${run}" -eq 1 ]; then
	if docker container inspect "${container_name}" >/dev/null 2>&1; then
		echo "Removing existing container: ${container_name}"
		docker rm -f "${container_name}" >/dev/null
	fi

	run_environment=(--env "DOLI_AUTO_INSTALL=${DOLI_AUTO_INSTALL:-0}")
	for variable_name in DOLI_DATABASE DOLI_DB_SERVER DOLI_DB_PASSWORD DOLI_ROOT_PASSWORD; do
		if [ -n "${!variable_name:-}" ]; then
			run_environment+=(--env "${variable_name}=${!variable_name}")
		fi
	done

	docker run -d \
		--name "${container_name}" \
		--restart unless-stopped \
		-p "${host_port}:80" \
		-v "${conf_volume}:/var/www/html/conf" \
		-v "${documents_volume}:/var/www/documents" \
		"${run_environment[@]}" \
		"${box_image}" >/dev/null

	echo "Dolibarr is running at http://127.0.0.1:${host_port}"
fi

cat <<EOF

Completed.
Package image: ${package_image}
Runtime image: ${box_image}
Release archive: ${output_dir}/dolibarr-${version}.tar.gz
EOF
