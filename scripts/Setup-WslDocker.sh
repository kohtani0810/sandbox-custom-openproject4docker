#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Installing Docker Engine from Docker's official apt repository"

conflicting_packages=(
  docker.io
  docker-compose
  docker-compose-v2
  docker-doc
  podman-docker
  containerd
  runc
)

installed_conflicts=()
for package in "${conflicting_packages[@]}"; do
  if dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null | grep -q '^ii'; then
    installed_conflicts+=("$package")
  fi
done

if ((${#installed_conflicts[@]})); then
  sudo apt-get remove -y "${installed_conflicts[@]}"
fi

sudo apt-get update
sudo apt-get install -y ca-certificates curl openssl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
architecture="$(dpkg --print-architecture)"
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: ${architecture}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
sudo docker run --rm hello-world

echo "==> Preparing OpenProject"
cd "$PROJECT_DIR"
sudo --preserve-env=PORT bash scripts/Bootstrap.sh
sudo docker compose ps

echo
echo "==> Setup completed"
echo "Open http://localhost:8080"
echo "Initial login: admin / admin"
echo "Sign out of Ubuntu and reopen it before running docker without sudo."
read -r -p "Press Enter to close this window..."
