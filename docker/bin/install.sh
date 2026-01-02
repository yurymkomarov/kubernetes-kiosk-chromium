#!/usr/bin/env bash
set -euo pipefail

: "${DEBIAN_CODENAME:=bookworm}"
: "${USE_RPI_CHROMIUM:=auto}"
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

resolve_rpi_chromium() {
  if [ "${USE_RPI_CHROMIUM}" != "auto" ]; then
    return
  fi
  case "$(detect_arch)" in
    arm64|aarch64)
      USE_RPI_CHROMIUM=1
      ;;
    *)
      USE_RPI_CHROMIUM=0
      ;;
  esac
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
    libgl1-mesa-dri libgles2-mesa \
    dbus fontconfig \
    fonts-dejavu ca-certificates curl gnupg \
    libegl1 \
    libglx-mesa0 \
    mesa-va-drivers mesa-vdpau-drivers \
    mesa-utils-extra
}

# Install Chromium from Raspberry Pi repo (arm64). Use when Debian's
# chromium package is not suitable for the target device.
install_chromium_rpi() {
  install -m 0755 -d /etc/apt/keyrings
  local keyring="/etc/apt/keyrings/raspberrypi-archive-keyring.gpg"
  local key_tmp
  key_tmp="$(mktemp)"
  curl -fsSL https://archive.raspberrypi.com/debian/raspberrypi.gpg.key -o "$key_tmp"
  if [ -n "$RPI_GPG_FINGERPRINT" ]; then
    local actual
    actual="$(gpg --show-keys --with-colons "$key_tmp" | awk -F: '$1=="fpr"{print $10; exit}')"
    if [ "$actual" != "$RPI_GPG_FINGERPRINT" ]; then
      echo "Raspberry Pi repo key fingerprint mismatch: $actual" >&2
      exit 1
    fi
  else
    echo "Warning: RPI_GPG_FINGERPRINT is empty; skipping key verification." >&2
  fi
  gpg --dearmor -o "$keyring" "$key_tmp"
  rm -f "$key_tmp"
  echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/raspberrypi-archive-keyring.gpg] http://archive.raspberrypi.com/debian ${DEBIAN_CODENAME} main" \
    > /etc/apt/sources.list.d/raspi.list
  printf 'Package: *\nPin: origin archive.raspberrypi.com\nPin-Priority: 600\n' \
    > /etc/apt/preferences.d/raspi.pref

  apt-get update
  apt-get upgrade -y
  apt-get install -y --no-install-recommends chromium-browser
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
  if [ -e /usr/lib/chromium-browser/chrome-sandbox ]; then
    chown root:root /usr/lib/chromium-browser/chrome-sandbox
    chmod 4755 /usr/lib/chromium-browser/chrome-sandbox
  fi
}

main() {
  resolve_rpi_chromium
  install_base_packages
  if [ "$USE_RPI_CHROMIUM" = "1" ]; then
    install_chromium_rpi
  else
    install_chromium_default
  fi
  fix_chrome_sandbox
  rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*
}

main "$@"
