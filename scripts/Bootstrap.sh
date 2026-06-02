#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

if ! command -v docker >/dev/null; then
  echo "Docker Engine is not installed."
  echo "Install Docker first, then rerun this script."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin is not installed."
  exit 1
fi

mkdir -p data/baselines
touch data/baselines/.gitkeep

if [[ ! -f .env ]]; then
  cp .env.example .env
  secret="$(openssl rand -hex 64)"
  sed -i "s/replace-with-a-random-secret/${secret}/" .env
  echo "Created .env with a random SECRET_KEY_BASE."
fi

docker compose up -d

echo
echo "OpenProject is starting."
echo "Open http://localhost:${PORT:-8080}"
echo "Initial login: admin / admin"
echo "Change the initial password immediately after logging in."

