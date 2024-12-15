# Khanfar-PI-TX-PC

A powerful GUI control software for rpitx that allows you to control your Raspberry Pi transmitter from any PC on the same network.

## Table of Contents
1. [Overview](#overview)
2. [System Requirements](#system-requirements)
3. [Installation Guide](#installation-guide)
4. [Configuration](#configuration)
5. [Features](#features)
6. [Usage Guide](#usage-guide)
7. [Advanced Features](#advanced-features)
8. [Troubleshooting](#troubleshooting)
9. [Development](#development)
10. [Security](#security)
11. [Maintenance](#maintenance)
12. [Support](#support)
13. [License](#license)

## Overview

Khanfar-PI-TX-PC is a comprehensive RF transmission control system that enables remote operation of a Raspberry Pi transmitter through an intuitive GUI interface. The system supports multiple transmission modes and provides advanced features for both amateur radio enthusiasts and professional users.

## System Requirements

### Raspberry Pi (Server)
- Hardware:
  - Raspberry Pi (B+ or newer)
  - GPIO4 (Pin 7) for antenna
  - RTL-SDR dongle (for transponder mode)
- Software:
  - Raspbian OS
  - Python 3.7+
  - Internet connection

### Control PC (Client)
- Python 3.7+
- Network connection to Raspberry Pi
- Modern web browser

## Installation Guide

### 1. Quick Installation

#### On Raspberry Pi:
```bash
# Update and install dependencies
sudo apt-get update
sudo apt-get install python3 python3-pip git
sudo apt-get install csdr rtl-sdr buffer

# Clone and install
git clone https://github.com/khanfar/Khanfar-PI-TX-PC
cd Khanfar-PI-TX-PC
./install.sh
sudo reboot
```

### 2. Detailed Installation

#### A. Raspberry Pi Setup
1. OS Installation:
   - Download latest Raspbian OS
   - Use Raspberry Pi Imager
   - Enable SSH during imaging

2. Network Configuration:
   ```bash
   sudo nano /etc/wpa_supplicant/wpa_supplicant.conf
   ```
   Add:
   ```
   network={
       ssid="your_wifi_name"
       psk="your_wifi_password"
   }
   ```

3. Additional Dependencies:
   ```bash
   sudo apt-get install git build-essential cmake pkg-config
   sudo apt-get install python3-numpy python3-scipy python3-matplotlib
   ```

#### B. RTL-SDR Configuration
1. Driver Setup:
   ```bash
   sudo nano /etc/modprobe.d/blacklist-rtl.conf
   ```
   Add:
   ```
   blacklist dvb_usb_rtl28xxu
   blacklist rtl2832
   blacklist rtl2830
   ```

2. Testing:
   ```bash
   sudo modprobe -r dvb_usb_rtl28xxu rtl2832
   rtl_test -t
   ```

## Server Installation (Raspberry Pi)

### 1. Initial Setup
```bash
# Update system and install dependencies
sudo apt-get update
sudo apt-get install python3 python3-pip git csdr rtl-sdr buffer

# Clone the repository
git clone https://github.com/khanfar/Khanfar-PI-TX-PC

# Enter project directory and install
cd Khanfar-PI-TX-PC
./install.sh

# Reboot to apply changes
sudo reboot
```

### 2. Running the Server
```bash
# After reboot, navigate to the server directory
cd Khanfar-PI-TX-PC/src/python

# Start the server
python3 rpitx_server.py
```

### 3. Verifying Server Operation
1. Check server status:
   ```bash
   # Check if server is running
   ps aux | grep rpitx_server.py
   
   # Check port status
   netstat -tuln | grep 5252
   ```

2. Test server response:
   ```bash
   # Test local connection
   curl localhost:5252
   ```

### 4. Automatic Server Start (Optional)
1. Create service file:
   ```bash
   sudo nano /etc/systemd/system/rpitx-server.service
   ```
   Add:
   ```ini
   [Unit]
   Description=Khanfar-PI-TX-PC Server
   After=network.target

   [Service]
   ExecStart=/usr/bin/python3 /home/pi/Khanfar-PI-TX-PC/src/python/rpitx_server.py
   WorkingDirectory=/home/pi/Khanfar-PI-TX-PC/src/python
   User=pi
   Group=pi
   Restart=always

   [Install]
   WantedBy=multi-user.target
   ```

2. Enable and start service:
   ```bash
   sudo systemctl enable rpitx-server
   sudo systemctl start rpitx-server
   ```

3. Check service status:
   ```bash
   sudo systemctl status rpitx-server
   ```

## Configuration

### Network Setup

#### Server (Raspberry Pi)
1. Enable SSH:
   ```bash
   sudo systemctl enable ssh
   sudo systemctl start ssh
   ```

2. Configure Firewall:
   ```bash
   sudo ufw allow 5252
   ```

#### Client (Control PC)
- Ensure network connectivity
- Verify port 5252 accessibility
- Test connection to Raspberry Pi

## Features

### 1. Transmission Modes

#### Audio Modes
- FM/NFM Transmission
  - Wide-band FM (15 kHz deviation)
  - Narrow-band FM (5 kHz deviation)
  - Real-time streaming
  
- AM Transmission
  - Adjustable modulation depth
  - Carrier level control
  
- SSB Operation
  - USB/LSB modes
  - DSB to SSB conversion
  - Automatic gain control
  
- FreeDV Digital Voice
  - Multiple codecs (700D/1600/3200)
  - Forward Error Correction

#### Digital Modes
- SSTV
  - Martin M1/M2
  - Scottie S1/S2
  - Robot 36
  
- RTTY
  - 45-300 baud rates
  - Multiple shifts
  
- Morse Code
  - 5-50 WPM
  - Farnsworth timing
  
- Modern Protocols
  - FT8
  - FSQ
  - Opera
  - POCSAG

#### Special Features
- Spectrum Painting
- Chirp Generation
- Carrier Testing
- IQ Recording/Playback
- Transponder Mode

### 2. GUI Features

#### Main Interface
- Status monitoring
- Mode selection
- Connection management
- Settings access

#### Mode-Specific Controls
- Frequency control
- Power adjustment
- Filter settings
- Modulation parameters

#### Advanced Controls
- Spectrum display
- Waterfall view
- Signal processing
- Recording options

## Usage Guide

### Basic Operation

1. Start Server:
   ```bash
   cd Khanfar-PI-TX-PC/src/python
   python3 rpitx_server.py
   ```

2. Launch Client:
   ```bash
   cd Khanfar-PI-TX-PC/src/python
   python rpitx_client.py
   ```

### Mode-Specific Operations

#### SSB Mode
1. Install dependencies:
   ```bash
   sudo apt-get install csdr
   ```
2. Configure:
   - Set frequency
   - Choose sideband
   - Adjust filters
3. Operate:
   - Select audio source
   - Monitor levels
   - Begin transmission

#### Transponder Mode
1. Hardware setup:
   - Connect RTL-SDR
   - Configure antenna
2. Operation:
   - Set input/output frequencies
   - Adjust gain (0-45)
   - Monitor performance

## Advanced Features

### Audio Processing
- Input selection
- Noise reduction
- Compression
- Equalization

### Recording
- IQ data capture
- Audio recording
- Format conversion
- Storage management

## Troubleshooting

### Common Issues

#### Audio Problems
- Input detection
- Level adjustment
- Quality optimization

#### RTL-SDR Issues
- Device recognition
- Driver conflicts
- Reception quality

#### Network Problems
- Connection timeout
- Latency issues
- Buffer management

## Development

### Customization
- Mode development
- Plugin creation
- GUI modifications
- Feature integration

## Security

### Network Security
- VPN implementation
- Authentication
- Connection monitoring

### RF Safety
- Power compliance
- Frequency regulations
- Interference prevention

## Maintenance

### Regular Tasks
```bash
# System updates
sudo apt-get update
sudo apt-get upgrade

# Log management
sudo journalctl --vacuum-time=30d

# Backup
sudo cp /etc/khanfar-pi-tx/* /backup/
```

### Monitoring
- CPU usage
- Temperature
- Network performance
- Storage status

## Support
For issues and feature requests, please use the [GitHub Issues](https://github.com/khanfar/Khanfar-PI-TX-PC/issues) page.

## License
This project is licensed under the same terms as rpitx. See the LICENSE file for details.

---
sudo apt-get install git build-essential cmake libfftw3-dev
chmod+x easytest.sh
sudo ./install.sh
rm -rf Khanfar-PI-TX-PC
sudo passwd root
chmod+x easytest.sh
---

Developed by KhanfarSystems
