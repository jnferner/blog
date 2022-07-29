#!/usr/bin/env bash
set -e

yarn run clean
yarn run deploy
rsync -avz --no-whole-file blog/ hhh:/usr/share/nginx/html/hohenheim.ch/blog/
