#!/bin/sh
set -eu

sh /opt/openproject-patches/patch-plan-comparison.sh
exec /app/docker/prod/entrypoint.sh "$@"
