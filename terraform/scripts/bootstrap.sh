#!/usr/bin/env bash
set -euo pipefail

# Values written by cloud-init from Terraform variables.
# shellcheck source=/dev/null
source /opt/bootstrap/bootstrap.env

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

log() { echo "[bootstrap] $(date -u +%H:%M:%S) $*"; }

# retry <tries> <sleep_seconds> <command...>
retry() {
  local tries=$1 sleep_s=$2
  shift 2
  local i=1
  until "$@"; do
    if [ "$i" -ge "$tries" ]; then
      log "FAILED after ${tries} tries: $*"
      return 1
    fi
    log "retry ${i}/${tries}: $*"
    sleep "$sleep_s"
    i=$((i + 1))
  done
}

log "Installing k3s (config at /etc/rancher/k3s/config.yaml: Traefik off, kubeconfig 0600)..."
retry 5 10 bash -c 'curl -sfL https://get.k3s.io | sh -s -'

log "Waiting for the node to be Ready..."
retry 30 10 kubectl wait --for=condition=Ready node --all --timeout=20s

# ArgoCD is installed from the upstream manifests (the APP is the Helm chart my-monitor/).
log "Installing ArgoCD ${ARGOCD_VERSION} from upstream manifests..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
retry 5 15 kubectl apply -n argocd --server-side \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

log "Waiting for the ArgoCD CRD and the FULL ArgoCD stack to be ready..."
retry 30 10 kubectl wait --for=condition=established crd/applications.argoproj.io --timeout=20s
# The application-controller (a StatefulSet) is what actually syncs Applications.
retry 60 10 kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=30s
retry 60 10 kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=30s
retry 60 10 kubectl -n argocd rollout status deploy/argocd-server --timeout=30s
retry 60 10 kubectl -n argocd rollout status deploy/argocd-redis --timeout=30s
# Belt-and-suspenders: every ArgoCD pod Ready before we proceed.
retry 30 10 kubectl -n argocd wait --for=condition=Ready pod --all --timeout=30s

log "Exposing the ArgoCD UI on NodePort 30443 (HTTPS)..."
kubectl -n argocd patch svc argocd-server --type merge -p \
  '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"targetPort":8080,"nodePort":30443}]}}'

if [ -n "${ARGOCD_ADMIN_PASSWORD}" ]; then
  log "Setting the ArgoCD admin password..."
  HASH="$(kubectl -n argocd exec deploy/argocd-server -- \
    argocd account bcrypt --password "${ARGOCD_ADMIN_PASSWORD}")"
  kubectl -n argocd patch secret argocd-secret -p \
    "{\"stringData\":{\"admin.password\":\"${HASH}\",\"admin.passwordMtime\":\"$(date +%FT%T%Z)\"}}"
fi

log "Creating the app namespace ${APP_NAMESPACE}..."
kubectl create namespace "${APP_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

log "Applying the ArgoCD Application..."
retry 10 10 kubectl apply -n argocd -f /opt/bootstrap/application.yaml

log "Waiting for ArgoCD to sync and the app to become Healthy..."
# Wait for the Application to report Synced, then Healthy (needs the image pulled
# and the readiness probe passing). jsonpath waits are supported on modern kubectl.
retry 30 15 kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced \
  application/uptime-kuma --timeout=20s
retry 30 15 kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/uptime-kuma --timeout=20s
# And confirm the actual workload rolled out in the app namespace.
retry 30 10 kubectl -n "${APP_NAMESPACE}" rollout status deploy/uptime-kuma --timeout=30s

log "Bootstrap complete. uptime-kuma is deployed, Synced and Healthy."
