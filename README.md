# Khanfar-PI-TX-PC

A powerful GUI control software for rpitx that allows you to control your Raspberry Pi transmitter from any PC on the same network. This project provides an easy-to-use interface for all rpitx transmission modes.

## Quick Installation

### 1. On Raspberry Pi:
```bash
# Install required packages
sudo apt-get update
sudo apt-get install python3 python3-pip git csdr rtl-sdr buffer

# Install Khanfar-PI-TX-PC server
git clone https://github.com/khanfar/Khanfar-PI-TX-PC
cd Khanfar-PI-TX-PC/src/python
python3 rpitx_server.py
```

### 2. On Control PC:
```bash
# Clone the repository
git clone https://github.com/khanfar/Khanfar-PI-TX-PC

# Navigate to client directory
cd Khanfar-PI-TX-PC/src/python

# Run the client
python rpitx_client.py
```

## Features

### Audio Transmission
- FM/NFM/AM/SSB modes
- FreeDV digital voice
- Configurable frequencies and parameters

### Digital Modes
- SSTV (Multiple modes: Martin1/2, Scottie1/2, Robot36)
- RTTY with adjustable baud rate
- Morse Code (adjustable WPM)
- POCSAG pager protocol
- FT8, FSQ, Opera digital modes

### Special Features
- Spectrum Painting
- Chirp signal generation
- Carrier wave testing
- IQ Recording and Playback
- Transponder mode (requires RTL-SDR)

## System Requirements

### Raspberry Pi
- Raspberry Pi (B+ or newer)
- Raspbian OS
- Internet connection
- GPIO4 (Pin 7) for antenna

### Control PC
- Python 3
- Network connection to Raspberry Pi

## Usage

1. Start the server on Raspberry Pi:
```bash
cd Khanfar-PI-TX-PC/src/python
python3 rpitx_server.py
```

2. Launch the client on your PC:
```bash
cd Khanfar-PI-TX-PC/src/python
python rpitx_client.py
```

3. In the client:
   - Enter your Raspberry Pi's IP address
   - Default port is 5252
   - Select transmission mode from tabs
   - Configure settings and start transmission

## Safety Notes
- Connect antenna to GPIO4 (Pin 7)
- Follow local RF transmission regulations
- Use appropriate filtering
- Check frequency restrictions

## Support
For issues and feature requests, please use the [GitHub Issues](https://github.com/khanfar/Khanfar-PI-TX-PC/issues) page.

## Credits
- GUI Control System by KhanfarSystems

## License
This project is licensed under the same terms as rpitx. See the LICENSE file for details.

---
Developed by KhanfarSystems
