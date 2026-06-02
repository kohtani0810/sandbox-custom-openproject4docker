#!/usr/bin/env bash
set -euo pipefail

action="${1:-refresh}"
project="${2:-shipment-status-agile-demo}"
label="${3:-$(date '+%Y-%m-%d %H:%M')}"
note="${4:-}"

docker compose cp scripts/Manage-Baseline.rb openproject:/tmp/Manage-Baseline.rb
docker compose exec -T openproject env RAILS_ENV=production \
  bundle exec rails runner /tmp/Manage-Baseline.rb "$action" "$project" "$label" "$note"

echo "Report: http://localhost:8080/baseline/?project=${project}"
