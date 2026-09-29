#!/bin/bash
# Installe les outils nécessaires à la partie 3 :
#   - Docker  : k3d fait tourner les nodes du cluster dans des conteneurs Docker
#   - kubectl : outil en ligne de commande pour piloter le cluster
#   - k3d     : crée un cluster k3s à l'intérieur de conteneurs Docker
set -e

# --- Outils de base ---
# curl : utilisé pour télécharger Docker, kubectl, k3d, Helm et appeler l'API GitLab
# git  : pour modifier le repo pendant la démo (v1 -> v2)
if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "=== Installation de curl et git ==="
  sudo apt-get update && sudo apt-get install -y curl git
fi

# --- Docker ---
if ! command -v docker >/dev/null 2>&1; then
  echo "=== Installation de Docker ==="
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"   # permet d'utiliser docker sans sudo (relancer la session)
else
  echo "Docker déjà installé"
fi

# --- kubectl ---
if ! command -v kubectl >/dev/null 2>&1; then
  echo "=== Installation de kubectl ==="
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
else
  echo "kubectl déjà installé"
fi

# --- k3d ---
if ! command -v k3d >/dev/null 2>&1; then
  echo "=== Installation de k3d ==="
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
else
  echo "k3d déjà installé"
fi

echo "=== Versions installées ==="
docker --version
kubectl version --client
k3d version