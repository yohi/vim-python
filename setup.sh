#!/bin/bash

ESC=$(printf '\033')

echo Application Root? [default: django/project]:
read INPUT_APPLICATION_ROOT

APPLICATION_ROOT=${INPUT_APPLICATION_ROOT:-"django/project"}

echo Docker Compose Service Name? [default: app]:
read INPUT_DOCKER_COMPOSE_SERVICE_NAME
DOCKER_COMPOSE_SERVICE_NAME=${INPUT_DOCKER_COMPOSE_SERVICE_NAME:-"app"}

docker compose create ${DOCKER_COMPOSE_SERVICE_NAME}
VOLUME_PATH=$(docker inspect --format='{{.Mounts}}' $(docker-compose ps -q ${DOCKER_COMPOSE_SERVICE_NAME}) | tr " " "\n" | grep volume | grep site-packages-data)
DELETE_VOLUME_NAME=$(docker inspect --type='container' $(docker compose ps -q app) | jq -r '.[].Mounts[] | select(has("Name")) | select(.Name | contains("app")) | .Name')
docker compose rm ${DOCKER_COMPOSE_SERVICE_NAME} -s -f -v
docker volume rm -f ${DELETE_VOLUME_NAME}

ls -l /home/y_ohi/.local/share/docker/volumes/j_league-app_site-packages-data/_data

echo Host Python Version Check...
HOST_PYTHON_VERSION=$(python3 --version | sed -E "s/\s|\.[0-9]+$//g")
printf "${ESC}[31m%s${ESC}[m\n" ${HOST_PYTHON_VERSION}

if [ -e compose.override.yaml ]; then
    mv compose.override.yaml "compose.override.yaml.bk.$(date "+%Y%m%d%H%M%S")"
fi

cat <<EOF > compose.override.yaml
volumes:
  ${DOCKER_COMPOSE_SERVICE_NAME}_site-packages-data:
    driver: local
networks:
  shared:
    external: true
EOF

echo Docker Python Version Check...
DOCKER_PYTHON_VERSION=$(docker-compose run --rm ${DOCKER_COMPOSE_SERVICE_NAME} python3 --version | sed -E "s/\s|\.[0-9]+\s*$//g")
printf "${ESC}[31m%s${ESC}[m\n" ${DOCKER_PYTHON_VERSION}

cat <<EOF >> compose.override.yaml
services:
  ${DOCKER_COMPOSE_SERVICE_NAME}:
    volumes:
      - ${DOCKER_COMPOSE_SERVICE_NAME}_site-packages-data:/usr/local/lib/${DOCKER_PYTHON_VERSION,,}/site-packages
    networks:
      - default
      - shared
EOF

echo Volume Path...
docker volume create ${DELETE_VOLUME_NAME}
printf "${ESC}[31m%s${ESC}[m\n" ${VOLUME_PATH}

ls -l ${VOLUME_PATH}

if [ -e ${APPLICATION_ROOT}/.venv ]; then
    rm -rf ${APPLICATION_ROOT}/.venv
fi

rm -rf ${APPLICATION_ROOT}/.venv/lib/${HOST_PYTHON_VERSION,,}/site-packages/

python3 -m venv ${APPLICATION_ROOT}/.venv


cd ${APPLICATION_ROOT}/.venv/lib/${HOST_PYTHON_VERSION,,}
cp -rp site-packages/* ${VOLUME_PATH}/
rm -rf site-packages
ln -s ${VOLUME_PATH} site-packages
cd - 1> /dev/null

cat <<EOF > ${APPLICATION_ROOT}/.envrc
source .venv/bin/activate
EOF
direnv allow ${APPLICATION_ROOT}
wait

echo Install PIP Package...
cd ${APPLICATION_ROOT}
source .venv/bin/activate
pip3 install -r ../requirements-dev.txt --force-reinstall
cd -
docker-compose build
docker-compose run --rm ${DOCKER_COMPOSE_SERVICE_NAME} pip install -r /tmp/requirements-dev.txt --force-reinstall

