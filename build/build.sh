#!/bin/bash

set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"

IMAGE_NAME="hkccr.ccs.tencentyun.com/kol-base/package:v1.0.2"
CONTAINER_NAME="package"
HOST_DIR="${HOST_DIR:-${project_dir}}"
CONTAINER_DIR="/home/code/dolibarr"
IMAGE="hkccr.ccs.tencentyun.com/kol-test"
environment="${DOLIBARR_ENVIRONMENT:-prod}"
module="dolibarr"
version=""

usage() {
	echo "Usage: $0 [options]"
	echo "Options:"
	echo "  -m MODULE       Build module (only dolibarr is available)"
	echo "  -e ENV          Build environment label (default: prod)"
	echo "  -v VERSION      Application image tag (default: v1.0.0)"
	echo "  -h              Display this help message"
	echo
	echo "Environment variables:"
	echo "  HOST_DIR, CONTAINER_NAME, DOLIBARR_ENVIRONMENT"
	exit 0
}

while getopts ":m:e:v:ph" opt; do
	case "${opt}" in
		m)
			module="${OPTARG}"
			;;
		e)
			environment="${OPTARG}"
			;;
		v)
			version="${OPTARG}"
			;;
		h)
			usage
			;;
		\?)
			echo "Unknown option: -${OPTARG}" >&2
			exit 1
			;;
		:)
			echo "Option -${OPTARG} requires an argument" >&2
			exit 1
			;;
	esac
done

version="${version:-v1.0.0}"

if [ "${module}" != "dolibarr" ] && [ "${module}" != "all" ]; then
	echo "Only the dolibarr module is available" >&2
	exit 1
fi

if [ "${module}" = "all" ]; then
	module="dolibarr"
fi

for value in "${environment}" "${version}"; do
	if [[ ! "${value}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
		echo "Invalid value: ${value}" >&2
		exit 1
	fi
done

if ! command -v docker >/dev/null 2>&1; then
	echo "Docker CLI is required" >&2
	exit 1
fi

if ! docker info >/dev/null 2>&1; then
	echo "Docker daemon is not running" >&2
	exit 1
fi

if [ ! -d "${HOST_DIR}" ]; then
	echo "Host source directory does not exist: ${HOST_DIR}" >&2
	exit 1
fi

if ! docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
	echo "Creating package container: ${CONTAINER_NAME}"
	docker run --name "${CONTAINER_NAME}" \
		-v "${HOST_DIR}:${CONTAINER_DIR}" \
		-d "${IMAGE_NAME}" \
		tail -f /dev/null >/dev/null
fi

if [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}")" != "true" ]; then
	docker start "${CONTAINER_NAME}" >/dev/null
fi

echo "Preparing application source with package environment"
docker exec "${CONTAINER_NAME}" \
	/bin/bash -c "bash ${CONTAINER_DIR}/build/${module}/build.sh ${environment}"

docker login "${IMAGE%%/*}"

echo "Building application image: ${IMAGE}/${module}:${version}"
docker build \
	-t "${IMAGE}/${module}:${version}" \
	-f "${project_dir}/output/${module}/Dockerfile" \
	"${project_dir}/output/${module}"

docker push "${IMAGE}/${module}:${version}"

echo
echo "Application image: ${IMAGE}/${module}:${version}"
echo "Build context: ${project_dir}/output/${module}"
