#!/usr/bin/env bash
set -euo pipefail

chart_dir="helm/kubernetes-kiosk-chromium"
chart_yaml="${chart_dir}/Chart.yaml"
values_yaml="${chart_dir}/values.yaml"

python - <<'PY'
import os
import re
from pathlib import Path

chart_version = os.environ["CHART_VERSION"]
image_tag = os.environ["IMAGE_TAG"]

chart_path = Path("helm/kubernetes-kiosk-chromium/Chart.yaml")
values_path = Path("helm/kubernetes-kiosk-chromium/values.yaml")

chart_text = chart_path.read_text()
chart_text = re.sub(r"(?m)^version:.*$", f"version: {chart_version}", chart_text)
chart_text = re.sub(r"(?m)^appVersion:.*$", f"appVersion: \"{chart_version}\"", chart_text)
chart_path.write_text(chart_text)

values_text = values_path.read_text()
values_text = re.sub(r"(?m)^(\s*tag:)\s*.*$", f"\\1 {image_tag}", values_text)
values_path.write_text(values_text)
PY

mkdir -p /tmp/helm
helm package "${chart_dir}" --destination /tmp/helm

repo="oci://ghcr.io/${GITHUB_REPOSITORY_OWNER}/helm"

helm registry login ghcr.io -u "${GITHUB_ACTOR}" -p "${GITHUB_TOKEN}"
helm push /tmp/helm/*.tgz "${repo}"
