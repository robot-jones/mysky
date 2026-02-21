# MySky

DIY Smart Calendar

## OS

Raspberry Pi OS 64-bit (trixie)

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

## Setup

_**NOTE:** You may have to update your Pi's bootloader if it doesn't support booting from USB._

### 1. Image the OS

I used the Raspberry Pi Imager app on another computer to image the OS onto a USB flash drive. Here are the settings I used:
- Model: Raspberry Pi 4
- OS: Raspberry Pi OS 64-bit (trixie)
- Target: USB Flash Drive
- Hostname: mysky
- Username: admin
- Set a Password
- Configure Wifi
- Enable SSH
- Enable Connect

### 2. Clone the Repo

```bash
git clone https://github.com/robot-jones/mysky.git
```

### 3. Run the Initialization Script

#### Things to know before you run:

- The `init.sh` script needs to run as root (`sudo`)
- It runs in several stages, some requiring a reboot
- Each subsequent run picks up where the previous one left off
- After the last reboot it should boot right into kiosk mode

```bash
cd mysky
sudo ./init.sh
```

## On the Horizon

- Custom UI: Need to decide on the approach:
  - Fork an open source project and customize
  - build it with NextJS
  - build it with React (create-react-app)
