#!/bin/bash
set -euo pipefail

NAMESPACE="monitoring"
TIMEOUT="10m"

echo "▶ Ajout des repos Helm..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update

echo "▶ Installation kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values ~/monitoring/values/kube-prometheus-stack.yaml \
  --timeout "$TIMEOUT" \
  --atomic \
  --cleanup-on-fail \
  --debug 2>&1 | tail -20

echo "▶ Installation Loki..."
helm upgrade --install loki \
  grafana/loki \
  --namespace "$NAMESPACE" \
  --values ~/monitoring/values/loki.yaml \
  --timeout "$TIMEOUT" \
  --atomic \
  --cleanup-on-fail

echo "▶ Installation Tempo..."
helm upgrade --install tempo \
  grafana/tempo \
  --namespace "$NAMESPACE" \
  --values ~/monitoring/values/tempo.yaml \
  --timeout "$TIMEOUT" \
  --atomic \
  --cleanup-on-fail

echo ""
echo "✅ Stack installée !"
echo ""
kubectl get pods -n monitoring -o wide
echo ""
echo "Grafana : http://192.168.100.112:32000"
echo "Login   : admin / Gr@fana2026!"
