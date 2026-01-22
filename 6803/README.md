# Flexnet 6803

# Notes

## Martin

I also started to implement the Flexnet in my 6803 FLEX2 system.
As far as I understood up to now:

loading the Flexnet driver with the FLEXDRV.CMD, the command first copies the netdriver
to the end of the memory range of  FLEX ($7xxx or so), changes the memory end
pointer in FLEX and then overwrites the jumping table for the driver routines,
so that the sector read, write, and check routines first points to the new
installed netdriver. In case of disc access the flexnet driver decides, whether
the device is a net device and takes the action or jumps again to the normal
flex driver.

I started to recode the 6809 to the 6803 machine.

The only 6803 commands I use, which are not 6800 compatible, are
STD, ABX and PUSHX, which could be replaced by 6800 commands.
For the other 6809 specific register I implement memory registers
like TEMPY or TEMPU which are then emulated with additional coding with the 6800
X-register. That works normally fine. I have done that already for the
8K BASIC (BASIC30.asm) , where the source code is only available for 6809. It is now
running on my 6803 system.

Beside that I replace in the FLEXNET code the smart coding for looking
whether the netdriver is already loaded. I replaced it with a short not so smart
easier code, to get results and fun earlier.

The netdriver itself is not placed at the end of the FLEX memory but
in a unused memory range, here $8000. That, of course is not compatible
with a SWTPC machine. But you can place it anywhere.
I use 2 interfaces:

1. ACIA at $D010
2. ACIA internal in 6803 running at 9600 Baud, used for netdrv

I am not sure, whether you find anything useful in my code, but may be.
best regards, Martin 

## Frederic

The PT68-1 has plenty of RAM you can load drivers in that is not available on the SWTPC.

The place where you won't conflict with any possible uses by other programs is RAM at F000-FFF7.

There are other places, such are RAM at the top of IO.  8040-8FFF.  This is generally a safe place to put drivers since the SWTPC can't have RAM in this address range and you won't have a conflict with other programs.

# Files:

| FNET03A.asm | |
| FNET03A.TXT | |
| NET_Betrieb_1.JPG | |
| RCD.asm | |
| RCD.TXT | |
| RDIR.asm | |
| RDIR.TXT | |
| RDRIVE.asm | |
| RDRIVE.TXT | |
| RESYNC.asm | |
| RESYNC.TXT | |
| REXIT.asm | |
| REXIT.TXT | |
| RLIST.asm | |
| RLIST.TXT | |
| RMOUNT.asm | |
| RMOUNT.TXT | |

# Credits

- Martin Wrede
