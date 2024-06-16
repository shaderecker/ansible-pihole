#!/bin/bash
set -e

[ "$(docker inspect -f "{{.State.Health.Status}}" pihole)" = "healthy" ] && HEALTHY=0 || HEALTHY=1

PIHOLE_HOME="/home/ohthehugemanatee/pihole"

# if all of these are true, then return 0, else return 1
if  [ ${HEALTHY} ]; then
  # If we own the primary IP.
  if /usr/sbin/ip a |grep -q 10.10.10.40 ; then
     # Ensure DHCP is enabled.
     if ! [ -f ${PIHOLE_HOME}/dnsmasq.d/02-pihole-dhcp.conf ]; then
       /usr/bin/docker exec -d pihole /usr/local/bin/pihole -a enabledhcp "10.10.10.100" "10.10.10.251" "10.10.10.1" "24" "vert"
     fi
  else
    # Ensure DHCP is disabled.
    if [ -f ${PIHOLE_HOME}/dnsmasq.d/02-pihole-dhcp.conf ]; then
        /usr/bin/docker exec -d pihole /usr/local/bin/pihole -a disabledhcp
    fi
  fi
  exit $HEALTHY
else
  exit $HEALTHY
fi
