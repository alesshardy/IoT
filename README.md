# Inception-of-Things (IoT)

Projet 42 — introduction à Kubernetes à travers **Vagrant**, **K3s**, **K3d** et **Argo CD**.
Le projet est découpé en 3 parties obligatoires (`p1`, `p2`, `p3`) et un bonus (`bonus`).

## Structure du dépôt

```
.
├── p1/       K3s en cluster (1 server + 1 agent) via Vagrant
├── p2/       K3s + 3 applications routées par Ingress via Vagrant
├── p3/       K3d + Argo CD (GitOps depuis un repo GitHub)
└── bonus/    GitLab local branché sur le pipeline de la p3
```

Chaque dossier contient :
- `Vagrantfile` (p1, p2) — définition des VMs.
- `scripts/` — scripts d'installation et de provisioning.
- `confs/` — manifests Kubernetes (YAML).
- `Makefile` (p1, p2) — raccourcis pour piloter les VMs et vérifier le cluster.

## Équipe

| Partie | Login | Rôle |
|---|---|---|
| p1 | `apintus` | K3s cluster (server + agent) |
| p2 | `kammi` | K3s + Ingress (3 apps) |
| p3 / bonus | `mvachera` | K3d, Argo CD, GitLab |

---

## Part 1 — K3s et Vagrant

Deux VMs Debian 13, provider `libvirt` :

| VM | Hostname | IP | Rôle |
|---|---|---|---|
| Server | `apintusS` | `192.168.56.110` | control-plane K3s |
| Worker | `apintusSW` | `192.168.56.111` | agent K3s |

Le worker rejoint automatiquement le cluster du server au démarrage (le *node-token* est
partagé entre les deux VMs via un petit serveur HTTP, `libvirt` ne montant pas `/vagrant`).

```bash
cd p1
make up            # vagrant up (les deux VMs)
make ssh-server     # vagrant ssh apintusS
make ssh-worker     # vagrant ssh apintusSW
```

Vérification (depuis `apintusS`) :

```bash
kubectl get nodes -o wide
```

Les deux nœuds doivent apparaître `Ready`.

```bash
make destroy
```

## Part 2 — K3s et trois applications

Une seule VM (`kammiS`, `192.168.56.110`), K3s avec Traefik comme Ingress Controller.
Trois applications de démo (`paulbouwer/hello-kubernetes`) déployées dans le namespace
`inception-of-things`, routées par host :

| Host | App | Replicas |
|---|---|---|
| `app1.com` | app1 | 1 |
| `app2.com` | app2 | 3 |
| autre / défaut | app3 | 1 |

```bash
cd p2
make up
make pods       # 5 pods attendus (1 + 3 + 1)
make ingress    # describe de l'Ingress
make test       # curl sur les 3 hosts
```

Test manuel :

```bash
curl -s -H "Host: app1.com" http://192.168.56.110/
curl -s -H "Host: app2.com" http://192.168.56.110/
curl -s -H "Host: autre-chose.com" http://192.168.56.110/   # → app3 par défaut
```

## Part 3 — K3d et Argo CD

Pas de Vagrant ici : K3d fait tourner K3s dans des conteneurs Docker.

```bash
cd p3/scripts
./install.sh   # Docker, kubectl, k3d
./setup.sh     # cluster k3d, namespaces argocd/dev, Argo CD, Application
```

Le cluster `iot-cluster` (1 server + 1 agent) est créé avec le port `8888` mappé sur le
NodePort `30888`. Argo CD surveille le dépôt GitHub
[`mvachera/Iot-mvachera`](https://github.com/mvachera/Iot-mvachera) (dossier `manifests/`)
et déploie automatiquement l'image `wil42/playground` dans le namespace `dev`.

```bash
kubectl get ns                        # argocd, dev
kubectl get pods -n dev
curl http://localhost:8888/            # {"status":"ok","message":"v1"}
```

Changer de version : éditer `manifests/deployment.yaml` sur le dépôt GitHub
(`wil42/playground:v1` → `:v2`), commit + push. Argo CD resynchronise automatiquement
(`selfHeal` + `prune` actifs).

Accès UI Argo CD :

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080 — user: admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

```bash
./delete.sh    # supprime le cluster k3d
```

## Bonus — GitLab local

Ajoute une instance GitLab locale (namespace `gitlab`, installée via Helm avec
PostgreSQL, Redis et MinIO en dépendances) et rebranche Argo CD dessus au lieu de GitHub.

```bash
cd bonus/scripts
./setup-gitlab.sh
```

L'installation prend 10 à 15 minutes. À la fin :

```bash
kubectl port-forward svc/gitlab-webservice-default -n gitlab 8181:8181
# http://localhost:8181 — user: root
kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 -d
```

Étapes manuelles ensuite (détaillées dans la sortie du script) : créer le groupe/projet
GitLab, y pousser les manifests, puis appliquer `bonus/confs/application.yaml` pour que
Argo CD suive désormais ce dépôt local au lieu de GitHub.

## Prérequis

- Vagrant + un provider (`libvirt` utilisé ici, `vagrant-libvirt` requis)
- Docker (pour la p3 et le bonus)
- `kubectl`, `k3d`, `helm` (installés automatiquement par les scripts fournis)

## Sujet

Voir [`inceptionofthings.pdf`](inceptionofthings.pdf) pour l'énoncé complet.
