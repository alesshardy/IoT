#!/bin/bash
# Démarre toute l'infra de la partie 3 :
# cluster k3d -> namespaces -> Argo CD -> Application qui surveille le repo GitHub
set -e

# Dossier du script, pour retrouver ../confs/application.yaml d'où qu'on le lance
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- 1. Cluster k3d ---
# 1 server + 1 agent, chacun est un conteneur Docker lancé depuis l'image rancher/k3s
# -p : le port 8888 de la VM est redirigé vers le NodePort 30888 des nodes
echo "=== Création du cluster ==="
k3d cluster create iot-cluster --servers 1 --agents 1 -p "8888:30888@loadbalancer"

# --- 2. Namespaces ---
# argocd : pour Argo CD / dev : pour l'appli déployée par Argo CD
echo "=== Création des namespaces ==="
kubectl create namespace argocd
kubectl create namespace dev

# --- 3. Argo CD ---
# Installation via les manifests officiels
# (--server-side : certains CRD d'Argo CD sont trop gros pour un apply classique)
echo "=== Installation d'Argo CD ==="
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "=== Attente qu'Argo CD soit prêt ==="
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s

# --- 4. Application Argo CD ---
# Dit à Argo CD de surveiller le repo GitHub et de déployer son contenu dans dev
echo "=== Création de l'Application ==="
kubectl apply -f "$SCRIPT_DIR/../confs/application.yaml"

# --- 5. Infos d'accès ---
echo ""
echo "=== Mot de passe admin Argo CD (user : admin) ==="
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "UI Argo CD : kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "           puis https://localhost:8080"
echo "Appli      : curl http://localhost:8888/  (attendre que le pod dans dev soit Running)"