/* flexnet.c -- Linux NetPC server for Flex systems
 *
 * Copyright (C) 2025 Michel Wurtz - mjwurtz@gmail.com
 *
 * This program implements a NetPC server that allows Flex operating system
 * running on 6800/6809 microprocessors to access disk images stored on a Linux
 * host system via serial connection. It implements the NetPC protocol originally
 * used in Netpc35 (by Bjarne Bäckstrom and Ron Anderson) but is a completely
 * independent implementation.
 *
 * FUNCTIONALITY:
 * - Serves Flex disk images (.DSK files) over serial connection
 * - Supports both single and double density disk formats
 * - Handles track/sector to block conversion for different disk geometries
 * - Provides directory listing and navigation capabilities
 * - Supports disk mounting and unmounting operations
 * - Implements checksum validation for data integrity
 *
 * PROTOCOL COMMANDS:
 * - S/s: Send/read a sector from disk image
 * - R/r: Receive/write a sector to disk image
 * - A:   List .dsk files in current directory
 * - I:   List subdirectories
 * - P:   Change directory (RCD command)
 * - M:   Mount disk image (RMOUNT command)
 * - E:   Exit/disconnect
 * - Q:   Quick drive ready check
 * - V:   Query drive letter (MS-DOS compatibility, ignored)
 * - ?:   Query current directory
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <sys/types.h>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <getopt.h>
#include <dirent.h>

/* Constants and Protocol Definitions */

// Sector size for Flex floppy disks (always 256 bytes)
#define SECSIZE 256

// ASCII control characters used in NetPC protocol
#define LF  0x0a    // Line Feed (10)
#define CR  0x0d    // Carriage Return (13)
#define ACK 0x06    // Acknowledge (positive response)
#define NAK 0x15    // Negative Acknowledge (error response)
#define ESC 0x1B    // Escape character (27)

// Help message
void usage( char *cmd) {
    fprintf( stderr, "Usage: %s [-h] => this help\n", cmd);
    fprintf( stderr, "       %s [-v] -d <device> -s <speed> disk_image\n", cmd);
    fprintf( stderr, "Options:\n");
    fprintf( stderr, " -d <device> : serial line to use\n");
    fprintf( stderr, " -s <speed> : baudrate to use\n");
    fprintf( stderr, " -v : print requests to the server and reply (debug)\n");
}

/* Global Variables */

/* Serial Communication */
char line[32];              // Serial device path (/dev/ttyS0, /dev/ttyUSB0, etc.)
int  speed = 0;             // Serial line speed in baud (e.g., 19200 for Microbox)
FILE *serial;               // Serial port file handle for communication

/* Command Processing */
char param[128];            // Buffer for NetPC command parameters
static int verbose = 0;     // Debug output flag (set with -v option)

/* Directory Management */
char curdir[256];           // Current working directory path

/* Disk Image Management */
char filename[256];         // Full path to the current disk image file
char *diskname;             // Pointer to just the disk image filename (no path)
int fd;                     // File descriptor for the open disk image
int ready;                  // Flag: is a disk image currently mounted and ready?
int readonly;               // Flag: is the current disk image read-only?

/* Disk Geometry and I/O */
uint8_t bloc[SECSIZE];      // Sector buffer for read/write operations (256 bytes)
uint8_t nbtrk;              // Number of data tracks on the disk (from SIR)
uint8_t nbsec;              // Number of sectors per track (from SIR)
uint8_t track0l;            // Number of sectors on track 0 (may differ from nbsec)

/**
 * Convert Flex track/sector address to linear block number in disk image
 * 
 * Flex uses track/sector addressing, but Unix files are linear. This function
 * converts between the two addressing schemes, handling the complexity that
 * track 0 may have a different number of sectors than other tracks (common
 * in double-density disks with single-density track 0).
 * 
 * @param ntrk Track number (0-based)
 * @param nsec Sector number (1-based, except track 0 sector 0 is valid)
 * @return Linear block number (0-based), or -1 if invalid track/sector
 * 
 * DISK LAYOUT:
 * - Track 0: sectors 0 to (track0l-1)    [track0l sectors total]
 * - Track 1: sectors 1 to nbsec          [nbsec sectors]
 * - Track 2: sectors 1 to nbsec          [nbsec sectors]
 * - ...
 * - Track N: sectors 1 to nbsec          [nbsec sectors]
 */
int ts2blk( uint8_t ntrk, uint8_t nsec)
{
    // Validate track and sector numbers
    if (ntrk > nbtrk || nsec > nbsec || (nsec == 0 && ntrk != 0)) {
        return( -1);
    }

    if (ntrk == 0) {        // Track 0 has special handling
        if (nsec == 0) {    // Track 0, sector 0 is valid (Boot sector)
            return 0;
        } else {
            return (nsec - 1);  // Track 0 sectors are 0-based in image
        }
    } else {
        // Other tracks: skip track 0, then count full tracks, then add sector
        return track0l + (ntrk - 1) * nbsec + nsec - 1;
    }
}

/**
 * Extract and format a Flex filename from disk directory entry
 * 
 * Flex stores filenames in an 11-byte field: 8 bytes for name + 3 for extension.
 * This function extracts the name and optionally inserts a dot between name
 * and extension to create a standard "filename.ext" format.
 * 
 * @param pos Pointer to 11-byte filename field in directory entry
 * @param name Output buffer for formatted filename (must be at least 12 bytes)
 * @param dot 1 = insert dot for regular files, 0 = no dot for volume labels
 * @return Length of formatted name, or -1 if invalid characters found
 * 
 * VALID CHARACTERS: A-Z, 0-9, '-', '_', 0xFF (unused), ' ' (padding), '*', '.', 0
 * INVALID: Control characters, other symbols
 * 
 * EXAMPLES:
 *   "HELLO   TXT" with dot=1 -> "HELLO.TXT" (9 chars)
 *   "MYDISK     " with dot=0 -> "MYDISK" (6 chars)
 *   "TEST    "    with dot=1 -> "TEST" (4 chars, no extension)
 */
int getname( uint8_t *pos, char *name, int dot)
{
    int k = 0;
    for (int j=0; j<11; j++) {
        if (!isalnum(pos[j]) && pos[j] != '-' && pos[j] != '_' && pos[j] != 0xFF
            && pos[j] != ' ' && pos[j] != '*' && pos[j] != '.' && pos[j] != 0)
            return -1;

        if (dot && pos[j] == ' ')
            return -1;

        if (pos[j] != 0 )
            name[k++] = pos[j];

        if (j == 7)	{
            if (pos[8] == 0)
                break;

            if (dot)
                name[k++] = '.';
        }
    }
    name[k] = 0;
    return k;
}

/**
 * Load and validate a Flex disk image file
 * 
 * This function opens a disk image file, validates it as a proper Flex disk,
 * extracts geometry information from the System Information Record (SIR),
 * and sets up global variables for disk access.
 * 
 * @param name Path to the disk image file to load
 * @return 0 on success, -1 on error
 * 
 * FLEX DISK STRUCTURE:
 * - Sector 0,0: Boot sector (if bootable)
 * - Sector 0,1: System Information Record (SIR) - unused
 * - Sector 0,2: Directory Information Record (DIR) - contains disk geometry
 * - Sector 0,3+: Directory entries
 * 
 * GEOMETRY DETECTION:
 * The function analyzes the disk size and SIR data to determine:
 * - Single Density: all tracks have same number of sectors
 * - Double Density: track 0 may have fewer sectors (SD format)
 * - Custom geometry: handles unusual configurations
 * 
 * GLOBAL VARIABLES SET:
 * - fd: file descriptor for the disk image
 * - ready: set to 1 if disk loaded successfully
 * - readonly: set based on file permissions
 * - nbtrk, nbsec, track0l: disk geometry parameters
 * - filename, diskname: file path information
 */
int load_dsk( char *name)
{

    struct stat dsk_stat;
    int size;
    int nb_sectors;
    char label[16];
    int volnum;
    int last_trk_sec;	
    int freesec; 

    strncpy( filename, name, 256);
    diskname = strrchr( filename, '/');
    if (diskname == NULL)
        diskname = filename;
    else
        diskname++;

    if (stat( filename, &dsk_stat)) {
        if (verbose)
            perror( filename); 
        return -1;
    }

    // Open disk image
    diskname = strrchr( filename, '/');
    if (diskname == NULL)
        diskname = filename;
    else
        diskname++;

    size = dsk_stat.st_size;

    if (dsk_stat.st_mode & S_IWUSR) {
        if ((fd = open( filename, O_RDWR)) < 0) {
            if (verbose)
                perror( diskname);
            return -1;
        }
        readonly = 0;
    } else {
        if ((fd = open( filename, O_RDONLY)) < 0 ) {
            if (verbose)
                perror( diskname);
            return -1;
        }
        readonly = 1;
    }

    lseek( fd, SECSIZE*2, SEEK_SET);

    if (read( fd, bloc, SECSIZE) != SECSIZE)
        return -1;

    nb_sectors = size / SECSIZE;

    if (nb_sectors * SECSIZE != size) {
        fprintf( stderr, "Disk size don't match an integer number of sectors: %u bytes left]\n",
                 size % SECSIZE);
        return -1;
    }

    if (verbose)
        printf( "Opening %s (%u sectors)\n", diskname, nb_sectors);

    // Not a flex disk ?
    if (getname( bloc + 0x10, label, 0) < 0 || bloc[0x26] == 0 || bloc[0x27] == 0) {
        fprintf( stderr, "Not a valid Flex disk image: ");
        return -1;
    }

    volnum = bloc[0x1b]*256 + bloc[0x1c];
    // Size of disk & free sector list
    nbtrk = bloc[0x26];
    nbsec = bloc[0x27];
    freesec = bloc[0x21]*256 + bloc[0x22];

    // Too much free sectors for the disk ?
    if (freesec > nbtrk * nbsec && verbose)
        printf( "Warning: Number of free sectors bigger than disk size\n");

    // Print info about the disk
    if (verbose)
        printf( "Flex Volume name: '%s', volume number %d (%d tracks, %d sectors/track)\n",
                label, volnum, nbtrk+1, nbsec);

    // Try to guess disk geometry
    if ((nbtrk+1) * nbsec == nb_sectors) {
        if (verbose) {
            printf( "Looks like a Single Density disk\n");
        }
        track0l = nbsec;
    } else {
        track0l = nb_sectors - nbtrk * nbsec;
        if ((nbsec >= 36 && track0l == 20) ||
            (nbsec == 18 && track0l == 10) ||
            (track0l == nbsec/2)) {
            if (verbose)
                printf ( "Looks like a Double Density disk with Single Density track 0 of %d sectors\n",
                         track0l);
        } else if (track0l > nbsec) {
            // Weird geometry... but can happen when disks are in EEPROM
            if (verbose)
                printf( "Unknown geometry: %d tracks of %d sectors + first track of %d sectors !\n",
                        nbtrk, nbsec, track0l);
            track0l = nbsec;
            nbtrk++;
            last_trk_sec = nb_sectors - (nbtrk-1) * nbsec - track0l;
            if (verbose)    
                printf( " => Using normal %d sector track 0, add a %d%s incomplete track of %d sectors\n",
                        track0l, nbtrk, "th", last_trk_sec);
        } else if (track0l > nbsec/2 && track0l < nbsec) {
            if(verbose)
                printf ( "Looks like a Double Density disk with Single Density track 0 of %d sectors\n",
                         track0l);
        } else {
            nbtrk -= (((nbtrk * nbsec - nb_sectors) / nbsec) + 1);
            // This is generaly no good, trying to guess end of track 0
            fprintf( stderr, "ERROR: Disk image too small... unusual geometry or truncated ?\n");
            return -1;
        }
    }
    ready = 1;
    return 0;
}

/**
 * Read command parameters from serial line until CR
 * 
 * Many NetPC protocol commands are followed by parameters (strings)
 * terminated by a carriage return (CR). This function reads these
 * parameters into the global param[] buffer.
 * 
 * @param none (uses global serial file handle)
 * @return none (stores result in global param[] buffer)
 * 
 * BUFFER MANAGEMENT:
 * - Reads up to 127 characters to prevent overflow
 * - Always null-terminates the result
 * - Silently truncates if input exceeds buffer size
 */
void getparam()
{
    int c, i;
    i = 0;
	
    while ((c = fgetc( serial)) != CR) {
        if (i<127)
            param[i++] = c;
        else
            param[i] = 0;
    }
    param[i] = 0;
}

/**
 * Calculate checksum for sector data transmission
 * 
 * The NetPC protocol uses a simple additive checksum to verify data
 * integrity during sector transfers. All 256 bytes of sector data
 * are summed and the result is sent as a 16-bit value (MSB, LSB).
 * 
 * @param data Pointer to 256-byte sector buffer
 * @return 16-bit checksum value (sum of all bytes)
 * 
 * CHECKSUM FORMAT:
 * - Transmitted as: [256 data bytes] [MSB] [LSB]
 * - MSB = (checksum >> 8) & 0xFF
 * - LSB = checksum & 0xFF
 */
int checksum( uint8_t *data)
{
    int j, chks;

    chks = 0;
    for (int i = 0; i < 256; i++)
        chks += (unsigned int) data[i];
    return chks & 0xFFFF;
}

/**
 * Handle 'S' (Send) command - read sector from disk and transmit to client
 * 
 * PROTOCOL SEQUENCE:
 * 1. Receive: [drive] [track] [sector]
 * 2. Read sector from disk image at calculated position
 * 3. Send: [256 data bytes] [checksum MSB] [checksum LSB]
 * 4. Receive: ACK (success) or NAK (retransmit request)
 * 
 * ERROR HANDLING:
 * - If no disk mounted: send zeros with bad checksum to force NAK
 * - If invalid track/sector: send zeros
 * - If read error: send zeros
 * 
 * DEBUGGING:
 * With verbose mode, prints read status and transmission result
 */
void sndblk()
{
    int drv, msb, lsb, chks;		// For checksum computing and transmitting
    int retval;
    int pos;
    uint8_t nsec, ntrk;

    drv = fgetc( serial);
    ntrk = fgetc( serial);
    nsec = fgetc( serial);
    retval = 1;

    if (ready == 0) {		// force checksum error if disk not ready
        if (verbose)
            printf( "No disk mounted, force CRC error!\n");
        for (int i = 0; i < 258; i++)
            fputc( 0, serial);
        fputc( 1, serial);
        if ((retval = fgetc( serial)) != NAK && verbose)
            printf ("... unexpected return value : 0x%02X\n", retval);
        return ;
    }

    if ((pos = SECSIZE * ts2blk( ntrk, nsec)) < 0) {
        retval = 0;
    } else {
        if (lseek( fd, pos, SEEK_SET) != pos)
            retval = 0;
        if (read( fd, bloc, SECSIZE) != SECSIZE)
            retval = 0;
    }
    if (retval == 0)
        for( int i = 0; i< 256; i++)
            bloc[i] = 0;
    if (verbose)
        if (retval) 
            printf( "Bloc dsk %d [0x%02X/0x%02X] (pos = %d) read", drv, ntrk, nsec, pos);
        else
            printf( "Fail to read bloc dsk %d [0x%02X/0x%02X] (pos = %d)", drv, ntrk, nsec, pos);

    chks = checksum( bloc);
    lsb = chks & 0xFF;
    msb = (chks >> 8) & 0xFF;
    for( int i = 0; i< 256; i++)
        fputc( bloc[i], serial);
    fputc( msb, serial);
    fputc( lsb, serial);

    retval = fgetc( serial);
    if (verbose)
        if (retval == NAK)
            printf( "... transmission failed\n");
        else if (retval == ACK)
            printf ("... transmission OK\n");
        else
            printf ("... return value not expected : 0x%02X\n", retval);
}

/**
 * Handle 'R' (Receive) command - receive sector from client and write to disk
 * 
 * PROTOCOL SEQUENCE:
 * 1. Receive: [drive] [track] [sector] [256 data bytes] [checksum MSB] [checksum LSB]
 * 2. Verify checksum of received data
 * 3. If checksum OK and valid position: write sector to disk
 * 4. Return: 1 for success (ACK will be sent), 0 for failure (NAK will be sent)
 * 
 * ERROR CONDITIONS:
 * - Checksum mismatch: data corruption during transmission
 * - Invalid track/sector: address out of range
 * - No disk ready: disk not mounted
 * - Write failure: disk I/O error
 * 
 * @return 1 on successful write, 0 on any error
 * 
 * DEBUGGING:
 * With verbose mode, displays checksum errors and hex dump of bad data
 */
int rcvblk()
{
    int msb, lsb, chks;		// For checksum computing and transmitting
    int retval;
    int pos;
    uint8_t nsec, ntrk;
    int drv, i;

    drv = fgetc( serial);
    ntrk = fgetc( serial);
    nsec = fgetc( serial);
    pos = SECSIZE * ts2blk( ntrk, nsec);

    for (i = 0; i <256; i++)
        bloc[i] = fgetc( serial);
    msb = fgetc( serial);
    lsb = fgetc( serial);
    retval = 1;

    if ((chks = checksum( bloc)) == msb * 256 + lsb) {
        if (pos < 0)
            retval = 0;
        else {
            if (ready == 0)
                return (retval = 0);
            if (lseek( fd, pos, SEEK_SET) != pos)
                retval = 0;
            if (write( fd, bloc, SECSIZE) != SECSIZE)
                retval = 0;
        }
    } else {
        retval = 0;
        if (verbose) {
            printf( "Bad checksum (0x%04X instead of 0x%04X)\n", msb * 256 + lsb, chks);
            for (i = 0; i< 256; i++)
                printf ("%c0x%02x", i%16?' ':'\n', bloc[i]);
        }
    }
    if (verbose)
        if (retval)
            printf( "Bloc [0x%02X/0x%02X] (pos = %d) written\n", ntrk, nsec, pos);
        else
            printf( "Fail to write bloc [0x%02X/0x%02X] (pos = %d)\n", ntrk, nsec, pos);
    return retval;
}

/**
 * Handle RCD (Remote Change Directory) command
 * 
 * Changes the server's current working directory. The new directory
 * path is read from the global param[] buffer (set by getparam()).
 * 
 * @return 1 on success (ACK will be sent), 0 on failure (NAK will be sent)
 * 
 * SIDE EFFECTS:
 * - Updates global curdir[] with new current directory
 * - Changes process working directory with chdir()
 * 
 * DEBUGGING:
 * With verbose mode, shows directory change attempts and results
 */
int chngd()
{
    int retval = 0;
    if (chdir( param) < 0) {
        retval = 0;
        if (verbose)
            printf( "Cannot change directory to %s\n", param);
    } else {
        getcwd( curdir, 255);
        retval = 1;
        if (verbose)
            printf( "Changing directory to %s\n", curdir);
    }
    return retval;
}

/**
 * Handle RMOUNT (Remote Mount) command
 * 
 * Unmounts the current disk image and attempts to mount a new one.
 * The disk name is read from param[] and ".DSK" extension is automatically
 * appended. If the uppercase version fails, tries lowercase ".dsk".
 * 
 * @return 1 on successful mount, 0 on failure
 * 
 * PROCESS:
 * 1. Close current disk image (if any)
 * 2. Try to load "param.DSK"
 * 3. If that fails, try "param.dsk"
 * 4. Update ready flag based on success
 * 
 * SIDE EFFECTS:
 * - Closes current disk image file descriptor
 * - Updates global disk variables if successful
 * - Sets ready flag appropriately
 */
int rmount()
{
    char filename[256];

    close( fd);
    if (verbose)
        printf( "closing %s\n", diskname);

    ready = 1;
    strncpy( filename, param, 255);
    strncat( filename, ".DSK", 255);	// Rmount don't put the extension
    if (load_dsk( filename) < 0) {
        if (verbose)
            printf( "trying with lowercase...\n");
        strncpy( filename, param, 255);
        strncat( filename, ".dsk", 255);
        if (load_dsk( filename) < 0)
            ready = 0;
    }
    return ready;
}

/**
 * Handle RDIR (Remote Directory) command - list .DSK files
 * 
 * Lists all .DSK files in current directory that match the given pattern.
 * The pattern is read via getparam() and used for filename filtering.
 * 
 * PROTOCOL SEQUENCE:
 * 1. Send CR LF (start of listing)
 * 2. For each matching file:
 *    - Wait for ' ' (space) from client (ready for next entry)
 *    - Send filename + CR LF
 * 3. Client sends final ' ' when done receiving
 * 4. Send ACK to complete command
 * 
 * FILTERING:
 * - Only files ending in ".DSK" (case insensitive)
 * - Only files starting with the parameter string
 * 
 * EARLY TERMINATION:
 * Client can send ESC instead of ' ' to abort listing
 */
int lstdsk()
{
    struct dirent *entry;
    DIR *dirp;
    int reply;
    int endlist;

    getparam();
	
    if (verbose)
        printf( "RDIR( %s) command\n", param);
				
    fputc( CR, serial);
    fputc( LF, serial);

    dirp = opendir( curdir);
    endlist = 1;
    while ((entry = readdir( dirp)) != NULL) {
        if (strcasecmp( (entry->d_name)+strlen(entry->d_name)-3, "DSK") != 0) 
            continue;
        if (strcasestr( entry->d_name, param) != entry->d_name)
            continue;
        if ((reply = fgetc( serial)) != ' ') {
            if (verbose && reply != ESC)
                printf( "Unexpected command (0x%02X) while reading directory\n", reply);
            endlist = 0;
            break;
        }
        if (verbose)
            printf( "---> %s\n", entry->d_name);
        fputs( entry->d_name, serial);
        fputc( CR, serial);
        fputc( LF, serial);
    }
    if (endlist)
        if ((reply = fgetc( serial)) != ' ')
            if (verbose)
                printf( "Unexpected command (0x%02X) while reading directory\n", reply);

    closedir( dirp);
    fputc( ACK, serial);
}

/**
 * Handle RLIST (Remote List) command - list subdirectories
 * 
 * Lists all subdirectories in the current directory. This allows
 * the Flex client to navigate the Unix directory structure.
 * 
 * PROTOCOL SEQUENCE:
 * 1. Read parameter (usually empty for full listing)
 * 2. Wait for 0x20 (space) from client
 * 3. Send CR LF (start of listing)
 * 4. For each directory (excluding . and ..):
 *    - Wait for 0x20 from client (ready signal)
 *    - Send directory name + CR LF
 * 5. Send ACK to complete
 * 
 * FILTERING:
 * - Only directories (not regular files)
 * - Excludes "." and ".." entries
 * - Uses stat() to verify directory status
 * 
 * ERROR HANDLING:
 * - Skips entries that can't be stat()'ed
 * - Handles early termination via ESC
 */
int lstdir()
{
    struct dirent *entry;
    struct stat statbuf;
    DIR *dirp;
    int reply;
    int endlist;

    if (verbose)
        printf( "RLIST command\n");
				
    getparam();
    if ((reply = fgetc( serial)) != 0x20)
        printf( "Bad char 0x%02X received...\n", reply);
    else {
        fputc( CR, serial);
        fputc( LF, serial);
    }

    endlist = 1;
    dirp = opendir( curdir);
    while ((entry = readdir( dirp)) != NULL) {
        if (strcmp(entry->d_name, ".") * strcmp(entry->d_name, "..") == 0)
            continue;
        if (stat( entry->d_name, &statbuf) == -1) {
            if (verbose)
                perror( entry->d_name);
            continue;
        }
        if (S_ISDIR( statbuf.st_mode) == 0) 
            continue;
        if ((reply = fgetc( serial)) != 0x20) {
            if (verbose && reply != ESC)
                printf( "Unexpected command (0x%02X) while reading directory\n", reply);
            endlist = 0;
            break;
        }
        if (verbose)
            printf( "---> %s\n", entry->d_name);
        fputs( entry->d_name, serial);
        fputc( CR, serial);
        fputc( LF, serial);
    }
    if (endlist)
        if ((reply = fgetc( serial)) != ' ')
            if (verbose)
                printf( "Unexpected command (0x%02X) while reading directory\n", reply);
    closedir( dirp);
    fputc( ACK, serial);
}

/**
 * Main program - NetPC server for Flex systems
 * 
 * COMMAND LINE OPTIONS:
 * -d <device>  : Serial device path (required)
 * -s <speed>   : Baud rate (required)
 * -v           : Verbose debug output
 * -h           : Show help and exit
 * 
 * PROGRAM FLOW:
 * 1. Parse command line arguments
 * 2. Open and configure serial port
 * 3. Load initial disk image
 * 4. Enter main command processing loop
 * 
 * COMMAND PROCESSING LOOP:
 * The server runs in an infinite loop, reading commands from the serial
 * port and dispatching them to appropriate handler functions:
 * 
 * - 0x55/0xAA: Synchronization (echo back)
 * - S/s: Send sector (sndblk)
 * - R/r: Receive sector (rcvblk -> ACK/NAK)
 * - V: Query/change drive (compatibility, ACK only)
 * - ?: Query current directory
 * - Q: Quick drive ready check (always ACK)
 * - A: List .DSK files (lstdsk)
 * - I: List directories (lstdir)
 * - C: Create disk (not implemented, NAK)
 * - D: Delete disk (not implemented, NAK)
 * - E: Exit server
 * - P: Change directory (chngd -> ACK/NAK)
 * - M: Mount disk (rmount -> ACK+mode or NAK)
 * 
 * @param argc Command line argument count
 * @param argv Command line argument array
 * @return 0 on normal exit, 1 on error
 */
int main(int argc, char **argv)
{
    int opt;
    char *name;
    struct stat dsk_stat;
    int command;
    int flags;
    struct termios linespec;
    int idlnk;

    // Read parameters
    while ((opt = getopt( argc, argv, "d:s:vh")) != -1) {
        switch (opt) {
        case 'h':
            usage( *argv);
            exit( 0);
            break;
        case 'v':
            verbose = 1;
            break;
        case 'd':
            strncpy( line, optarg, 31) ;
            break;
        case 's':
            sscanf( optarg, "%d", &speed);
            break;
        default: /* unknown commands */
            usage( *argv);
            exit( 1);
        }
    }

    // Some sanitary checking on options
    if (strlen( line) == 0) {
        fprintf( stderr, "No serial line ?\n");
        usage( *argv);
        exit( 1);
    }

    if (speed == 0) {
        fprintf( stderr, "No baudrate ?\n");
        usage( *argv);
        exit( 1);
    }

    if((serial = fopen( line, "r+")) == NULL )
        perror( line);

    if ((idlnk = fileno( serial)) < 0)
        perror( line);

    if (tcgetattr (idlnk, &linespec) < 0) {
        perror ("ERROR getting current terminal's attributes");
        exit( 1);
    }
    cfmakeraw( &linespec);
    cfsetspeed( &linespec, speed);
		
    if (tcsetattr (idlnk, TCSANOW, &linespec) < 0) {
        perror ("ERROR setting current terminal's attributes");
        exit( 1);
    }

    if (verbose)
        printf( "Link on %s, speed is %d bauds\n", line, speed);

    if (optind < argc) {
        name = argv[ optind++];
        if (optind < argc) {
            fprintf( stderr, "Only one filename is allowed\n");
            usage( *argv);
            exit (1);
        }
    } else {
        fprintf( stderr, "No file name ???\n");
        usage( *argv);
        exit( 1);
    }

    // Load the file


    getcwd( curdir, 255);

    if (load_dsk( name) < 0)
        exit( 1);

    if (readonly) {
        fprintf( stderr, "Flexnet can't start with a read-only file\n");
        exit( 1);
    }

    /* Main Command Processing Loop */
    /* 
     * The server continuously reads commands from the Flex client and
     * responds according to the NetPC protocol specification.
     */
    while (1) {
        command = fgetc( serial);   // Read next command byte
        *param = 0;                 // Clear parameter buffer
        
        switch (command) {
        /* Synchronization Commands */
        case 0x55:  // Sync pattern 1
        case 0xAA:  // Sync pattern 2 (or RESYNC)
            fputc( command, serial);    // Echo back for synchronization
            if (verbose)
                printf( "Initial sync or RESYNC command ($%02x)\n", command);
            break;
            
        /* Sector I/O Commands */
        case 'S':   // Send sector to client (read from disk)
        case 's':   // FLEXNET uses lowercase variant
            sndblk();
            break;
        case 'R':   // Receive sector from client (write to disk)
        case 'r':   // FLEXNET uses lowercase variant
            fputc(rcvblk()?ACK:NAK, serial);    // Send ACK on success, NAK on error
            break;
        /* Drive Management Commands */
        case 'V':   // Query/change MS-DOS drive letter (ignored on Unix)
            getparam();             // Read parameter but ignore it
            fputc( ACK, serial);    // Always acknowledge
            if (verbose)
                printf( "Query (change) drive command\n");
            break;
            
        case '?':   // Query current directory
            fputs( curdir, serial); // Send current directory path
            fputc( CR, serial);     // Terminate with CR
            fputc( ACK, serial);
            if (verbose)
                printf( "Query current directory (%s) command\n", curdir);
            break;
            
        case 'Q':   // Quick drive ready check
            fputc( ACK, serial);    // Unix files are always "ready"
            if (verbose)
                printf( "Quick check: is drive ready ? (unix: always yes)\n");
            break;
            
        /* Directory Listing Commands */
        case 'A':   // List .DSK files (RDIR command)
            lstdsk();
            break;
            
        case 'I':   // List subdirectories (RLIST command)
            lstdir();
            break;
        /* File Management Commands (Not Implemented) */
        case 'C':   // Create .DSK file (RCREATE command)
            getparam(); // Read disk name
            getparam(); // Read track count
            getparam(); // Read sector count
            getparam(); // Read additional parameters
            // Fall through to 'D' case
        case 'D':   // Delete .DSK file (RDELETE command)
            getparam(); // Read filename parameter
            fputc( NAK, serial);    // Not implemented - return error
            if (verbose)
                printf( "%s(%s) command (not implemented, reply NAK)\n",
                        command=='C'?"RCREATE":"RDELETE", param);
            break;
            
        /* Session Management Commands */
        case 'E':   // Exit/disconnect (REXIT command)
            fputc (ACK, serial);    // Acknowledge shutdown
            if (verbose)
                printf( "Flexnet exit\n");
            exit( 0);   // Terminate server
            
        case 'P':   // Change directory (RCD command)
            getparam(); // Read new directory path
            fputc (chngd()?ACK:NAK, serial);    // ACK on success, NAK on error
            break;
            
        case 'M':   // Mount disk image (RMOUNT command)
            getparam(); // Read disk image filename
            if (rmount()) {
                fputc( ACK, serial);                        // Success
                fputc( readonly?'R':'W', serial);          // Send read/write status
            } else {
                fputc( NAK, serial);                        // Mount failed
            }
            break;
            
        /* Error Conditions */
        case -1:    // EOF on serial port (connection lost)
            fprintf( stderr, "Serial line disappeared - Panic exit\n");
            exit( 1);
            
        default:    // Unknown command - ignore and continue
            if (verbose)
                printf( "Unknown command 0x%02x (%c)\n", command, 
                       isprint( command) ? command : '?');
            break;
        }
    }
}
