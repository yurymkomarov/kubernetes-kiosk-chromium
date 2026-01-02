#!/usr/bin/env bash
set -euo pipefail

: "${DEBIAN_CODENAME:=}"
: "${TARGETARCH:=}"
: "${RPI_GPG_FINGERPRINT:=CF8A1AF502A2AA2D763BAE7E82B129927FA3303E}"

detect_arch() {
  if [ -n "${TARGETARCH}" ]; then
    printf '%s' "${TARGETARCH}"
    return
  fi
  if command -v dpkg >/dev/null 2>&1; then
    dpkg --print-architecture
    return
  fi
  uname -m
}

# Install core X11 stack, minimal WM, and GPU/DRM/Mesa runtime libs.
# Keep this list conservative to reduce image size.
install_base_packages() {
  apt-get update
  apt-get install -y --no-install-recommends \
    xserver-xorg xinit xfonts-base x11-xserver-utils \
    matchbox-window-manager \
    unclutter \
    dumb-init \
    chromium-sandbox \
    libdrm2 libgbm1 libinput10 udev \
    libgl1-mesa-dri libgles2 \
    dbus fontconfig \
    fonts-dejavu ca-certificates curl gnupg \
    libegl1 \
    libglx-mesa0 \
    mesa-va-drivers mesa-vdpau-drivers \
    mesa-utils-extra
}

# Install Chromium from Debian repos (default path for most targets).
install_chromium_default() {
  apt-get update
  apt-get upgrade -y
  apt-get install -y --no-install-recommends chromium
}

# Ensure chrome-sandbox has correct setuid root permissions so Chromium
# can launch in a containerized environment.
fix_chrome_sandbox() {
  if [ -e /usr/lib/chromium/chrome-sandbox ]; then
    chown root:root /usr/lib/chromium/chrome-sandbox
    chmod 4755 /usr/lib/chromium/chrome-sandbox
  fi
}

main() {
  install_base_packages
  install_chromium_default
  fix_chrome_sandbox
  rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*
}

main "$@"
