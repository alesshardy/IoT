#!/bin/bash
set -e   # arrête le script dès qu'une commande échoue (évite de continuer sur une install cassée)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"   # chemin absolu du dossier du script

# --- Helm ---
# Helm = gestionnaire de paquets de Kubernetes (comme apt pour Linux).
# Il installe une appli complète (un "chart") avec nos options (--set ...),
# sans avoir à écrire nous-mêmes des dizaines de fichiers YAML.
# Ici il sert à installer GitLab, PostgreSQL, Redis et MinIO dans le cluster.
if ! command -v helm >/dev/null 2>&1; then
  echo "=== Installation de Helm ==="
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "Helm déjà installé"
fi

# Ce script suppose que le cluster k3d existe deja et qu'Argo CD est deja installe.
# Il installe uniquement Gitlab (+ ses dependances externes) dans le namespace "gitlab".

# Attend qu'un pod existe ET soit Ready (evite l'erreur "pods not found"
# quand kubectl wait est lance avant que le pod ne soit meme cree)
wait_for_pod() {
  local target="$1"      # nom de pod, ou selector -l
  local namespace="$2"
  local is_name="$3"     # "name" ou "label"

  echo "Attente de la creation du pod ($target)..."
  for i in $(seq 1 30); do
    if [ "$is_name" = "name" ]; then
      kubectl get pod "$target" -n "$namespace" >/dev/null 2>&1 && break
    else
      [ "$(kubectl get pod -l "$target" -n "$namespace" --no-headers 2>/dev/null | wc -l)" -gt 0 ] && break
    fi
    sleep 5
  done

  echo "Attente que le pod soit Ready..."
  if [ "$is_name" = "name" ]; then
    kubectl wait --for=condition=Ready "pod/$target" -n "$namespace" --timeout=180s
  else
    kubectl wait --for=condition=Ready pod -l "$target" -n "$namespace" --timeout=180s
  fi
}

echo "=== Namespace gitlab ==="
kubectl create namespace gitlab 2>/dev/null || echo "gitlab namespace deja la"

echo "=== Helm repos ==="
helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || true
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update

# --- PostgreSQL -------------------------------------------------------------
# max_locks_per_transaction est augmente des le depart : le schema Gitlab est
# enorme (des centaines de tables), sinon les migrations plantent avec
# "ERROR: out of shared memory"
echo "=== PostgreSQL ==="
helm install gitlab-postgresql bitnami/postgresql \
  --namespace gitlab \
  --set auth.username=gitlab \
  --set auth.password=gitlabpassword \
  --set auth.database=gitlabhq_production \
  --set primary.resources.requests.memory=512Mi \
  --set primary.resources.requests.cpu=250m \
  --set primary.resources.limits.memory=1Gi \
  --set-string "primary.extendedConfiguration=max_locks_per_transaction = 256"

wait_for_pod "gitlab-postgresql-0" "gitlab" "name"
sleep 30

# --- Redis -------------------------------------------------------------------
# Gitlab envoie TOUJOURS un AUTH, meme si Redis n'a pas de mot de passe
# => auth.enabled=true obligatoire, et le secret gitlab-redis-secret doit
# utiliser la cle EXACTE "secret" (pas "redis-password")
echo "=== Redis ==="
REDIS_PASS="gitlabredispass"

helm install gitlab-redis bitnami/redis \
  --namespace gitlab \
  --set auth.enabled=true \
  --set auth.password="$REDIS_PASS" \
  --set architecture=standalone

wait_for_pod "gitlab-redis-master-0" "gitlab" "name"

kubectl delete secret gitlab-redis-secret -n gitlab 2>/dev/null || true
kubectl create secret generic gitlab-redis-secret \
  --namespace gitlab \
  --from-literal=secret="$REDIS_PASS"

# --- MinIO (stockage objet S3) -----------------------------------------------
# Chart Bitnami : les images officielles MinIO (quay.io / Docker Hub) ne sont
# plus accessibles publiquement. defaultBuckets crée les buckets au démarrage
# (Gitlab ne les crée jamais lui-même), donc plus besoin du pod "mc".
# images bitnami/minio plus gratuites depuis aout 2025 -> archive bitnamilegacy
# console.enabled=false : l'interface web de MinIO ne sert pas ici
echo "=== MinIO ==="
helm install gitlab-minio bitnami/minio \
  --namespace gitlab \
  --set global.security.allowInsecureImages=true \
  --set image.repository=bitnamilegacy/minio \
  --set console.enabled=false \
  --set mode=standalone \
  --set auth.rootUser=gitlab \
  --set auth.rootPassword=gitlabpassword \
  --set persistence.enabled=false \
  --set defaultBuckets="git-lfs\,artifacts\,uploads\,packages\,external-diffs\,terraform-state\,dependency-proxy" \
  --set resources.requests.memory=256Mi \
  --set resources.requests.cpu=100m

wait_for_pod "app.kubernetes.io/name=minio" "gitlab" "label"

kubectl delete secret gitlab-object-storage -n gitlab 2>/dev/null || true
kubectl create secret generic gitlab-object-storage \
  --namespace gitlab \
  --from-literal=connection='{"provider":"AWS","region":"us-east-1","aws_access_key_id":"gitlab","aws_secret_access_key":"gitlabpassword","endpoint":"http://gitlab-minio.gitlab.svc.cluster.local:9000","path_style":true}'

# --- Gitlab lui-meme ----------------------------------------------------------
# registry.enabled=false : pas besoin d'un registre Docker interne pour ce projet
# webservice/sidekiq limites a 1 replica : la VM a peu de RAM, plusieurs
# replicas = pods evinces (Evicted) faute de memoire disponible
echo "=== Gitlab ==="
helm install gitlab gitlab/gitlab \
  --namespace gitlab \
  --timeout 900s \
  --set global.edition=ce \
  --set global.hosts.domain=127.0.0.1.nip.io \
  --set certmanager-issuer.email=me@example.com \
  --set global.hosts.https=false \
  --set nginx-ingress.enabled=false \
  --set gitlab-runner.install=false \
  --set global.gitlab.chart.tls.enabled=false \
  --set global.psql.host=gitlab-postgresql.gitlab.svc.cluster.local \
  --set global.psql.password.secret=gitlab-postgresql \
  --set global.psql.password.key=password \
  --set global.psql.username=gitlab \
  --set global.psql.database=gitlabhq_production \
  --set global.redis.host=gitlab-redis-master.gitlab.svc.cluster.local \
  --set global.appConfig.object_store.enabled=true \
  --set global.appConfig.object_store.connection.secret=gitlab-object-storage \
  --set global.appConfig.object_store.connection.key=connection \
  --set registry.enabled=false \
  --set gitlab.webservice.minReplicas=1 \
  --set gitlab.webservice.maxReplicas=1 \
  --set gitlab.sidekiq.minReplicas=1 \
  --set gitlab.sidekiq.maxReplicas=1

echo ""
echo "=== Installation lancee. Compte 10-15 min. ==="
echo "Surveille avec : kubectl get pods -n gitlab -w"
echo "Ne relance rien pendant que les migrations tournent, laisse-les finir."
echo ""
echo "=== Connexion Gitlab (quand tous les pods sont Running/Completed) ==="
echo "User : root"
echo "Mot de passe :"
echo "  kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 -d; echo"
echo ""
echo "Acces a l'UI (dans un terminal a part) :"
echo "  kubectl port-forward svc/gitlab-webservice-default -n gitlab 8181:8181"
echo "  puis http://localhost:8181"
echo ""
echo "=== Etapes suivantes ==="
echo "1. Dans l'UI : creer le groupe 'mvachera' (Public) puis le projet 'iot-mvachera' (Public)"
echo "2. Pousser les manifests (v1) dans un dossier manifests/ :"
echo "     git clone http://localhost:8181/mvachera/iot-mvachera.git"
echo "     mkdir iot-mvachera/manifests && cp deployment.yaml service.yaml iot-mvachera/manifests/"
echo "     cd iot-mvachera && git add . && git commit -m 'v1' && git push   # user root"
echo "3. Brancher Argo CD sur Gitlab :"
echo "     kubectl apply -f $SCRIPT_DIR/../confs/application.yaml"
echo "4. Verifier :"
echo "     kubectl get application -n argocd    # Synced / Healthy"
echo "     curl http://localhost:8888/          # v1"
echo ""
echo "UI Argo CD (autre terminal) : kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  -> https://localhost:8080 (user admin)"