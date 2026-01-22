# FlexNet - NetPC Server for Flex Systems

FlexNet is a Linux-based NetPC server that allows Flex operating systems running on 6800/6809 microprocessors to access disk images stored on a host computer via serial connections.

## Version 2.2.0 Features

### 🚀 Multi-Port Support
- **Simultaneous Connections**: Serve multiple Flex systems at the same time
- **Independent Sessions**: Each port operates independently with its own configuration
- **YAML Configuration**: Centralized configuration file for all ports

### 💾 Multi-Drive Support (NEW in 2.2.0)
- **Up to 4 Drives per Port**: Each serial port can serve up to 4 disk images (A:, B:, C:, D:)
- **Drive Selection**: Flex systems can access different drives on the same port
- **Independent Drive Management**: Each drive can have different disk images and geometries

### 🔧 Daemon Mode
- **Background Operation**: Run as a system daemon with proper PID management
- **Signal Handling**: Graceful shutdown with SIGTERM/SIGINT
- **System Logging**: Comprehensive logging via syslog for daemon operations

### 📡 Protocol Support
- **NetPC Protocol**: Full implementation of the original NetPC protocol
- **Disk Formats**: Single and double density Flex disk images (.DSK files)
- **Checksum Validation**: Data integrity verification for all transfers

## Installation

### Prerequisites
```bash
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install gcc libyaml-dev

# RedHat/CentOS/Fedora
sudo yum install gcc libyaml-devel
```

### Build
```bash
git clone https://github.com/linuxha/flexnet.git
cd flexnet
gcc -o flexnet flexnet_final.c -lyaml
```

## Configuration

### Single Port Mode (Legacy)
```bash
# Direct command line usage
./flexnet -d /dev/ttyS0 -s 19200 disk.dsk
```

### Multi-Port Multi-Drive Mode
Create a YAML configuration file:

```yaml
# flexnet.yaml
ports:
  - device: /dev/ttyS0
    speed: 19200
    drives:
      - disk: system.dsk      # Drive A:
      - disk: data.dsk        # Drive B:
      - disk: games.dsk       # Drive C:
      - disk: utilities.dsk   # Drive D:
  
  - device: /dev/ttyUSB0
    speed: 9600
    drives:
      - disk: development.dsk # Drive A:
      - disk: backup.dsk      # Drive B:
```

Run with configuration:
```bash
# Foreground mode
./flexnet -c flexnet.yaml -v

# Daemon mode
./flexnet -D -c flexnet.yaml
```

## Usage

### Command Line Options
- `-c <config>` : YAML configuration file (multi-port mode)
- `-d <device>` : Serial device (single port mode)
- `-s <speed>`  : Baud rate (single port mode)
- `-v` : Verbose debug output
- `-D` : Run as daemon (background)
- `-V` : Show version
- `-h` : Show help

### Supported Baud Rates
- 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200

### Serial Devices
- `/dev/ttyS0`, `/dev/ttyS1` - Hardware serial ports
- `/dev/ttyUSB0`, `/dev/ttyUSB1` - USB serial adapters
- `/dev/ttyACM0` - USB CDC ACM devices

## NetPC Protocol Commands

| Command | Description | Multi-Drive Support |
|---------|-------------|-------------------|
| `S`/`s` | Send/read sector from disk | ✓ Drive selection via parameter |
| `R`/`r` | Receive/write sector to disk | ✓ Drive selection via parameter |
| `A` | List .dsk files in directory | - |
| `I` | List subdirectories | - |
| `P` | Change directory (RCD) | - |
| `M` | Mount disk image (RMOUNT) | ✓ Specify drive to mount |
| `E` | Exit/disconnect | - |
| `Q` | Quick drive ready check | ✓ Check specific drive |
| `V` | Query drive letter (MS-DOS compatibility) | ✓ |
| `?` | Query current directory | - |

## Disk Image Support

### Supported Formats
- **Single Density**: 18 sectors/track, 35-80 tracks
- **Double Density**: Mixed density (SD track 0, DD tracks 1+)
- **Custom Geometries**: Unusual track/sector configurations

### File Extensions
- `.dsk` - Flex disk images
- `.DSK` - Flex disk images (case insensitive)

## System Integration

### systemd Service
Create `/etc/systemd/system/flexnet.service`:
```ini
[Unit]
Description=FlexNet NetPC Server
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/flexnet -D -c /etc/flexnet.yaml
PIDFile=/var/run/flexnet.pid
Restart=always
User=flexnet
Group=dialout

[Install]
WantedBy=multi-user.target
```

Enable service:
```bash
sudo systemctl enable flexnet
sudo systemctl start flexnet
```

### User Permissions
Add user to dialout group for serial port access:
```bash
sudo usermod -a -G dialout $USER
```

## Development

### Architecture
- **Multi-threaded**: Each port runs in its own context
- **Event-driven**: Uses `select()` for efficient I/O multiplexing
- **Modular**: Clean separation between single-port and multi-port modes

### Code Structure
- `flexnet_final.c` - Main multi-port implementation
- `flexnet_original.c` - Original single-port version
- `example.yaml` - Configuration file template

### Building from Source
```bash
# Debug build
gcc -g -DDEBUG -o flexnet_debug flexnet_final.c -lyaml

# Optimized build
gcc -O2 -o flexnet_release flexnet_final.c -lyaml
```

## Troubleshooting

### Common Issues

**Permission denied on serial port:**
```bash
sudo chmod 666 /dev/ttyS0
# or add user to dialout group
sudo usermod -a -G dialout $USER
```

**YAML parsing errors:**
```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('flexnet.yaml'))"
```

**Daemon not starting:**
```bash
# Check logs
journalctl -u flexnet -f
# or
tail -f /var/log/syslog | grep flexnet
```

### Debug Mode
Enable verbose output to troubleshoot protocol issues:
```bash
./flexnet -v -c config.yaml
```

## Version History

- **2.2.0** (2026-01-22) - Multi-drive support (up to 4 drives per port)
- **2.1.0** (2026-01-22) - Multi-port support and YAML configuration
- **2.0.0** (2026-01-22) - Daemon mode and enhanced logging
- **1.x** - Original single-port implementation

## License

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2, or (at your option) any later version.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

- GitHub Issues: [https://github.com/linuxha/flexnet/issues](https://github.com/linuxha/flexnet/issues)
- Documentation: See `PROTOCOL.md` for detailed protocol specification
- Examples: Check `example.yaml` for configuration templates

# History
