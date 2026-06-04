#!/usr/bin/env bash
set -euo pipefail

bash /opt/openproject-patches/patch-plan-comparison.sh
exec /app/docker/prod/entrypoint.sh "$@"
