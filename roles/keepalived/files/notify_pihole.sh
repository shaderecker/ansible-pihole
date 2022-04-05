#!/bin/bash

TYPE=$1
NAME=$2
TARGETSTATE=$3

echo $(date): $TARGETSTATE state >> /home/pi/keepalived_state.log
