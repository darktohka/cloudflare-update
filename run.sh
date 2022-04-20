#!/bin/bash

parent_path=$( cd "$(dirname "${BASH_SOURCE}")" ; pwd -P )
cd "$parent_path"

TAG=cloudflare
NAME=cloudflare

if [ ! "$(docker ps -q -f name=$NAME)" ]; then
  if [ "$(docker ps -aq -f status=exited -f name=$NAME)" ]; then
    docker rm "$NAME" --force
  fi

  chown -R 427:427 config
  docker rm --force "$NAME"
  docker build --pull -t "$TAG" .
  docker run --name "$NAME" -v "$(pwd)/config:/srv/config" "$TAG"
fi

