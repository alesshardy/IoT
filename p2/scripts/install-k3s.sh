#!/bin/bash
# Arret immediat si une commande echoue
set -e

# 1. DNS fiable (le DNS du reseau virtuel etait instable) 
echo "[*] Configuration DNS fiable..."
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf

echo "==========================================="
echo "Installation K3s en mode SERVER (avec Traefik)"
echo "==========================================="

# 2. Installer K3s en mode server 
# Traefik reste ACTIVE ici: c'est l'Ingress Controller dont on a besoin
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --bind-address=192.168.56.110 --advertise-address=192.168.56.110 --node-ip=192.168.56.110" sh -

echo "[*] Attente du demarrage de K3s..."
sleep 15

# 3. Rendre kubectl utilisable par l'utilisateur vagrant 
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
sed -i 's/127.0.0.1/192.168.56.110/g' /home/vagrant/.kube/config

# KUBECONFIG permanent: /etc/environment vaut pour TOUTES les sessions
# (.bashrc seul ne suffit pas, cette box ouvre sh et non bash)
if ! grep -q "KUBECONFIG" /etc/environment; then
    echo "KUBECONFIG=/home/vagrant/.kube/config" | sudo tee -a /etc/environment
fi
if ! grep -q "KUBECONFIG" /home/vagrant/.bashrc; then
    echo 'export KUBECONFIG=/home/vagrant/.kube/config' >> /home/vagrant/.bashrc
fi

# KUBECONFIG pour la suite de CE script
export KUBECONFIG=/home/vagrant/.kube/config

echo "==========================================="
echo "Deploiement automatique des applications"
echo "==========================================="

# 4. Attendre que l'API Kubernetes reponde 
echo "[*] Attente que l'API Kubernetes soit prete..."
for i in $(seq 1 30); do
    if kubectl get nodes > /dev/null 2>&1; then
        echo "  API disponible"
        break
    fi
    echo "  Tentative $i/30..."
    sleep 5
done

# 5. Deployer les manifests (copies dans /vagrant par rsync) 
# Le namespace d'abord, car les autres ressources en dependent
kubectl apply -f /vagrant/confs/namespace.yaml
kubectl apply -f /vagrant/confs/app1.yaml
kubectl apply -f /vagrant/confs/app2.yaml
kubectl apply -f /vagrant/confs/app3.yaml
kubectl apply -f /vagrant/confs/ingress.yaml

# 6. Attendre que les applications soient pretes
echo "[*] Attente que les applications soient pretes..."
kubectl wait --for=condition=available deployment --all -n inception-of-things --timeout=300s || true

# 7. Attendre que Traefik route reellement le trafic
# Traefik est installe a part par K3s, avec un decalage: sans cette
# boucle, vagrant up rend la main avant que le port 80 est publie
echo "[*] Attente que Traefik reponde..."
for i in $(seq 1 30); do
    if curl -s -H "Host: app1.com" http://192.168.56.110/ | grep -q "Hello from"; then
        echo "  Ingress operationnel"
        break
    fi
    echo "  Tentative $i/30..."
    sleep 5
done

echo "==========================================="
echo "K3s + applications installes avec succes!"
echo "==========================================="
