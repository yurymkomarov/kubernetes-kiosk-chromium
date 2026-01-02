#!/usr/bin/env bash
set -euo pipefail

# Defaults / public config
# Environment variables can override any of these values.
URL="${URL:-https://google.com}"
ROTATE="${ROTATE:-normal}"              # normal|left|right|inverted
CURSOR="${CURSOR:-false}"               # false|true
OUTPUT="${OUTPUT:-}"                    # e.g. DSI-1 or HDMI-1; empty => first connected
GPU="${GPU:-1}"                         # 1=use GPU, 0=software
ACCEL_PROFILE="${ACCEL_PROFILE:-safe}"  # safe|rpi

export DISPLAY=:0
: "${XDG_RUNTIME_DIR:=/tmp/xdg}"
CHROME_BIN="/usr/bin/chromium"

# User-supplied Chromium flags (merged with defaults later).
EXTRA_FLAGS_USER="${EXTRA_FLAGS:-}"
CHROMIUM_FLAGS_USER="${CHROMIUM_FLAGS:-}"

# Logging helpers
log()  { printf '[kiosk] %s\n' "$*"; }
fail() { printf '[kiosk][FATAL] %s\n' "$*" 1>&2; exit 1; }

# Runtime directories
# Create writable locations used by Xorg, D-Bus, and Chromium.
setup_runtime_dirs() {
  mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
  mkdir -p /data
  mkdir -p /run/dbus
}

# D-Bus (system + session)
# System bus is enough for our kiosk needs; session bus is not required.
setup_dbus() {
  export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"
  dbus-daemon --system --fork || true
}

# Clean shutdown (SIGTERM from kube)
# Ensure child processes exit when the container is stopped.
install_traps() {
  kill_tree() { pkill -TERM -P $$ || true; sleep 0.2; pkill -KILL -P $$ || true; }
  trap kill_tree INT TERM
}

# Xorg + wait for socket
# Start an X server and wait for its UNIX socket to appear.
start_xorg() {
  log "Starting Xorg on $DISPLAY"
  Xorg "$DISPLAY" -noreset vt1 -logfile /tmp/Xorg.log &
  for i in $(seq 1 60); do [ -S /tmp/.X11-unix/X0 ] && break; sleep 1; done
  [ -S /tmp/.X11-unix/X0 ] || fail "Xorg socket not ready after 60s"
}

# Display configuration
# Hide cursor, disable screen blanking, and apply rotation/output if set.
configure_display() {
  [ "$CURSOR" = "false" ] && (unclutter -display "$DISPLAY" -idle 0 & ) || true
  xset -display "$DISPLAY" s off -dpms || true

  if command -v xrandr >/dev/null 2>&1; then
    local OUT LINE
    if [ -n "$OUTPUT" ]; then
      OUT="$OUTPUT"
    else
      OUT="$(xrandr --display "$DISPLAY" | awk '/ connected/{print $1; exit}')"
    fi
    if [ -n "$OUT" ]; then
      xrandr --display "$DISPLAY" --output "$OUT" --rotate "$ROTATE" || true
      LINE="$(xrandr --display "$DISPLAY" | sed -n '1,/$OUT connected/{$!d}; $ p' | grep -A1 "^$OUT " || true)"
      log "xrandr selected output: $OUT"
      log "xrandr mode line: $(echo "$LINE" | tr '\n' ' ')"
    else
      log "xrandr: no connected outputs found"
    fi
  fi
}

# Window manager
# Matchbox provides a minimal window manager suitable for kiosk use.
start_wm() {
  matchbox-window-manager -use_titlebar no -use_lowlight &
}

# Chromium flags
# Build a stable default flag set, with optional GPU/accel overrides.
build_chromium_flags() {
  # Base defaults for kiosk mode and stability.
  local base_flags=(
    --no-sandbox
    --ozone-platform=x11
    --use-gl=egl
    --use-angle=egl
    --disable-vulkan
    --disable-features=Vulkan
    --ignore-gpu-blocklist
    --enable-gpu-rasterization
    --hide-scrollbars
    --overscroll-history-navigation=0
    --noerrdialogs
    --disable-sync
    --password-store=basic
    --disable-crash-reporter
    --disk-cache-dir=/tmp/chrome-cache
    --media-cache-size=104857600
    # Quiet noisy background services and logs
    --disable-background-networking
    --disable-component-update
    --disable-logging
    --log-level=3
  )
  case "$ACCEL_PROFILE" in
    rpi)
      # Allow DMABUF/zero-copy on X11 for vc4/v3d (requires working GBM/DRI3).
      : # no extra disables
      ;;
    safe|*)
      # Conservative: avoid problematic code paths on some kernels.
      base_flags+=( --disable-zero-copy --disable-gpu-memory-buffer-video-frames )
      ;;
  esac

  # Merge user-provided flags (user flags take precedence when repeated).
  local merged
  merged="${CHROMIUM_FLAGS_USER} ${EXTRA_FLAGS_USER} ${base_flags[*]}"

  # GPU toggle
  if [ "$GPU" = "0" ]; then
    merged+=" --disable-gpu --disable-accelerated-video-decode --disable-accelerated-video-encode --disable-gpu-rasterization --disable-webgl"
  fi

  echo "$merged"
}

# Chromium kiosk loop
# Restart Chromium on exit and fall back to --disable-gpu after crashes.
chromium_loop() {
  if [ "$ACCEL_PROFILE" = "safe" ]; then
    export LIBGL_DRI3_DISABLE=1   # stability: no DRI3/dmabuf
  else
    unset LIBGL_DRI3_DISABLE      # allow DRI3/dmabuf
  fi

  # Respect GPU toggle for Mesa (software rendering when GPU=0).
  if [ "$GPU" = "0" ]; then
    export LIBGL_ALWAYS_SOFTWARE=1
  else
    unset LIBGL_ALWAYS_SOFTWARE || true
  fi

  local flags crash_cnt=0
  flags="$(build_chromium_flags)"

  log "using chromium flags ($ACCEL_PROFILE): $flags"

  while true; do
    $CHROME_BIN \
      --user-data-dir=/data \
      --no-first-run --no-default-browser-check --disable-session-crashed-bubble \
      --disable-translate --disable-features=TranslateUI \
      --disable-infobars --disable-dev-shm-usage \
      --kiosk --start-fullscreen --new-window "$URL" \
      --homepage="$URL" --overscroll-history-navigation=0 \
      --autoplay-policy=no-user-gesture-required $flags || true

    local code=$?
    log "chromium exited ($code)"
    crash_cnt=$((crash_cnt+1))

    if [ "$crash_cnt" -ge 3 ] && ! echo "$flags" | grep -q -- "--disable-gpu"; then
      log "too many crashes, switching to --disable-gpu"
      flags="$flags --disable-gpu"
    fi

    sleep 2
  done
}

main() {
  setup_runtime_dirs
  setup_dbus
  install_traps
  start_xorg
  configure_display
  start_wm
  chromium_loop
}

main "$@"
