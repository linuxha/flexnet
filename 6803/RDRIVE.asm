*   File name:  RDRIVE.TXT
*
*   Syntax: RDRIVE <path>
*
*   Note: <path> may contain the whole directory path,
*         including the disk name, for example "C:\dir1\dir2\.."
*         In order to achieve this, the FLEX EOL character is
*         temporarily cleared. Thus, multiple commands on one
*         line can be used with this utility, only if RMOUNT
*         is the last command on the line.
*
*   Adapted from Bjarne Backstrom's source code for RMOUNT
*   by Joel Setton
*
*       02.01   2002-08-31 js Use signature string
*       02.02   2002-09-19 js New vectors
*       02.03   2002-11-23 js Longer delay if and only if the
*                             drive is A or B, i.e. a floppy
*       02.04   2002-11-24 js Do an "rwhich" command if no
*                             parameters are specified
*       02.05   2024-08-01 Wrede adepted to SBC6803
* ---------------------------------------------------------------
*
*   FLEX equates.
*
warms   equ     $AD03      ;     FLEX warm start
PUTCHR  equ     $AD18      ;     print one character
pstrng  equ     $AD1E      ;     write string to display
pcrlf   equ     $AD24      ;     write cr/lf to display
nxtch   equ     $AD27      ;     get next buffer character
memend  equ     $AC2B      ;     memory end pointer
*
ttylbp  equ     $AC14      ;     line buffer pointer location
ttyeol  equ     $AC02      ;     end of line character location
*
* ---------------------------------------------------------------
*
ack     equ     $06        ;     acknowledge character
cr      equ     $0d        ;     carriage return character

*
* ***************************************************************
*
        org     $A100

start EQU *
        bra     COLD

versn   fcb     2,5     ;        version number
PTR     rmb     2       ;        Pointer in buffer
eoltmp  rmb     1       ;        temp storage for EOL character
chrcnt  rmb     1       ;        character counter
drvptr  rmb     2       ;        drive pointer
temp    rmb     1       ;        temp pointer for letter
*
* ---------------------------------------------------------------
* Serial input/output vectors
* The following 2 JMPs are initialized
* with the addresses of the serial in/out
* vectors which are at the start of NETDRV
* The default (warms) is a dummy value
*
schar JMP warms
rchar JMP warms
*
COLD EQU *         ; START OF CODE
*
* SBC6803 no MEMEND scan necessary
*
* Scan if a copy of FLEXNet is already loaded
* search "netU"
*
search  LDX     #$8015    ; FLEXNET driver here
        LDAA    #"n"
        CMPA    0,X
        BNE     sear4     ; no match
        LDAA    #"e"
        CMPA    1,X
        BNE     sear4
        LDAA    #"t"
        CMPA    2,X
        BNE     sear4
        LDAA    #"U"
        CMPA    3,X
        BNE     sear4     ; no match finally
        BRA     foundit
sear4   JMP     noload
*
* string was found, all is OK
* Set the address of the in/out vectors
*
foundit LDX     #$801D    ; address of schar vector
        STX     schar+1
        LDX     #$8020    ; address of rchar vector
        STX     rchar+1
*
* Set the drive letter pointer
* leax 19,x               ; corrected to 19,x  old 6,x was wrong
        LDX    #$8033
        stx    drvptr

*
* ---------------------------------------------------------------
*
*       jsr     pcrlf       ;    (DELETED)

        lda     ttyeol      ;    save EOL character
        sta     eoltmp

        clr     chrcnt      ;    check file name length
        ldx     ttylbp

chec04  ldaa    0,X         ; x+  get character
        INX
        cmpa    #$20        ;    skip leading spaces
        beq     chec04

        staa    temp        ;    store the first character after spaces

chec08  cmpa    #cr         ;    carriage return?
        beq     chec12
        inc     chrcnt      ;    no, inc character count
        ldaa    0,X         ; x+ check next character
        INX
        bra     chec08

chec12  ldaa    chrcnt      ;    check character count
        cmpa    #1          ;    less than 2 characters?
        blo     where       ;    yes, do a "Where am I" command
*
* ---------------------------------------------------------------
*
        clr     ttyeol      ;    disable TTYEOL

        ldaa    #"V"        ;    send V (driVe) command to remote host
        JSR     schar
        bcc     Mnwrkng      ;    time out, communication not working
*
main04  jsr     nxtch       ;    skip leading spaces
        cmpa    #$20
        beq     main04

main08  JSR     schar       ;    send one character to remote host
        bcc     Mnwrkng      ;    time out, communication not working
        cmpa    #cr         ;    last character in line?
        beq     main12
        jsr     nxtch       ;    get next character
        bra     main08
*
main12  JSR     rchar       ;    get response
        bcc     Mnwrkng      ;    time out, communication not working
        cmpa    #ack        ;    got an ack?
        bne     badfnm      ;    no, report bad file name

*
*  Success!
*
*  store the drive letter
        ldaa temp
        deca                  ;    change a/b to @/a
        anda   #$5e           ;    make upper case
*        staa [drvptr]         ;    store it  !!! find other code
        LDX    drvptr      ; get address of drv pointer
        STAA   0,X         ; store it into [drvptr]
        ldx    #succst     ;    report success
        bra    finish

noload  ldx    #nodrv       ; Inform that drivers are not loaded
        bra    finis2
*
* long branch jump
Mnwrkng JMP    nwrkng
* -----------------------------------------
*
* No parameters were typed, do a "Where am I" command
*
where equ *

* SEND THE "WHERE" COMMAND
       LDAA   #"?"
       JSR    schar
       BCC    nwrkng

* RECEIVE ONE LINE
       LDX    #BUFFER   ; INITIALIZE POINTER
       STX    PTR
LP1    JSR    rchar     ; GET CHAR
       BCC    nwrkng
       CMPA   #cr       ; FINISHED?
       BEQ    DISP
* STORE THE CHARACTER
       JSR    PUTIT
       BRA    LP1

DISP EQU *
* LINE FEED RECEIVED, DISPLAY LINE ON CRT
       CLRA             ; ADD TERMINATOR
       JSR    PUTIT

* set the drive code
       ldaa    BUFFER   ; get the first character of string
       deca
       anda    #$5e
*       staa [drvptr]   ; !!! find code for that
       LDX    drvptr      ; get address of drv pointer
       STAA   0,X         ; store it into [drvptr]
       LDX    #CURDIR
       JSR    pstrng

 LDX #BUFFER
 JSR PDATA

* WAIT FOR ACK
WTACK   JSR    rchar
        BCC    nwrkng
        CMPA   #ack
        BNE    WTACK
        BRA    exit2


* LOW-LEVEL ROUTINES
* PRINT A STRING
*
PDATA2  JSR    PUTCHR
PDATA   LDAA   0,X
        INX
        CMPA   #0          ; because of INX
        BNE    PDATA2
        RTS

* PUT A CHARACTER IN BUFFER
PUTIT   LDX    PTR
        STAA   0,X          ; X+
        INX
        STX    PTR
        RTS


*
*   Error/exit routines
*
badfnm  ldx     #badfst      ;   bad name
        bra     finish
*
nwrkng  ldx     #nwrkst      ;   communication is not working
        bra     finish
*
finish  lda     eoltmp       ;   restore EOL character
        sta     ttyeol
finis2  jsr     pstrng       ;   print string pointed to by XREG
exit2   jmp     warms        ;   back to FLEX
*
* ---------------------------------------------------------------
*
CURDIR  FCC     "The current directory is  "
        FCB     4
nwrkst  fcc     "Communication is not working!"
        FCB     8,4
badfst  fcc     "Bad directory name!"
        FCB     8,4
succst  fcc     "Command executed OK."
        FCB     4
nodrv   FCC     "NETDRV is not loaded in memory, no action taken."
        FCB     4


* BUFFER AREA
BUFFER RMB 256
        end  ;   start