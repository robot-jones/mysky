# MySky

DIY Smart Calendar

## Hardware

- Raspberry Pi 4 Model B Rev 1.4 (8GB RAM)
- 32GB USB Flash Drive
- Argon ONE V2 Case
- CAPERAVE Portable Monitor 15.6 inch FHD Touchscreen (Model: CF-15T-1)
- USB Keyboard/Mouse (currently needed for initial setup)
- Cables:
  - micro-HDMI -> HDMI (video)
  - USB-C (touch)
  - USB-C -> power adapter (pi)
  - USB-C -> power adapter (display)
- [Upcoming] HC-SR501 PIR motion sensor w/ jumper wires and mount

## Image the OS

1. Download and run Raspberry Pi Imager
2. Choose these settings
   - model: Raspberry Pi 4
   - OS: Raspberry Pi OS 64-bit (trixie)
   - target: USB Flash Drive
   - hostname: mysky
   - username: admin
   - set a password
   - ccnfigure wifi
   - enable SSH
   - enable Connect
3. Write the image

## Initialization Script

### Usage
```bash
sudo ./init.sh [--reset|--help]
  --reset: Clear initialization state to start fresh
  --help: Show this help message
```

- The `init.sh` script needs to be run as admin (with `sudo`)
- It runs in several stages (some requiring reboot)
- Each subsequent run picks up where the previous one left off
- The script needs to run until it boots to the calendar in kiosk mode
- If the script encounters an error, you might be able to find more context in the logs found in `.init/`

## On the Horizon

- Custom UI: Need to decide on the approach:
  - Fork an open source project and customize
  - build it with NextJS
  - build it with React (create-react-app)
