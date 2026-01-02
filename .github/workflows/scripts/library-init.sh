#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"

case "$cmd" in
  helm-lint)
    helm lint helm/kubernetes-kiosk-chromium
    ;;
  render-helm)
    helm template helm/kubernetes-kiosk-chromium > /tmp/helm-rendered.yaml
    ;;
  kubeconform)
    curl -fsSL https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz \
      | tar -xz
    ./kubeconform -strict -summary /tmp/helm-rendered.yaml
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    exit 1
    ;;
esac
