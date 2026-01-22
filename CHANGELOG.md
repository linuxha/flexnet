# FlexNet Development Log

## Version 2.2.0 - January 22, 2026

### New Features
- **Multi-Drive Support**: Each port can now serve up to 4 disk images (drives A-D)
- **Enhanced YAML Configuration**: Support for drive arrays in configuration files
- **Improved Protocol Handling**: Drive selection support in sector operations
- **Code Quality**: All compilation warnings resolved

### Files Modified
- `flexnet_final.c` - Main implementation with multi-drive support
- `example.yaml` - Updated with multi-drive configuration examples
- `README.md` - Comprehensive documentation update
- `Makefile.multiport` - Build system improvements

### Technical Changes
- Updated `port_config_t` structure to include drive arrays
- Added `ts2blk_multi()` function for multi-drive track/sector conversion
- Enhanced signal handling for proper multi-drive cleanup
- Fixed all gcc warnings (unused variables, dangling else, missing returns)

## Version 2.1.0 - January 22, 2026

### New Features
- **Multi-Port Support**: Simultaneous connections via YAML configuration
- **YAML Integration**: Configuration file support using libyaml
- **Daemon Infrastructure**: Background operation capabilities

### Files Created
- `flexnet_final.c` - Multi-port implementation base
- `example.yaml` - Configuration template
- `Makefile.multiport` - Enhanced build system

### Technical Changes
- Added `port_config_t` structure for multi-port management
- Implemented `load_config()` function for YAML parsing
- Added daemon support functions (daemonize, signal_handler, etc.)

## Version 2.0.0 - January 22, 2026

### New Features
- **Daemon Mode**: Background operation with PID management
- **Signal Handling**: Graceful shutdown support
- **Enhanced Logging**: Syslog integration for daemon operations
- **Improved CLI**: Version and help options

### Files Modified
- `flexnet.c` - Added daemon support and logging functions

### Technical Changes
- Added `daemonize()` function for background operation
- Implemented signal handlers for clean shutdown
- Added `log_message()` function for unified logging

## Previous Versions

### Version 1.x (Original Implementation)
- Single-port NetPC server
- Basic protocol support (sector read/write, directory operations)
- Direct serial communication
- Single disk image per instance

## Development Notes

### Build Requirements
- gcc compiler
- libyaml-dev library for configuration parsing
- Standard POSIX libraries

### Testing
All versions tested with:
- Clean compilation (no warnings)
- Version display functionality
- Configuration loading
- Help text display

### Backward Compatibility
All versions maintain compatibility with original NetPC protocol and single-port operation mode.