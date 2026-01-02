# Kubernetes Kiosk Chromium

Containerized Chromium kiosk designed for Kubernetes nodes with attached displays (e.g., Raspberry Pi).
The Docker image runs Xorg + Matchbox and launches Chromium in kiosk mode.

## Quick Start (Helm, OCI)
```bash
helm install kiosk oci://ghcr.io/yurymkomarov/helm/kubernetes-kiosk-chromium \
  --version <CHART_VERSION> \
  --set env.URL=http://example.com
```

## Configuration
Helm values map directly to environment variables consumed by `docker/bin/run.sh`.

Common values:
- `env.URL` — page to open (e.g., `http://example.com`)
- `env.OUTPUT` — display output name from `xrandr` (e.g., `DSI-1`)
- `env.ROTATE` — `normal|left|right|inverted`
- `env.GPU` — `1` for GPU, `0` for software rendering
- `env.ACCEL_PROFILE` — `safe` or `rpi` (enables DMABUF/zero-copy on Raspberry Pi)
- `env.CURSOR` — `true` or `false`
- `env.CHROMIUM_FLAGS`, `env.EXTRA_FLAGS` — custom Chromium flags

## Device Access Notes
The chart mounts `/dev/dri`, `/dev/input`, `/run/udev`, `/dev/vchiq`, and `/dev/vcsm-cma`. Ensure the target node provides these devices (especially on Raspberry Pi).

## License
Apache-2.0. See `LICENSE`.
