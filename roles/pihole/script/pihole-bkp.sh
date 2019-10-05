#!/bin/bash

version=4.3.2-1_armhf

docker pull pihole/pihole:$version
docker stop pihole
docker rm pihole

IP="192.168.178.46"
IPv6="fd00::d202:facb:5b48:9b96"

# Default of directory you run this from, update to where ever.
DOCKER_CONFIGS="/home/pi/pihole"

# Default ports + daemonized docker container
docker run -d --dns 127.0.0.1 --dns 1.1.1.1 \
    --name pihole \
    --log-opt max-size=10m \
    --log-opt max-file=5 \
    -e TZ="Europe/Berlin" \
    -v "${DOCKER_CONFIGS}/pihole/:/etc/pihole/" \
    -v "${DOCKER_CONFIGS}/dnsmasq.d/:/etc/dnsmasq.d/" \
    -e ServerIP="${IP}" \
    -e ServerIPv6="${IPv6}" \
    -e WEBPASSWORD="Intranet" \
    -e DNS1="1.1.1.1" \
    -e DNS2="2606:4700:4700::1111" \
    -e VIRTUAL_HOST="raspberrypi-bkp" \
    -e DNSMASQ_LISTENING="local" \
    --net=host \
    --restart=unless-stopped \
    pihole/pihole:$version

printf 'Starting up pihole container '
for i in $(seq 1 20); do
    if [ "$(docker inspect -f "{{.State.Health.Status}}" pihole)" == "healthy" ] ; then
        printf ' OK\n'
        exit 0
    else
        sleep 3
        printf '.'
    fi

    if [ $i -eq 20 ] ; then
        printf "\nTimed out waiting for Pi-hole start, check your container logs for more info\n"
        exit 1
    fi
done;
