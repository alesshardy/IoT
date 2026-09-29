#!/bin/bash
# Arret immediat si une commande echoue
set -e

# --- 1. DNS fiable (le DNS du reseau virtuel etait instable) ---
echo "[*] Configuration DNS fiable..."
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf

echo "==========================================="
echo "Installation K3s en mode WORKER (agent)"
echo "==========================================="

SERVER_IP="192.168.56.110"

# Interface qui porte l'IP du sujet (ens6 sur cette box), trouvee par son IP
IFACE=$(ip -o -4 addr show | awk '/192\.168\.56\.111\// {print $2}')
[ -n "$IFACE" ] || { echo "ERREUR: interface 192.168.56.111 introuvable"; exit 1; }
echo "[*] Interface du reseau prive : ${IFACE}"

# --- 2. Recuperer le token du Server via HTTP (port 8000) ---
# Les VMs demarrent en parallele: on reessaie jusqu'a ce que le Server soit pret
echo "[*] Attente de la disponibilite du serveur de token (port 8000)..."
for i in $(seq 1 30); do
    if curl -sf "http://${SERVER_IP}:8000/token.txt" -o /tmp/k3s_token.txt 2>/dev/null; then
        echo "  Token recupere avec succes!"
        break
    fi
    echo "  Tentative $i/30..."
    sleep 5
done

# Echec si le fichier token est absent ou vide
if [ ! -s /tmp/k3s_token.txt ]; then
    echo "ERREUR: impossible de recuperer le token"
    exit 1
fi

K3S_TOKEN=$(cat /tmp/k3s_token.txt)

# --- 3. Attendre que l'API K3s du Server reponde (port 6443) ---
echo "[*] Attente de la connexion au serveur K3s (${SERVER_IP}:6443)..."
for i in $(seq 1 30); do
    if nc -z ${SERVER_IP} 6443 2>/dev/null; then
        echo "  Serveur K3s accessible"
        break
    fi
    echo "  Tentative $i/30..."
    sleep 5
done

# --- 4. Installer K3s en mode agent et rejoindre le cluster ---
# K3S_URL = adresse du Server / K3S_TOKEN = preuve d'autorisation
curl -sfL https://get.k3s.io | K3S_URL="https://${SERVER_IP}:6443" K3S_TOKEN="${K3S_TOKEN}" INSTALL_K3S_EXEC="agent --node-ip=192.168.56.111 --flannel-iface=${IFACE}" sh -

echo "==========================================="
echo "K3s WORKER installe avec succes!"
echo "==========================================="
