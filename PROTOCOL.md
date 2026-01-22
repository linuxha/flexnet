# NetPC Protocol Specification

## Overview

The NetPC protocol is a serial communication protocol that allows Flex operating systems running on 6800/6809 microprocessors to access disk images stored on a remote host system. This document describes the protocol as implemented in the flexnet server.

## Connection Parameters

- **Interface**: Serial (RS-232)
- **Data Format**: 8 data bits, no parity, 1 stop bit
- **Flow Control**: None (software)
- **Speed**: Configurable (typically 19200 baud for Microbox systems)

## Protocol Characteristics

- **Command-Response**: Each command from client receives a response
- **Binary Protocol**: Uses raw binary data for sector transfers
- **Error Detection**: Checksums for data integrity
- **Stateful**: Server maintains current directory and mounted disk state

## Command Format

Commands are single ASCII characters followed by optional parameters:

```
[COMMAND][PARAMETERS...][CR]
```

Where:
- `COMMAND` = Single ASCII character (case insensitive for most commands)
- `PARAMETERS` = Command-specific data
- `CR` = Carriage Return (0x0D) - parameter terminator

## Control Characters

| Character | Hex  | Purpose |
|-----------|------|---------|
| CR        | 0x0D | Parameter terminator |
| LF        | 0x0A | Line feed in responses |
| ACK       | 0x06 | Positive acknowledgment |
| NAK       | 0x15 | Negative acknowledgment |
| ESC       | 0x1B | Abort/escape sequence |

## Command Reference

### Synchronization Commands

#### 0x55, 0xAA - Synchronization
```
Client -> Server: [0x55 or 0xAA]
Server -> Client: [same byte echoed back]
```
**Purpose**: Establish or re-establish communication synchronization.

### Sector I/O Commands

#### S/s - Send Sector (Read from Disk)
```
Client -> Server: 'S' [drive] [track] [sector]
Server -> Client: [256 data bytes] [checksum MSB] [checksum LSB]
Client -> Server: [ACK or NAK]
```

**Parameters**:
- `drive`: Drive number (typically 0)
- `track`: Track number (0-255)  
- `sector`: Sector number (0-255, but 0 only valid for track 0)

**Data Format**:
- 256 bytes of sector data
- 16-bit additive checksum (MSB first)

**Error Handling**:
- Invalid track/sector: Server sends zeros
- No disk mounted: Server sends zeros with bad checksum
- Checksum error: Client sends NAK, server retransmits

#### R/r - Receive Sector (Write to Disk)
```
Client -> Server: 'R' [drive] [track] [sector] [256 data bytes] [checksum MSB] [checksum LSB]
Server -> Client: [ACK or NAK]
```

**Validation**:
- Checksum must match received data
- Track/sector must be valid for current disk
- Disk must be mounted and writable

### Directory Commands

#### A - List Disk Images (RDIR)
```
Client -> Server: 'A' [pattern] [CR]
Server -> Client: [CR] [LF]
    For each matching file:
        Client -> Server: [SPACE]
        Server -> Client: [filename] [CR] [LF]
Client -> Server: [SPACE] (when ready for more) or [ESC] (to abort)
Server -> Client: [ACK]
```

**Purpose**: List .DSK files in current directory matching pattern.

#### I - List Directories (RLIST)
```
Client -> Server: 'I' [pattern] [CR]
Server -> Client: [expected response byte]
Server -> Client: [CR] [LF]
    For each directory:
        Client -> Server: [0x20]
        Server -> Client: [directory name] [CR] [LF]
Client -> Server: [0x20] (when done)
Server -> Client: [ACK]
```

**Purpose**: List subdirectories for navigation.

### File System Commands

#### P - Change Directory (RCD)
```
Client -> Server: 'P' [directory path] [CR]
Server -> Client: [ACK or NAK]
```

**Purpose**: Change server's current working directory.

#### M - Mount Disk Image (RMOUNT)
```
Client -> Server: 'M' [disk name] [CR]
Server -> Client: [ACK] [R or W] (success) or [NAK] (failure)
```

**Response Codes**:
- `ACK` followed by `R`: Disk mounted read-only
- `ACK` followed by `W`: Disk mounted read-write
- `NAK`: Mount failed

**File Extension**: Server automatically appends `.DSK` (tries uppercase first, then lowercase).

#### ? - Query Current Directory
```
Client -> Server: '?'
Server -> Client: [current directory path] [CR] [ACK]
```

### Status Commands

#### Q - Quick Drive Ready Check
```
Client -> Server: 'Q'
Server -> Client: [ACK]
```

**Purpose**: Check if drive is ready. Unix implementation always returns ACK.

#### V - Drive Letter Query (MS-DOS Compatibility)
```
Client -> Server: 'V' [parameters] [CR]
Server -> Client: [ACK]
```

**Purpose**: Legacy MS-DOS drive letter command. Ignored on Unix systems.

### Session Commands

#### E - Exit (REXIT)
```
Client -> Server: 'E'
Server -> Client: [ACK]
```

**Purpose**: Terminate server connection. Server exits after sending ACK.

### Unimplemented Commands

#### C - Create Disk Image (RCREATE)
```
Client -> Server: 'C' [name] [CR] [tracks] [CR] [sectors] [CR] [params] [CR]
Server -> Client: [NAK]
```

#### D - Delete Disk Image (RDELETE)  
```
Client -> Server: 'D' [filename] [CR]
Server -> Client: [NAK]
```

**Status**: These commands are recognized but not implemented. Always return NAK.

## Disk Geometry

### Track/Sector Addressing

Flex uses track/sector addressing which is converted to linear block addressing:

- **Track 0**: May have different sector count (track0l sectors)
- **Other Tracks**: Standard sector count (nbsec sectors each)
- **Sector Numbering**: 
  - Track 0: sectors 0 to (track0l-1)
  - Other tracks: sectors 1 to nbsec

### Linear Block Calculation

```
if (track == 0):
    block = sector
else:
    block = track0l + (track-1) * nbsec + (sector-1)
```

### Supported Formats

- **Single Density**: All tracks have same sector count
- **Double Density**: Track 0 may have fewer sectors (single density)
- **Custom Geometry**: Unusual configurations supported

## Error Handling

### Client-Side Errors
- **Invalid Command**: Ignored by server
- **Transmission Errors**: Detected via checksum, NAK response triggers retry
- **Connection Loss**: Server detects EOF and exits

### Server-Side Errors
- **Disk Not Ready**: Zero data with bad checksum forces client error
- **Invalid Address**: Zero data returned
- **I/O Errors**: Zero data returned
- **Permission Errors**: NAK responses

### Checksum Algorithm

```c
checksum = 0
for (i = 0; i < 256; i++)
    checksum += data[i]
checksum = checksum & 0xFFFF
```

Transmitted as: `[MSB = (checksum >> 8) & 0xFF] [LSB = checksum & 0xFF]`

## Protocol States

### Server States
1. **Uninitialized**: No disk mounted
2. **Ready**: Disk mounted and accessible
3. **Read-Only**: Disk mounted but write-protected
4. **Error**: Disk mount failed or I/O error

### Directory Context
- Server maintains current working directory
- Disk image paths are relative to current directory
- Directory changes persist across disk mounts

## Implementation Notes

### Case Sensitivity
- Commands 'S'/'s' and 'R'/'r' are case insensitive
- File and directory names follow Unix case sensitivity rules
- Disk image extensions tried as ".DSK" then ".dsk"

### Buffer Sizes
- Sector data: 256 bytes fixed
- Command parameters: 127 characters maximum
- Directory paths: 255 characters maximum
- Filenames: 255 characters maximum

### Timing
- No explicit timing requirements
- Commands are synchronous (request/response)
- Client controls pacing of directory listings

## Security Considerations

- Server runs with user permissions of executing process
- No authentication mechanism
- Directory access limited to server's file system permissions
- Read-only disks enforced at Unix file system level

## Example Session

```
# Synchronization
Client: 0x55
Server: 0x55

# Query current directory  
Client: '?'
Server: "/home/user/disks" 0x0D 0x06

# List disk images
Client: 'A' "GAME" 0x0D
Server: 0x0D 0x0A
Client: 0x20
Server: "GAME1.DSK" 0x0D 0x0A
Client: 0x20
Server: "GAME2.DSK" 0x0D 0x0A  
Client: 0x20
Server: 0x06

# Mount disk
Client: 'M' "GAME1" 0x0D
Server: 0x06 'W'

# Read sector 0,2 (directory sector)
Client: 'S' 0x00 0x00 0x02
Server: [256 bytes of data] [MSB] [LSB]
Client: 0x06

# Exit
Client: 'E'
Server: 0x06
```

## References

- Original NetPC protocol by Bjarne Bäckström and Ron Anderson
- Flex Operating System disk format specification
- This implementation: flexnet.c by Michel Wurtz