#!/usr/bin/env bash
# =============================================================================
# Installation de la stack d'observabilité NexShop (namespace monitoring) :
#   kube-prometheus-stack (Prometheus, Grafana, Alertmanager), Loki, Promtail, Tempo
#
# Usage :
#   export MONITORING_NODE=k8s2-worker1
#   export GRAFANA_ADMIN_PASSWORD='...'
#   bash install.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES="$SCRIPT_DIR/values"
NAMESPACE="monitoring"
TIMEOUT="10m"

: "${MONITORING_NODE:?Définir MONITORING_NODE (ex. k8s2-worker1)}"
: "${GRAFANA_ADMIN_PASSWORD:?Définir GRAFANA_ADMIN_PASSWORD}"

# Versions de charts figées (générées par pin-versions.sh)
[ -f "$SCRIPT_DIR/versions.env" ] \
  || { echo "✖ versions.env absent : lancer d'abord « bash pin-versions.sh »"; exit 1; }
# shellcheck source=/dev/null
source "$SCRIPT_DIR/versions.env"
for v in KPS_VERSION LOKI_VERSION PROMTAIL_VERSION TEMPO_VERSION; do
  [ -n "${!v:-}" ] || { echo "✖ $v vide dans versions.env"; exit 1; }
done

echo "▶ Vérification des prérequis..."
command -v helm >/dev/null    || { echo "✖ helm introuvable"; exit 1; }
command -v kubectl >/dev/null || { echo "✖ kubectl introuvable"; exit 1; }
kubectl get storageclass local-path >/dev/null 2>&1 \
  || { echo "✖ StorageClass local-path absente (installer local-path-provisioner)"; exit 1; }

echo "▶ Préparation du nœud de monitoring : $MONITORING_NODE"
kubectl label node "$MONITORING_NODE" monitoring=true --overwrite
kubectl taint node "$MONITORING_NODE" dedicated=monitoring:NoSchedule --overwrite

echo "▶ Namespace et secret Grafana..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "▶ Dépôts Helm..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo update

install_chart() {
  local release="$1" chart="$2" version="$3" values="$4"
  echo "▶ $release ($chart $version)..."
  helm upgrade --install "$release" "$chart" \
    --namespace "$NAMESPACE" \
    --version "$version" \
    --values "$values" \
    --timeout "$TIMEOUT" \
    --atomic \
    --cleanup-on-fail
}

install_chart kube-prometheus-stack prometheus-community/kube-prometheus-stack "$KPS_VERSION"      "$VALUES/kube-prometheus-stack.yaml"
install_chart loki                  grafana/loki                               "$LOKI_VERSION"     "$VALUES/loki.yaml"
install_chart promtail              grafana/promtail                           "$PROMTAIL_VERSION" "$VALUES/promtail.yaml"
install_chart tempo                 grafana/tempo                              "$TEMPO_VERSION"    "$VALUES/tempo.yaml"

echo "▶ ServiceMonitor NexShop et NodePorts Loki / Tempo..."
kubectl apply -f "$SCRIPT_DIR/manifests/"

echo ""
echo "✅ Stack installée"
kubectl get pods -n "$NAMESPACE" -o wide
echo ""
echo "Grafana    : http://<IP de $MONITORING_NODE>:32000 (admin / \$GRAFANA_ADMIN_PASSWORD)"
echo "Prometheus : http://<IP d'un nœud>:30090"
echo "Loki       : http://<IP d'un nœud>:30003"
echo "Tempo      : http://<IP d'un nœud>:30622"
