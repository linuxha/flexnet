*   File name   FNET03.txt
*
*   This is a driver package which implements
*   a remote mounted ".DSK file drive" over a serial line.
*
*** If the remote end is running on a slow machine, you might have
*   to remove the "***" comments, which will activate some delays
*   and "hand shaking". There is also a constant in the "delay"
*   routine, that can be changed for fine tuning. "As is," (with
*   the "***" comments removed) the constants have been tuned to
*   run with a 40 MHz 386 PC as the host computer.
*
*   Also, the "odelc" constant might have to be increased, if the
*   remote end has a slow HD. Otherwise, a time-out error might
*   occur during file pointer positioning.
*
*
*   vn  01.00   2000-09-15, BjB
*       01.01   2000-09-19, BjB:    fixing typos and omissions
*       02.00   2000-09-24, BjB:    time-out if comm link is broken
*       02.01   2000-09-24, BjB:    fixed verify
*       02.03   2000-09-30, BjB:    options for "fast/slow PC"
*       03.00   2002-05-01, js      Add jump vectors for rchar/schar
*       03.01   2002-08-30, js      Add string search routine to
*                                   avoid duplicate loads
*       03.02   2002-09-19, JS      Add ACIA reset vector and move all
*                                   vectors after signature
*       03.03   2002-11-23, js      Add the "remember drive letter" function
*                                   and longer delay for floppies
*       03.04   2002-11-29  js      Add a few pointers for uninstall
*       03.05   2024-07-31  Wrede   convert to SBC6803 FLEX2 system
*                                   carry set/unset in driver logic
*                                   default delay to $FFFF
* ---------------------------------------------------------------
*
        org     $8000


* The following lines should all stay together: jump table,
* signature, vectors, and a few pointers. The Rxxx.CMD utilities
* expect them to keep the same relative position, so if they
* are moved they MUST be moved together as one single block.
*
*  ACIA is SER2 for FLEXNET
*
*   FLEX disk driver jump table 
*
fread   rmb     3               ;read single sector
fwrite  rmb     3               ;write single sector
fverfy  rmb     3               ;verify write operation
frestr  rmb     3               ;restore head to track# 00
fdrive  rmb     3               ;drive selection
fcheck  rmb     3               ;check ready
fquick  rmb     3               ;quick check ready

* signature string

sgnst   fcc     'netUUdrv'
len     equ     *-sgnst
* orig LBRA
        JMP    schar          ;vector for send character
        JMP    rchar          ;vector for receive character
        JMP    reset          ;vector for ACIA reset

        fcc     'FLEXNet 4.1.1'

drvltr  rmb     4               ;MS-DOS drive letter
netdrv  fcb     -1              ;Flex drive selected as DOS drive
        fcb     -1              ;-1 means no drive mapped
        fcb     -1
        fcb     -1

qcheck  fcb     0               ;0 = do not do Quick Check before reading and writing sectors
*                               ;1 = do Quick Check before reading and writing sectors
slowpc  fcb     1               ;0 = not slow PC
*                               ;1 = Slow PC

size    fdb     drvend          ;Size of drivers

* End of "block"

*
*   Local variables
*
curdrv  rmb     1               ;current drive from fcb
curtrk  rmb     2               ;current ttss#
chksum  rmb     2               ;checksum
cnt     rmb     1               ;div counter
lstdrv  rmb     1               ;latest drive# selected
delcnt  rmb     1               ;inner time-out delay counter
*                               ;(default is drive 3)
odelc   rmb     2               ;max delay
*
*  simulate 6809 with these registers
*
*             lines with  !!! must be checked
*
XTEMP09  RMB 2
BTEMP09  RMB 1
*
*   Read one sector from 'net drive'
*
nread   PSHX
        PSHA                   ; save X,A on stack
        PSHB                   ; save B on stack
*        ldaa     -64+3,X         ;get requested drive#  OFFSET ?  !!!
        LDAA    3,X             ; check index !!!
        staa    curdrv          ; extended address
        LDX     #netdrv         ; get address of netdrv table
        TAB
        ABX                     ; add offset of drive
*        
        cmpa    0,X             ;same as assigned 'net drive'#?
        PULB
        PULA
        PULX                    ; restore A,B,X
        bne     fread           ;no, do FLEX read routine
        PSHX
        std     curtrk          ;save current ttss#
        clr     chksum          ;clear checksum
        clr     chksum+1
        clr     cnt             ;256 bytes to read
*
*   Q(uick) Check that remote drive is ready
*
        ldaa    qcheck
        beq     nqchk1
        ldaa     #"Q"            ;Send Q command
        JSR     schar
        BCC     nrea10          ;"Drive not ready" time out
        JSR     rchar           ;get response
        BCC     nrea10          ;time out
        cmpa    #ack            ;got an ack?
        BNE     nrea10          ;nope, report error

        LDAA    slowpc
        beq     nqchk1

        JSR     delay           ;for "slow PC" ***

nqchk1  ldaa    #"s"            ;Send sector command
        JSR     schar
        bcc     nrea10          ;";Drive not ready"

        LDAA    slowpc
        beq     ntslw1
        JSR     delay           ;for "slow PC" ***
ntslw1  ldaa    curdrv          ;drive number
        JSR     schar
        bcc     nrea10
        ldaa    curtrk          ;tt#
        JSR     schar
        bcc     nrea10
        ldaa    curtrk+1        ;ss#
        JSR     schar
        bcc     nrea10
nrea04  JSR     rchar           ;read one byte
        bcc     nrea10
        staa    0,X             ;store in FCB and move pointer
        INX
        adda    chksum+1        ;update checksum lsb
        staa    chksum+1
        bcc     nrea08          ;bra if no carry
        inc     chksum          ;update checksum msb
nrea08  dec     cnt             ;decrease byte count
        bne     nrea04          ;loop till 0

        JSR     rchar           ;get checksum msb
        bcc     nrea10
        PSHA                    ;save for now
        JSR     rchar           ;get checksum lsb
        TAB
        PULA                    ;restore msb
        bcc     nrea10          ;time out?

        CMPA   chksum          ; compare MSB
        BNE    nrea12
        CMPB   chksum+1        ; compare LSB
*        
        bne     nrea12          ;bra if checksum err

        ldaa    #ack            ;send ack char
        JSR     schar
        bcc     nrea10
        clrb                    ;report okay
        bra     nrea16

nrea10  ldab    #16             ;report Drive not ready
        bra     nrea16

nrea12  ldaa    #nak            ;send nak char
        JSR     schar
        bcc     nrea10
        ldab    #09             ;report read error (CRC)

nrea16  stab    chksum          ;for later test
        tstb                    ;for FLEX error check
        PULX                    ;restore FCB pointer
        rts
*
*   Write one sector to 'net drive'
*
* code adaption 6803 same as read code
*
*
*   JUMP TABLE long branches
*
Mfwrite  JMP fwrite
*
nwrite  PSHX
        PSHA
        PSHB
*        ldaa    -64+3,X         ;get requested drive# OFFSET ? !!!
        LDAA    3,X             ; check index !!!
        staa    curdrv
        staa    lstdrv          ;last drive written to
        LDX     #netdrv
        TAB
        ABX
        cmpa    0,X             ;same as assigned 'net drive'#?
        PULB
        PULA
        PULX
        bne     Mfwrite         ;no, do FLEX write routine
        PSHX                    ;save FCB pointer
        std     curtrk          ;save current ttss#
        clr     chksum          ;clear checksum
        clr     chksum+1
        clr     cnt             ;256 bytes to send
*
*   Q(uick) Check that remote drive is ready
*
        ldaa    qcheck
        beq     nqchk2

        ldaa     #"Q"           ;Send Q command
        JSR     schar
        BCC     nwri10          ;"Drive not ready" time out
        JSR     rchar           ;get response
        BCC     nwri10          ;time out
        cmpa    #ack            ;got an ack?
        bne     nwri10          ;nope, report error
        ldaa    slowpc
        beq     nqchk2
        JSR     delay           ;for "slow PC" ***
nqchk2  ldaa    #"r"            ;Receive sector command
        JSR     schar
        bcc     nwri10          ;"Drive not ready"

        ldaa    slowpc
        beq     ntslw2

        JSR     delay           ;for "slow PC" ***
ntslw2  ldaa    curdrv          ;drive number
        JSR     schar
        bcc     nwri10
        ldaa    curtrk          ;tt#
        JSR     schar
        bcc     nwri10
        ldaa    curtrk+1        ;ss#
        JSR     schar
        bcc     nwri10
        ldaa    slowpc
        beq     nwri04
        JSR     delay           ;for "slow PC" ***
nwri04  ldaa    0,x             ;get byte from FCB and move pointer
        INX
        JSR     schar
        bcc     nwri10
        adda    chksum+1        ;update checksum lsb
        staa    chksum+1
        bcc     nwri08          ;bra if no carry
        inc     chksum          ;update checksum msb
nwri08  dec     cnt             ;decrease byte count
        bne     nwri04
        ldaa    chksum          ;send checksum msb
        JSR     schar
        bcc     nwri10
        ldaa    chksum+1        ;send checksum lsb
        JSR     schar
        bcc     nwri10
        JSR     rchar           ;get response
        bcc     nwri10
        cmpa    #ack
        bne     nwri12          ;bra if not ack
        clrb                    ;report okay
        bra     nwri16

nwri10  ldab    #16             ;report Drive not ready
        bra     nwri16
nwri12  ldab    #10             ;disk file write error

nwri16  stab    chksum          ;for later check
        tstb                    ;for FLEX error check
        PULX                    ;restore FCB pointer
        rts
*
*   JUMP TABLE long branches
*
Mfverfy  JMP fverfy
Mfrestr  JMP frestr
Mfdrive  JMP fdrive
*
*
*   Verify last sector written
*
nverfy  ldaa    lstdrv          ;was last drive# = new drive#?
        PSHX
        PSHB
        LDX     #netdrv
        TAB
        ABX
        cmpa    0,X             ;same as assigned 'net drive'#?
*       cmpa    netdrv,pcr
        PULB
        PULX
        BNE     Mfverfy         ;no, do FLEX verify routine

        ldab    chksum          ;get latest checksum test result
        tstb
        rts
*
*   Restore to track# 00
*
nrestr  lda     3,x             ;get requested drive#
        PSHX
        PSHB
        LDX     #netdrv
        TAB
        ABX
        cmpa    0,X             ;same as assigned 'net drive'#?

*       cmpa    netdrv,pcr      ;same as assigned 'net drive'#?

        PULB
        PULX
        BNE     Mfrestr         ;no, do FLEX restore routine
        clrb                    ;nothing to do with 'net drive'
        rts
*
*   Drive select
*
ndrsel  lda     3,x             ;get requested drive#
        PSHX
        PSHB
        LDX     #netdrv
        TAB
        ABX
        cmpa    0,x             ;same as assigned 'net drive'#?
*       cmpa    netdrv,pcr      ;same as assigned 'net drive'#?
        PULB
        PULX
        BNE     Mfdrive         ;no, do FLEX drive select routine

        clrb                    ;nothing to do with 'netdrv'
        rts
*
*   Check drive ready
*
ncheck  lda     3,x             ;get requested drive#
        PSHX
        PSHB
        LDX     #netdrv
        TAB
        ABX
        cmpa    0,x             ;same as assigned 'net drive'#?
*       cmpa    netdrv,pcr      ;same as assigned for 'net drive'#?
        PULB
        PULX
        BNE     Mfcheck          ;no, do FLEX check drive ready routine
        bra     nqui04          ;common for Check & Quick Check
*
*   Quick check drive ready
*
nquick  lda     3,x             ;get requested drive#
        PSHX
        PSHB
        LDX     #netdrv
        TAB
        ABX
        cmpa    0,x             ;same as assigned 'net drive'#?
*       cmpa    netdrv,pcr      ;same as assigned for 'net drive'#?
        PULB
        PULX
        BNE     Mfquick         ;no, do FLEX Quick Check routine
nqui04  ldaa    #"Q"            ;quick check command
        JSR     schar
        bcc     nqui08
        bsr     rchar           ;get response
        bcc     nqui08
        cmpa    #ack
        bne     nqui08          ;not ready
        clrb                    ;report drive ready
        bra     nqui12
nqui08  ldab    #16             ;report drive not ready
        sec
nqui12  tstb
        rts
*
* Long jump branch
Mfquick  JMP fquick
Mfcheck  JMP fcheck
*
*   Receive character.
*   Returns with character in ACCA and CC set if successful,
*                           CC cleared if time-out occurred.
*
*  6803 we use X register !  Set Carry if read/write success
*
rchar   PSHX
        bsr     dlyset          ;go set delay
        ldx     odelc           ;outer delay counter
        clr     delcnt          ;inner delay counter
rcha04  ldab    ACIAC1          ;check if char received
        ANDB    #$80
        bne     rcha08          ;get character
        dec     delcnt          ;decrement inner delay counter
        bne     rcha04          ;continue if not = 0
        DEX                     ;decrement outer delay counter
        bne     rcha04          ;continue if not = 0
        bra     rcha12          ;return with CC cleared
rcha08  ldaa    ACIADR          ;read char
        SEC                     ; set carry , all o.k.
rcha12  PULX
        RTS
*
*   Send character.
*   Returns with CC set if successful,
*                CC cleared if time-out occurred.
*
schar   PSHX
        bsr     dlyset          ;go set proper delay
        ldx     odelc           ;outer delay counter
        clr     delcnt          ;inner delay counter
scha04  ldab    ACIAC1          ;check if tdr is empty
        ANDB    #$20
        bne     scha08          ; transmit end OK, send char
        dec     delcnt          ;decrement inner delay counter
        bne     scha04          ;continue if not = 0
        DEX                     ;decrement outer delay counter
        bne     scha04          ;continue if not = 0
        bra     scha12          ;return with CC cleared
scha08  staa    ACIADT          ;send char
        SEC                     ; set carry, all o.k.
scha12  PULX
        RTS
*
*   Delay routine (for "slow PC")
*
delay   clrb
        STAB    BTEMP09
        ldab     #50             ;change if needed
dela04  DEC     BTEMP09
        bne     dela04
        decb
        bne     dela04
        RTS
*
*  ACIA reset routine SER2 on SBC6803
*
reset   ldaa     #$05            ;ACIA master reset
        staa     ACIAS
        ldaa     #$0A            ;8 bits,9600B enable T and R
        staa     ACIAC1
        rts
*
*  Delay set routine
*  Sets the content of "odelc" as a function of
*  the drive type; destroys y and b
*
dlyset  STX     XTEMP09
*        ldx     #100            ;default value 
        ldx     #$FFFF   ; with this value is does the job, room for optimize
        ldab    drvltr          ;get drive letter
        cmpb    #$40            ;is it floppy?
        bne     dlexit          ;no, don't change
        ldx     #65535          ;select longer delay
dlexit  stx     odelc
        LDX     XTEMP09
        rts
drvend  equ     *               ;end of driver package
*
* ---------------------------------------------------------------
*
*   FLEX equates
*
warms   equ     $AD03           ;FLEX warm start
pstrng  equ     $AD1E           ;write string to display
pcrlf   equ     $AD24           ;write cr/lf to display
putchr  equ     $AD18           ;write character to display
gethex  equ     $AD42           ;get hex number
*
memend  equ     $AC2b           ;FLEX end of user RAM
drvtbl  equ     $BE00           ;start of FLEX driver jump table
*
*   Misc equates
*
ack     equ     $06             ;acknowledge character
nak     equ     $15             ;negative acknowledge

tmp     equ     lstdrv          ;re-use for temp storage
tries   equ     cnt             ;re-use for number of tries
*
* ---------------------------------------------------------------
*
*   The following code will be dropped after a successful
*   line synchronization and relocation of the driver routines.
*
* ---------------------------------------------------------------
*
        org     $A100
start   bra     init
versn   fcb     4,1             ;version number
*
*   New jump address table   copied to net driver section
*
newtbl  fdb     nread           ;read single sector
        fdb     nwrite          ;write single sector
        fdb     nverfy          ;verify write operation
        fdb     nrestr          ;restore head to track# 00
        fdb     ndrsel          ;drive select
        fdb     ncheck          ;check drive ready
        fdb     nquick          ;quick check drive ready

*---------------------------------------------------------
*
*   Start of installer program init NET jump table
*                              copy from original table
*
*---------------------------------------------------------
*
* Display greeting message and version number
*
init    ldx     #greet          ;point to string
        ldd     versn           ;get version number
        addd    #$3030          ;make ASCII
        staa    v1
        stab    v1+2
        jsr     pstrng          ;go print string
*
* Scan if a copy of FLEXNet is already loaded
* search "netU"
*
        
search  LDX #sgnst
        LDAA #"n"
        CMPA 0,X
        BNE error1               ; no match
        LDAA #"e"
        CMPA 1,X
        BNE error1
        LDAA #"t"
        CMPA 2,X
        BNE error1
        LDAA #"U"
        CMPA 3,X
        BNE error1               ; no match finally
        BRA sear4                ; drive code found go copy action
*
* string not found,  tell user
*
error1  ldx     #drvsig         ;drv code not found...
        bra     sync17          ;display then exit
*
* Search done and match found;
* initialize FLEXNet tables and go!
*
sear4   equ     *
* Get drive number from user
        jsr     gethex          ;get hex number
        bcs     nonum           ;skip if not valid
        tstb
        beq     nonum           
        STX     XTEMP09         ;transfer number to d  
        LDD     XTEMP09
        andb    #$03            ;limit to 3
        PSHX
        LDX     #netdrv
        ABX                     ; add drive
        stab    0,X             ;store in target drive #
*       stab    netdrv          ;store in target drive #
        PULX
        bra     sear4           ;allow multiple drives
nonum equ *
*
*   Initialize ACIA.
*
* Adaptation SBC6803 system:
*
ACIAS   equ $0010  ; ACIA first control register
ACIAC1  equ $0011  ; ACIA second control register
ACIADR  equ $0012  ; ACIA data register receive
ACIADT  equ $0013  ; ACIA data register transfer
*
*   ACIA on port #0

port    equ     0
BOARD   EQU     16*port+$D010

aciac   EQU     BOARD         ;    ACIA CONTROL REGISTER
aciad   EQU     aciac+1       ;    ACIA DATA REGISTER
*
        jsr     reset         ;call the ACIA reset routine
*
* default to short delay (i.e. hard disk)
*
        ldx     #$4000
        stx     odelc
*   Check if host is ready; "sync" with $55
*   and then $aa. This will verify that 8 bits
*   are transferred correctly.
*
sync    ldaa    #5              ;number of tries
        staa    tries
        ldaa    #$55            ;1:st sync char
sync04  staa    tmp
sync08  JSR     schar           ;send char
        bcc     sync16          ;time out, report error
        JSR     rchar           ;get answer from receiver
        bcc     sync16
        cmpa    tmp             ;same as sent?
        beq     sync12          ;yes

        ldaa    tmp
        cmpa    #$55            ;1:st sync char?
        bne     sync16          ;nope, something is wrong

        dec     tries           ;decrease try count
        bne     sync08          ;try again if not 0
        bra     sync16          ;report sync error

sync12  cmpa    #$aa            ;2:nd sync char?
        beq     sync20          ;yes, continue

        ldaa    #$aa            ;send 2:nd sync char
        bra     sync04

sync16  ldx     #synstr         ;"Can't sync..."
sync17  jsr     pstrng
        jmp     warms           ;back to FLEX
*
sync20  ldx     #scnest         ;"Serial connection established"
        jsr     pstrng

*
*   Now do a "Where am I" command
*
        ldaa    #"?"
        JSR     schar
        bcc     sync16
*
*   Receive the current drive and folder string,
*   and keep the first letter, with some processing:
*   @ if floppy, other if hard disk
*
        JSR     rchar
        bcc     sync16          ;exit if time-out
        PSHA                    ;save character
        suba    #1              ;A/B becomes @/A
        anda    #$5E            ;make upper case
        staa    drvltr          ;store it as @ if floppy
        cmpa    #$40            ;is it floppy?
        bne     wtack           ;no, leave as-is
        ldx     #$FFFF          ;set long delay
        stx     odelc           ;store it
*
*   receive all other characters and discard them
*   until the final ACK is received
*
wtack   JSR     rchar
        bcc     sync16
        cmpa    #ack
        bne     wtack
*
*   Inform user about the current drive
*
        ldx     #drvmsg         ;point to string
        jsr     pstrng          ;print it
        PULA                    ;retrieve original char
        anda    #$5f            ;make upper case
        jsr     putchr          ;print it
        LDAA    #":"            ;... then print ":"
        jsr     putchr
*
*   Copy FLEX driver jump table to new location and original to jump table
*
        LDX     #$BE81      ; start jump vectors inc aways 3+
* fread
        LDD     0,X         ; get address original FLEX2
        STD     fread+1     ; FLEX2 value to jump table
        LDD     newtbl      ; get new NET value
        STD     0,X         ; put into FLEX driver section
* fwrite
        LDD     3,X         ; get address original FLEX2
        STD     fwrite+1    ; FLEX2 value to jump table
        LDD     newtbl+2    ; get new NET value
        STD     3,X         ; put into FLEX driver section        
* fverfy
        LDD     6,X         ; get address original FLEX2
        STD     fverfy+1    ; FLEX2 value to jump table
        LDD     newtbl+4    ; get new NET value
        STD     6,X         ; put into FLEX driver section  
* frestr
        LDD     9,X         ; get address original FLEX2
        STD     frestr+1    ; FLEX2 value to jump table
        LDD     newtbl+6    ; get new NET value
        STD     9,X         ; put into FLEX driver section  
* fdrive
        LDD     12,X        ; get address original FLEX2
        STD     fdrive+1    ; FLEX2 value to jump table
        LDD     newtbl+8    ; get new NET value
        STD     12,X        ; put into FLEX driver section  
* fcheck
        LDD     15,X        ; get address original FLEX2
        STD     fcheck+1    ; FLEX2 value to jump table
        LDD     newtbl+10   ; get new NET value
        STD     15,X        ; put into FLEX driver section  
* fquick
        LDD     18,X        ; get address original FLEX2
        STD     fquick+1    ; FLEX2 value to jump table
        LDD     newtbl+12   ; get new NET value
        STD     18,X        ; put into FLEX driver section  
* 
* insert JMP into jump table
*
        LDAA    #$7E
        STAA    fread
        STAA    fwrite
        STAA    fverfy
        STAA    frestr
        STAA    fdrive
        STAA    fcheck
        STAA    fquick
*       
        ldx     #instst         ;"Remote .DSK ...
        jsr     pstrng
        ldaa    netdrv          ;get 'net drive'#
        adda    #$30            ;make ASCII
        jsr     putchr
        jsr     pcrlf
        jmp     warms
*
* Messages to the user
*
greet   fcc     "FLEXNet driver version "
v1      fcb     0,".",0,4
synstr  fcc     "Can't sync serial transfer!"
        fcb      4
scnest  fcc     "Serial connection established"
        fcb      4
instst  fcc     "Remote .DSK drive installed as drive #"
        fcb      4
alread  fcc     "FLEXNet is already loaded, no action taken."
        fcb      4
drvmsg  fcc     "Current MS-DOS drive is "
        fcb      4
drvsig  fcc     "Driver signature not recognized!"
        FCB      4
*
        end     ; start
