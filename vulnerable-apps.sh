#!/bin/bash

docker run -dit -p 9000:3000 registry.hub.docker.com/bkimminich/juice-shop
docker run -dit -p 9001:80 registry.hub.docker.com/vulnerables/web-dvwa
docker run -dit -p 9002:80 registry.hub.docker.com/ianwijaya/hackazon
docker run -dit -p 9003:8080 registry.hub.docker.com/webgoat/webgoat-7.1