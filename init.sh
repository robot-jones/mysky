#!/bin/bash
set -e

echo "┌──────────────────────┐"
echo "│  MySky Raspberry Pi  │"
echo "└──────────────────────┘"

# -------------------------------------
#   FUNCTIONS
# -------------------------------------

getTimestamp() {
  date -Iseconds
}

getStageText() {
  echo "Stage $CURRENT_STAGE"
}

completeStage() {
  local timestamp=$(getTimestamp)
  local stagetext=$(getStageText)
  local result="${1:-"success"}"
  echo "$timestamp | $stagetext | $result" >> "$STAGE_FILE"
  CURRENT_STAGE=$((CURRENT_STAGE + 1))
}

log() {
  local timestamp=$(getTimestamp)
  local stagetext=$(getStageText)
  echo "$timestamp | $stagetext | $1"
  echo "$timestamp | $stagetext | $1" >> "$LOG_FILE"
}

updateSystemPackages() {
  log "Updating system packages"
  if ! apt update; then
    completeStage "apt update failed"
    exit 1
  fi
  if ! apt upgrade -y; then
    completeStage "apt upgrade failed"
    exit 1
  fi
}

updateBootloader() {
  log "Updating Raspberry Pi bootloader"
  if ! rpi-eeprom-update -a; then
    completeStage "bootloader update failed"
    exit 1
  fi
}

enableUsbBoot() {
  log "Enabling USB boot"
  if ! raspi-config nonint do_boot_order 4; then
    completeStage "USB boot configuration failed"
    exit 1
  fi
}

bootToDesktop() {
  log "Set boot to desktop"
  if ! raspi-config nonint do_boot_behaviour B4; then
    completeStage "boot to desktop configuration failed"
    exit 1
  fi
}

useX11() {
  log "Use X11 instead of Wayland"
  if ! raspi-config nonint do_wayland W1; then
    completeStage "X11 configuration failed"
    exit 1
  fi
}

setResolution() {
  log "Set HDMI resolution to 1080p"
  if ! grep -q "video=HDMI-A-1:1920x1080@60" /boot/firmware/cmdline.txt 2>/dev/null; then
    if ! echo -n " video=HDMI-A-1:1920x1080@60" >> /boot/firmware/cmdline.txt; then
      completeStage "failed to write resolution to cmdline.txt"
      exit 1
    fi
  else
    log "Resolution already set, skipping"
  fi
}

installArgon1() {
  log "Installing Argon1 themes and tools"
  local script_path="/tmp/argon1.sh"
  if ! curl -fsSL -o "$script_path" https://download.argon40.com/argon1.sh; then
    completeStage "failed to download Argon1 script"
    exit 1
  fi
  log "Downloaded Argon1 script to $script_path"
  log "Script size: $(wc -c < "$script_path") bytes"
  if ! chmod +x "$script_path"; then
    rm -f "$script_path"
    completeStage "failed to make Argon1 script executable"
    exit 1
  fi
  if ! bash "$script_path"; then
    rm -f "$script_path"
    completeStage "Argon1 script execution failed"
    exit 1
  fi
  log "Argon1 installation completed successfully"
  rm -f "$script_path"
}

installPackages() {
  log "Installing required packages"
  if ! apt install -y --no-install-recommends \
    x11-xserver-utils \
    unclutter \
    xscreensaver \
    chromium; then
    completeStage "package installation failed"
    exit 1
  fi
}

configureBash() {
  log "Configuring bash"
  cat > /home/admin/.bash_aliases <<'EOF' || { completeStage "failed to write bash aliases"; exit 1; }
alias ll='ls -halF'
alias reload='source ~/.bashrc'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gup='git pull --rebase'
alias gst='git status -sb'

go () {
  git fetch
  git checkout $1
  git reset --hard origin/$1
  git status -sb
}

up () {
  local times=${1:-1}
  while [ $times -gt 0 ]; do
    cd ..
    times=$(( $times - 1 ))
  done
}
EOF
}

writeKioskScript() {
  log "Writing kiosk script"
  cat > /home/admin/kiosk.sh <<'EOF' || { completeStage "failed to write kiosk script"; exit 1; }
#!/usr/bin/env bash
set -e

# Wait for network (important on boot)
until getent hosts calendar.google.com >/dev/null; do
  sleep 2
done

# Disable screen blanking / power management
xset s off
xset -dpms
xset s noblank
xset q >/dev/null 2>&1 || sleep 3

# Start xscreensaver
# xscreensaver &

# Auto-hide mouse cursor
unclutter -idle 0.5 -root &

# Ensure profile exists
CHROME_PREFS="/home/admin/.config/chromium-kiosk/Default/Preferences"
if [ ! -f "$CHROME_PREFS" ]; then
  chromium --headless --disable-gpu about:blank >/dev/null 2>&1 || true
fi

# Let chromium think it always exited cleanly.
if [ -f "$CHROME_PREFS" ]; then
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' "$CHROME_PREFS"
  sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/' "$CHROME_PREFS"
fi

# Launch Chromium in kiosk mode
exec chromium \
  --user-data-dir="/home/admin/.config/chromium-kiosk" \
  --kiosk \
  --password-store=basic \
  --no-first-run \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=TranslateUI \
  --noerrdialogs \
  --overscroll-history-navigation=0 \
  --disable-session-restore \
  --new-window \
  --disable-pinch \
  "https://calendar.google.com"
EOF
  if ! chmod +x /home/admin/kiosk.sh; then
    completeStage "failed to make kiosk script executable"
    exit 1
  fi
}

writeAutoStartScript() {
  log "Writing auto-start script"
  if ! mkdir -p /home/admin/.config/autostart; then
    completeStage "failed to create autostart directory"
    exit 1
  fi
  cat > /home/admin/.config/autostart/mysky.desktop <<'EOF' || { completeStage "failed to write autostart desktop file"; exit 1; }
[Desktop Entry]
Type=Application
Name=MySky
Exec=/home/admin/kiosk.sh
# Optional: adjust as needed
StartupNotify=false
Terminal=false
EOF
}

forceRoot() {
  if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
  fi
}

configureOutput() {
  if [ ! -d ".init" ]; then
    mkdir -p .init
  fi
  if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    log "init started"
  fi
  if [ ! -f "$STAGE_FILE" ]; then
    touch "$STAGE_FILE"
    completeStage
  fi
}

inferStage() {
  INIT_STAGE_CONTENTS=$(cat "$STAGE_FILE")
  CURRENT_STAGE=$(echo "$INIT_STAGE_CONTENTS" | wc -l | xargs)
  PREVIOUS_STAGE_RESULT=$(echo "$INIT_STAGE_CONTENTS" | tail -n 1 | cut -d'|' -f3- | xargs)
  if [ "$PREVIOUS_STAGE_RESULT" != "success" ]; then
    echo "Initialization previously failed:"
    echo "  stage: $CURRENT_STAGE"
    echo "  message: $PREVIOUS_STAGE_RESULT"
    echo "Please check $LOG_FILE for more details."
    exit 1
  fi
}

# -------------------------------------
#   VARIABLES
# -------------------------------------

LOG_FILE=".init/logs.txt"
STAGE_FILE=".init/stage.txt"
INIT_STAGE_CONTENTS=""
CURRENT_STAGE=0
PREVIOUS_STAGE_RESULT=""

# -------------------------------------
#   SETUP
# -------------------------------------

forceRoot
configureOutput
inferStage

# -------------------------------------
#   STAGES
# -------------------------------------

if [ "$CURRENT_STAGE" -eq 1 ]; then
  echo ">>> Stage 1: System Updates <<<"
  updateSystemPackages
  updateBootloader
  completeStage
  reboot
fi

if [ "$CURRENT_STAGE" -eq 2 ]; then
  echo ">>> Stage 2: System Configuration <<<"
  enableUsbBoot
  bootToDesktop
  useX11
  setResolution  # Is this actually needed?
  completeStage
  reboot
fi

if [ "$CURRENT_STAGE" -eq 3 ]; then
  echo ">>> Stage 3: Package Installation <<<"
  installPackages
  completeStage
  # reboot
fi

if [ "$CURRENT_STAGE" -eq 4 ]; then
  echo ">>> Stage 4: Optional Argon1 Installation <<<"
  installArgon1
  completeStage
  # reboot
fi

if [ "$CURRENT_STAGE" -eq 5 ]; then
  echo ">>> Stage 5: User Configuration & Scripts <<<"
  configureBash
  writeKioskScript
  writeAutoStartScript
  completeStage
  reboot
fi

if [ "$CURRENT_STAGE" -gt 5 ]; then
  echo "Initialization complete!"
  exit 0
fi
