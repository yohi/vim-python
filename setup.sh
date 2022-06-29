#!/bin/bash

ESC=$(printf '\033')

echo Application Root? [default: django/project]:
read INPUT_APPLICATION_ROOT

APPLICATION_ROOT=${INPUT_APPLICATION_ROOT:-"django/project"}

echo Docker Compose Service Name? [default: app]:
read INPUT_DOCKER_COMPOSE_SERVICE_NAME
DOCKER_COMPOSE_SERVICE_NAME=${INPUT_DOCKER_COMPOSE_SERVICE_NAME:-"app"}

echo Host Python Version Check...
HOST_PYTHON_VERSION=$(python3 --version | sed -E "s/\s|\.[0-9]+$//g")
printf "${ESC}[31m%s${ESC}[m\n" ${HOST_PYTHON_VERSION}

if [ -d docker-compose.override.yml ]; then
    mv docker-compose.override.yml docker-compose.override.yml.bk
fi

cat <<EOF > docker-compose.override.yml
volumes:
    ${DOCKER_COMPOSE_SERVICE_NAME}_site-packages-data:
        driver: local
EOF

echo Docker Python Version Check...
DOCKER_PYTHON_VERSION=$(docker-compose run --rm ${DOCKER_COMPOSE_SERVICE_NAME} python3 --version | sed -E "s/\s|\.[0-9]+\s*$//g")
printf "${ESC}[31m%s${ESC}[m\n" ${DOCKER_PYTHON_VERSION}

cat <<EOF >> docker-compose.override.yml
services:
    ${DOCKER_COMPOSE_SERVICE_NAME}:
      volumes:
        - ${DOCKER_COMPOSE_SERVICE_NAME}_site-packages-data:/usr/local/lib/${DOCKER_PYTHON_VERSION,,}/site-packages
EOF

echo Volume Path...
docker-compose create ${DOCKER_COMPOSE_SERVICE_NAME}
VOLUME_PATH=$(docker inspect --format='{{.Mounts}}' $(docker-compose ps -q ${DOCKER_COMPOSE_SERVICE_NAME}) | tr " " "\n" | grep volume | grep site-packages-data)
printf "${ESC}[31m%s${ESC}[m\n" ${VOLUME_PATH}

if [ -d ${APPLICATION_ROOT}/.venv ]; then
    rm -rf ${APPLICATION_ROOT}/.venv
fi

python3 -m venv ${APPLICATION_ROOT}/.venv

cd ${APPLICATION_ROOT}/.venv/lib/${HOST_PYTHON_VERSION,,}
rm -rf site-packages
ln -s ${VOLUME_PATH} site-packages
cd - 1> /dev/null

cat <<EOF > ${APPLICATION_ROOT}/.envrc
source .venv/bin/activate
EOF
direnv allow ${APPLICATION_ROOT}
wait

echo Install PIP Package...
docker-compose build --no-cache
docker-compose run --rm ${DOCKER_COMPOSE_SERVICE_NAME} pip install -r /tmp/requirements-dev.txt
