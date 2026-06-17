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

log "Installing the Helm CLI..."
retry 5 10 bash -c 'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'

# ArgoCD is installed via its OFFICIAL HELM CHART; the app is ALSO a Helm chart (my-monitor/).
# The NodePort 30443 (HTTPS) UI is configured through Helm values instead of a kubectl patch.
log "Installing ArgoCD via Helm chart ${ARGOCD_CHART_VERSION} (argocd app ${ARGOCD_VERSION})..."
retry 3 10 helm repo add argo https://argoproj.github.io/argo-helm
retry 3 10 helm repo update
retry 2 20 helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version "${ARGOCD_CHART_VERSION}" \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttps=30443 \
  --wait --timeout 8m

log "Verifying the ArgoCD CRD and the full stack are ready..."
retry 30 10 kubectl wait --for=condition=established crd/applications.argoproj.io --timeout=20s
# The application-controller (a StatefulSet) is what actually syncs Applications.
retry 60 10 kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=30s
retry 30 10 kubectl -n argocd wait --for=condition=Ready pod --all --timeout=30s

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
