#!/usr/bin/env bash
# Désinstalle la stack d'observabilité. Les PVC (données Prometheus, Loki, Tempo,
# Grafana) sont conservés sauf si DELETE_DATA=true.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="monitoring"

kubectl delete -f "$SCRIPT_DIR/manifests/" --ignore-not-found
for release in tempo promtail loki kube-prometheus-stack; do
  helm uninstall "$release" -n "$NAMESPACE" 2>/dev/null || echo "  $release déjà absent"
done
kubectl -n "$NAMESPACE" delete secret grafana-admin --ignore-not-found

if [ "${DELETE_DATA:-false}" = "true" ]; then
  echo "▶ Suppression des PVC..."
  kubectl -n "$NAMESPACE" delete pvc --all
fi

echo "✅ Stack désinstallée (CRDs Prometheus Operator conservées)"
