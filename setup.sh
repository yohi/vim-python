#!/bin/bash
echo Application Root? [default: django/app]:
read INPUT_APPLICATION_ROOT

APPLICATION_ROOT=${INPUT_APPLICATION_ROOT:-"django/app"}

echo Docker Compose Service Name? [default: app]:
read INPUT_DOCKER_COMPOSE_SERVICE_NAME
DOCKER_COMPOSE_SERVICE_NAME=${INPUT_DOCKER_COMPOSE_SERVICE_NAME:-"app"}

echo Host Python Version Check...
HOST_PYTHON_VERSION=$(python3 --version | sed -E "s/\s|\.[0-9]+$//g")
echo ${HOST_PYTHON_VERSION}

if [ -d docker-compose.override.yml ]; then
    mv docker-compose.override.yml docker-compose.override.yml.bk
fi

cat <<EOF > docker-compose.override.yml
volumes:
    ${DOCKER_COMPOSE_SERVICE_NAME}_site-packages-data:
EOF

echo Docker Python Version Check...
docker-compose build ${DOCKER_COMPOSE_SERVICE_NAME}
DOCKER_PYTHON_VERSION=$(docker-compose run ${DOCKER_COMPOSE_SERVICE_NAME} python3 --version | sed -E "s/\s|\.[0-9]+\s*$//g")
echo ${DOCKER_PYTHON_VERSION}

cat <<EOF >> docker-compose.override.yml
services:
    ${DOCKER_COMPOSE_SERVICE_NAME}:
      volumes:
        - ${DOCKER_COMPOSE_SERVICE_NAME}_site-packages-data:/usr/local/lib/${DOCKER_PYTHON_VERSION,,}/site-packages
EOF

VOLUME_PATH=$(docker inspect --format='{{.Mounts}}' $(docker-compose ps -q ${DOCKER_COMPOSE_SERVICE_NAME}) | tr " " "\n" | grep volume | grep site-packages-data)

if [ -d ${APPLICATION_ROOT}/.venv ]; then
    rm -rf ${APPLICATION_ROOT}/.venv
fi

python3 -m venv ${APPLICATION_ROOT}/.venv

cd ${APPLICATION_ROOT}/.venv/lib/${HOST_PYTHON_VERSION,,}
rm -rf site-packages
ln -s ${VOLUME_PATH} site-packages
cd -

cat <<EOF > ${APPLICATION_ROOT}/.envrc
source .venv/bin/activate
EOF
direnv allow ${APPLICATION_ROOT}
wait


echo Install PIP Package...
docker-compose run --rm ${DOCKER_COMPOSE_SERVICE_NAME} pip install -r /tmp/requirements-dev.txt
