#!/bin/bash

# This script performs a series of steps to set up a Raspberry Pi for use as a
# MySky calendar display. It is designed to be idempotent and can be safely
# re-run if any step fails, allowing you to fix the underlying issue and
# continue without losing progress. Some stages will automatically reboot.
# You simply continue to re-run the script until all stages are complete, and
# the system finally boots up to the calendar display in kiosk mode.

# -------------------------------------
#   GLOBAL CONSTANTS
# -------------------------------------

OUTPUT_PATH=".init"
LOG_FILE="$OUTPUT_PATH/logs.txt"
STAGE_FILE="$OUTPUT_PATH/stage.txt"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
LIGHT_GRAY='\033[0;37m'
NC='\033[0m'

# -------------------------------------
#   GLOBAL VARIABLES
# -------------------------------------

CURRENT_STAGE=0

# -------------------------------------
#   HELPER FUNCTIONS
# -------------------------------------

getTimestamp() {
  date -Iseconds
}

getStageText() {
  echo "Stage $CURRENT_STAGE"
}

# -------------------------------------
#   SCRIPT FUNCTIONS
# -------------------------------------

forceRoot() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}This script must be run as root.${NC}"
    exit 1
  fi
}

reset() {
  echo -e "${YELLOW}Resetting initialization state...${NC}"
  rm -rf .init
  echo -e "${GREEN}Initialization state reset. You can now run the script again to start fresh.${NC}"
}

showHelp() {
  echo ""
  echo "Usage: sudo ./init.sh [--reset|--help]"
  echo "  --reset: Clear initialization state to start fresh"
  echo "  --help: Show this help message"
}

displayBanner() {
  echo "┌──────────────────────┐"
  echo "│  MySky Raspberry Pi  │"
  echo "└──────────────────────┘"
}

log() {
  local color="${1:-$NC}"
  local message="${2:-}"
  echo -e "${LIGHT_GRAY}$(getTimestamp)${NC} | $(getStageText) | ${color}${message}${NC}"
  echo "$(getTimestamp) | $(getStageText) | $message" >> "$LOG_FILE"
}

prepOutput() {
  if [ ! -d "$OUTPUT_PATH" ]; then
    mkdir -p "$OUTPUT_PATH"
  fi
  if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
  fi
  if [ ! -f "$STAGE_FILE" ]; then
    touch "$STAGE_FILE"
    echo "$(getTimestamp) | $(getStageText) | success" >> "$STAGE_FILE"
  fi
}

handleArgs() {
  # Only handle the first argument for simplicity
  local arg=$1

  if [ "$arg" == "--reset" ]; then
    reset
    exit 0
  fi

  if [ "$arg" == "--help" ] || [ "$arg" == "-h" ]; then
    showHelp
    exit 0
  fi
}

# -------------------------------------
#   STAGE FUNCTIONS
# -------------------------------------

updateStageVariables() {
  local stage_contents=$(cat "$STAGE_FILE")
  CURRENT_STAGE=$(echo "$stage_contents" | wc -l | xargs)
  local previous_stage_result=$(echo "$stage_contents" | tail -n 1 | cut -d'|' -f3- | xargs)
  if [ "$previous_stage_result" != "success" ]; then
    echo -e "${RED}Initialization previously failed:${NC}"
    echo -e "${RED}  stage: ${CURRENT_STAGE}${NC}"
    echo -e "${RED}  message: ${previous_stage_result}${NC}"
    echo -e "${YELLOW}Please check ${LOG_FILE} for more details.${NC}"
    exit 1
  fi
}

failStage() {
  local message=${1:-"Unknown error"}
  echo "$(getTimestamp) | $(getStageText) | $message" >> "$STAGE_FILE"
  log "$RED" "$(getStageText) failed: $message"
  exit 1
}

completeStage() {
  echo "$(getTimestamp) | $(getStageText) | success" >> "$STAGE_FILE"
  log "$GREEN" "$(getStageText) completed successfully"
  updateStageVariables
}

stageReboot() {
  local message=${1:-"** A reboot is required **"}
  log "$YELLOW" "$message"
  read -n 1 -r -s -p "Press any key to reboot..."
  reboot
}

# -------------------------------------
#   STEP FUNCTIONS
# -------------------------------------

updateSystemPackages() {
  log "$BLUE" "Updating system packages"
  if ! apt update; then
    failStage "apt update failed"
  fi
  if ! apt upgrade -y; then
    failStage "apt upgrade failed"
  fi
}

updateBootloader() {
  log "$BLUE" "Updating Raspberry Pi bootloader"
  if ! rpi-eeprom-update -a; then
    failStage "bootloader update failed"
  fi
}

enableUsbBoot() {
  log "$BLUE" "Enabling USB boot"
  if ! raspi-config nonint do_boot_order 0xf14; then
    failStage "usb boot configuration failed"
  fi
}

bootToDesktop() {
  log "$BLUE" "Enabling boot to desktop"
  if ! raspi-config nonint do_boot_behaviour B4; then
    failStage "boot to desktop configuration failed"
  fi
}

useX11() {
  log "$BLUE" "Using X11 instead of Wayland"
  if ! raspi-config nonint do_wayland W1; then
    failStage "X11 configuration failed"
  fi
}

setResolution() {
  log "$BLUE" "Setting HDMI resolution to 1080p"
  if ! grep -q "video=HDMI-A-1:1920x1080@60" /boot/firmware/cmdline.txt 2>/dev/null; then
    if ! echo -n " video=HDMI-A-1:1920x1080@60" >> /boot/firmware/cmdline.txt; then
      failStage "failed to write resolution to cmdline.txt"
    fi
  else
    log "$YELLOW" "Resolution already set, skipping"
  fi
}

installArgon1() {
  log "$BLUE" "Installing Argon1 themes and tools"
  local script_path="/tmp/argon1.sh"
  if ! curl -fsSL -o "$script_path" https://download.argon40.com/argon1.sh; then
    failStage "failed to download Argon1 script"
  fi
  log "$BLUE" "Downloaded Argon1 script to $script_path"
  log "$BLUE" "Script size: $(wc -c < "$script_path") bytes"
  if ! chmod +x "$script_path"; then
    rm -f "$script_path"
    failStage "failed to make argon1 script executable"
  fi
  if ! bash "$script_path"; then
    rm -f "$script_path"
    failStage "argon1 script execution failed"
  fi
  log "$BLUE" "argon1 installation completed successfully"
  rm -f "$script_path"
}

installPackages() {
  log "$BLUE" "Installing required packages"
  if ! apt install -y --no-install-recommends \
    x11-xserver-utils \
    unclutter \
    xscreensaver \
    chromium; then
    failStage "package installation failed"
  fi
}

googleLogin() {
  log "$BLUE" "Configuring Google login"
  log "$YELLOW" "  1. Login to your Google account in the Chromium browser that opens."
  log "$YELLOW" "  2. After logging in, close the browser to continue initialization."
  if ! chromium --user-data-dir="/home/admin/.config/chromium-kiosk" --no-first-run "https://accounts.google.com/signin/v2/identifier?service=calendar"; then
    failStage "failed to open Chromium for Google login"
  fi
}

configureBash() {
  log "$BLUE" "Configuring bash"
  cat > /home/admin/.bash_aliases <<'EOF' || { failStage "failed to write bash aliases"; }
alias ll='ls -halF'
alias reload='source ~/.bashrc'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gup='git pull --rebase'
alias gst='git status -sb'

go () {
  git fetch
  git checkout "$1"
  git reset --hard origin/"$1"
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
  if ! chown admin:admin /home/admin/.bash_aliases; then
    failStage "failed to set ownership on bash aliases"
  fi
}

writeKioskScript() {
  log "$BLUE" "Writing kiosk script"
  cat > /home/admin/kiosk.sh <<'EOF' || { failStage "failed to write kiosk script"; }
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
  if [ ! -f "$CHROME_PREFS" ]; then
    echo "Failed to create Chromium profile, cannot continue"
    exit 1
  fi
fi

# Let chromium think it always exited cleanly.
if [ -f "$CHROME_PREFS" ]; then
  if grep -q '"exited_cleanly":false' "$CHROME_PREFS"; then
    sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' "$CHROME_PREFS"
  fi
  if grep -q '"exit_type":"Crashed"' "$CHROME_PREFS"; then
    sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/' "$CHROME_PREFS"
  fi
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
    failStage "failed to make kiosk script executable"
  fi
  if ! chown admin:admin /home/admin/kiosk.sh; then
    failStage "failed to set ownership on kiosk script"
  fi
}

writeAutoStartScript() {
  log "$BLUE" "Writing auto-start script"
  if ! mkdir -p /home/admin/.config/autostart; then
    failStage "failed to create autostart directory"
  fi
  cat > /home/admin/.config/autostart/mysky.desktop <<'EOF' || { failStage "failed to write autostart desktop file"; }
[Desktop Entry]
Type=Application
Name=MySky
Exec=/home/admin/kiosk.sh
# Optional: adjust as needed
StartupNotify=false
Terminal=false
EOF
  if ! chown -R admin:admin /home/admin/.config; then
    failStage "failed to set ownership on .config directory"
  fi
}

# -------------------------------------
#   SCRIPT START
# -------------------------------------

handleArgs $*
displayBanner
prepOutput
updateStageVariables

if [ "$CURRENT_STAGE" -eq 1 ]; then
  log "$BLUE" ">>> Stage 1/6: System Updates <<<"
  updateSystemPackages
  updateBootloader
  completeStage
  stageReboot
fi

if [ "$CURRENT_STAGE" -eq 2 ]; then
  log "$BLUE" ">>> Stage 2/6: System Configuration <<<"
  enableUsbBoot
  bootToDesktop
  useX11
  setResolution
  completeStage
  stageReboot
fi

if [ "$CURRENT_STAGE" -eq 3 ]; then
  log "$BLUE" ">>> Stage 3/6: Package Installation <<<"
  installPackages
  completeStage
fi

if [ "$CURRENT_STAGE" -eq 4 ]; then
  log "$BLUE" ">>> Stage 4/6: Optional Argon1 Installation <<<"
  installArgon1
  completeStage
fi

if [ "$CURRENT_STAGE" -eq 5 ]; then
  log "$BLUE" ">>> Stage 5/6: User Configuration <<<"
  configureBash
  googleLogin
  completeStage
fi

if [ "$CURRENT_STAGE" -eq 6 ]; then
  log "$BLUE" ">>> Stage 6/6: MySky Scripts <<<"
  writeKioskScript
  writeAutoStartScript
  completeStage
  stageReboot "Initialization complete! Rebooting into MySky calendar display..."
fi

if [ "$CURRENT_STAGE" -gt 6 ]; then
  log "$GREEN" "Initialization complete!"
  exit 0
fi
