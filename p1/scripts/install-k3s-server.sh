#!/bin/bash
# Arret immediat si une commande echoue
set -e

# --- 1. DNS fiable (le DNS du reseau virtuel etait instable) ---
echo "[*] Configuration DNS fiable..."
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf

echo "==========================================="
echo "Installation K3s en mode SERVER (controller)"
echo "==========================================="

# --- 2. Installer K3s en mode server (control-plane) sur l'IP fixe ---
# Interface qui porte l'IP du sujet (ens6 sur cette box), trouvee par son IP
IFACE=$(ip -o -4 addr show | awk '/192\.168\.56\.110\// {print $2}')
[ -n "$IFACE" ] || { echo "ERREUR: interface 192.168.56.110 introuvable"; exit 1; }
echo "[*] Interface du reseau prive : ${IFACE}"

# Traefik desactive: pas besoin d'Ingress en P1
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --bind-address=192.168.56.110 --advertise-address=192.168.56.110 --node-ip=192.168.56.110 --flannel-iface=${IFACE} --disable=traefik" sh -

echo "[*] Attente du demarrage de K3s..."
sleep 10

# --- 3. Rendre kubectl utilisable par l'utilisateur vagrant ---
# Le fichier d'origine appartient a root: on en fait une copie lisible
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
sed -i 's/127.0.0.1/192.168.56.110/g' /home/vagrant/.kube/config

# KUBECONFIG permanent, pour toutes les sessions
if ! grep -q "KUBECONFIG" /etc/environment; then
    echo "KUBECONFIG=/home/vagrant/.kube/config" | sudo tee -a /etc/environment
fi
if ! grep -q "KUBECONFIG" /home/vagrant/.bashrc; then
    echo 'export KUBECONFIG=/home/vagrant/.kube/config' >> /home/vagrant/.bashrc
fi

# --- 4. Partager le token avec le Worker via un serveur HTTP (port 8000) ---
# libvirt ne monte pas /vagrant: on passe donc par le reseau
mkdir -p /tmp/token_share
cp /var/lib/rancher/k3s/server/node-token /tmp/token_share/token.txt
chmod 644 /tmp/token_share/token.txt

# systemd-run: lance le serveur HTTP comme service systemd independant,
# qui survit a la fermeture de la session SSH du provisioning
systemctl stop k3s-token-share 2>/dev/null || true
systemd-run --unit=k3s-token-share \
    python3 -m http.server 8000 --bind 192.168.56.110 --directory /tmp/token_share

echo "==========================================="
echo "K3s SERVER installe avec succes!"
echo "==========================================="
