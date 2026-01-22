*        NAM     REXIT
*
* "RemoteEXIT" command does the following:
*
* - Exit NETPC which is running on the PC
* - Reset the Flex disk driver vectors to their
*   original values
* - Clear (i.e. fill with zeroes) the space used
*   by the NETDRV drivers
* - Reset MEMEND to recover the free memory space,
*   but do so ONLY if the NETDRV code was located
*   immediately above MEMEND.
*
*
*       01.01   2002-11-29 js Initial version
*       01.02   2024-07-31 Wrede SBC6803
* ---------------------------------------------------------------

* FLEX ROUTINES EQUATES
*
TTYLBP  EQU $AC14 ;LINE BUFFER POINTER
TTYEOL  EQU $AC02 ;EOL CHARACTER LOCATION

INCHNE  EQU $B3E5 ;INPUT_NO_ECHO VECTOR
MEMEND  EQU $AC2B ;MEMORY END POINTER
PSTRNG  EQU $AD1E
PUTCHR  EQU $AD18
NXTCH   EQU $AD27
OUTDEC  EQU $AD39
GETHEX  EQU $AD42
GETCHR  EQU $AD15
PCRLF   EQU $AD24
INBUF   EQU $AD1B
CLASS   EQU $AD21
GETFIL  EQU $AD2D
INDEC   EQU $AD48
FMS     EQU $B406
FMSCLS  EQU $B403
WARMS   EQU $AD03
*
* ASCII STUFF
CR      EQU $0D
LF      EQU $0A
ACK     EQU $06
NACK    EQU $15
ESC     EQU $1B
BS      EQU 8

        ORG     $A100
        BRA     search

* VERSION NUMBER

VN      FCB     1,2

* TEMP STORAGE

base    RMB     2         ; start of signature string
size    RMB     2         ;  size of driver code
XTEMP09 RMB     2
YTEMP09 RMB     2
BTEMP09 RMB     1

* Serial input/output vectors
* The following 2 JMPs are initialized
* with the addresses of the serial in/out
* vectors which are at the start of NETDRV
* The default (WARMS) is a dummy value

schar   JMP     WARMS
rchar   JMP     WARMS

memend  equ     $AC2B           ; FLEX end of user RAM
*

*-----------------------------------------
* Step 0: Check for Netpc drivers in memory; if
*         they are not loaded, just exit.
*
*
* Scan if a copy of FLEXNet is already loaded
* search "netU"
*
search  LDX #$8015             ; FLEXNET driver here
        LDAA #"n"
        CMPA 0,X
        BNE sear4               ; no match
        LDAA #"e"
        CMPA 1,X
        BNE sear4
        LDAA #"t"
        CMPA 2,X
        BNE sear4
        LDAA #"U"
        CMPA 3,X
        BNE sear4               ; no match finally
        BRA foundit
sear4   JMP noload
*
* Signature string was found, all is OK
* Proceed with utility!

*--------------------------------------
*
* Step 1: Store start and end pointers
*

* Store drivers start address
foundit STX     XTEMP09
*        LDD     XTEMP09
*        tfr     x,d
*        subd    #21            ; point to start of code
        LDD     #$8000         ; base is fix here !
        std     base           ; store pointer

* Set the address of the in/out vectors
        LDX     #$801D         ; points to JMP of netdriver
        STX     schar+1        ; update JMP warms to real pointer
        LDX     #$8020
        STX     rchar+1

* Read size of drivers and store it

        ldd     $803D         ; drvend info in NET driver
        ANDA    #$7F          ; through away MSbit to get number of bytes !
        std     size

*----------------------------------
*
* Step 2: Send the "Exit" command

        LDAA    #"E"
        JSR     schar         ;  send command
        BCC     NOWORK        ;  exit if time-out

* WAIT FOR ACK

WTACK   JSR     rchar         ;  Receive character
        BCC     NOWORK        ;  exit if time-out
        CMPA    #ACK          ;  "ack" received?
        BNE     WTACK         ;  No, try again

*----------------------------------
*
* Step 3: Restore the original Flex
*         disk driver vectors

clear   ldab    #21            ; Restore 7 vectors
        ldx     base           ; "from"     pointer
        STX     XTEMP09
        LDX     #$BE80         ; "to"     pointer
        STX     YTEMP09
* restore loop

relp    LDX     XTEMP09
        ldaa    0,X            ;read from Net drivers
        INX
        STX     XTEMP09        ; do X+
        LDX     YTEMP09
        staa    0,X            ; Store in Flex area
        INX
        STX     YTEMP09        ; do Y+
        decb
        bne     relp           ; loop until done


*---------------------------------
*
* Step 4: Fill driver space with zeroes
*

        ldx     base           ; Point to base address
        ldd     size           ; Number of bytes to clear
fill    clr     0,X            ; clear one byte
        INX
        subd    #1             ; count down
        bne     fill           ; loop until done

*----------------------------------
*
* Step 5: No MEMEMD adjust here
*
        bra     EXITOK          ; No, exit without restoring MEMEND

*------------------------------------
* Message and exit routines

noload  ldx     #nodrv          ; Inform that drivers are not loaded
        bra     finish

EXITOK  ldx     #exitst         ; Report exit from program
        bra     finish

NOWORK  LDX     #TIMOUT         ; Report time-out error

finish  JSR     PSTRNG
EXIT2   JMP     WARMS


* CHARACTER STRINGS

TIMOUT  FCC     "Communication time-out error"
        FCB      4
nodrv   FCC     "NETDRV is not loaded in memory, no action taken."
        FCB      4
exitst  fcc     "Program Exit"
        FCB      4

 END    ; start at $A100
