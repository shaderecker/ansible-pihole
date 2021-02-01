#!/bin/bash

[ "$(docker inspect -f "{{.State.Health.Status}}" pihole)" = "healthy" ]
