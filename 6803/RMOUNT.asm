*   File name:  rmount.asm
*
*   This utility will "MOUNT" a .DSK file
*   on a remote host computer, that is running NETPC.
*   netdrv must already be running on the FLEX computer.
*
*   Syntax: RMOUNT <file_name>
*
*   Note: <file_name> may contain the whole directory path,
*         including the disk name, for example "C:\dir1\dir2\.."
*         In order to achieve this, the FLEX EOL character is
*         temporarily cleared. Thus, multiple commands on one
*         line can be used with this utility, only if RMOUNT
*         is the last command on the line.
*
*   Vn  01.00   2000-09-25, BjB.
*       01.01   2002-05-01 js Use the serial routines in NETDRV
*       02.01   2002-08-31 js Use signature string
*       02.02   2002-09-19 js New vectors
*       02.03   2002-10-06 js Check for proper extension
*       02.04   2002-11-12 js Add read/write status check
*       02.05   2024-08-01 Wrede adepted to SBC6803
*
* ---------------------------------------------------------------
*
*   FLEX equates.
*
warms   equ     $AD03        ;   FLEX warm start
pstrng  equ     $AD1E        ;   write string to display
pcrlf   equ     $AD24        ;   write cr/lf to display
nxtch   equ     $AD27        ;   get next buffer character
MEMEND  EQU     $AC2B
*
ttylbp  equ     $AC14        ;  line buffer pointer location
ttyeol  equ     $AC02        ;   end of line character location
*
* ---------------------------------------------------------------
*
ack     equ     $06          ;  acknowledge character
cr      equ     $0D          ;  carriage return character

*
* ***************************************************************
*
        org     $A100
start BRA COLD
*
*
versn   fdb     $0205        ;   version number
eoltmp  rmb     1            ;  temp storage for EOL character
chrcnt  rmb     1            ;   character counter

* Serial input/output vectors
* The following 2 JMPs are initialized
* with the addresses of the serial in/out
* vectors which are at the start of NETDRV
* The default (WARMS) is a dummy value

schar JMP warms
rchar JMP warms


* START OF CODE
COLD ;EQU *
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
* Long jumps
*
Mnwrkng JMP    nwrkng
*
* string was found, all is OK
* Set the address of the in/out vectors
*
foundit LDX     #$801D    ; address of schar vector
        STX     schar+1
        LDX     #$8020    ; address of rchar vector
        STX     rchar+1
*
* ---------------------------------------------------------------
*
check   jsr     pcrlf

        ldaa    ttyeol        ;  save EOL character
        staa    eoltmp

        ldaa    #"Q"          ;  quick check that communication is working
        JSR     schar
        bcc     Mnwrkng       ;  time out, communication not working

        JSR     rchar         ;  get response
        bcc     Mnwrkng       ;  time out, communication not working
        cmpa    #ack          ;  got an ack?
        bne     Mnwrkng       ;  communication not working

*
* -----------------------------------------------------
*
*  Check file name length/extension

        clr     chrcnt
        ldx     ttylbp

chec04  ldaa    0,X         ; x+  get character
        INX
        cmpa    #$20        ;   skip leading spaces
        beq     chec04

chec08  cmpa    #cr         ;   carriage return?
        beq     chec12
        cmpa    #"."        ;    Extension provided?
        bne     chec10
* the next characters must be "dsk"
* SBC6803 direct check !

        LDAA    0,X
        INX
        ANDA    #$5F        ; convert to uppercase
        CMPA    #"D"        ; D?
        BNE     badex       ; exit for bad extention
        LDAA    0,X
        INX
        ANDA    #$5F        ; convert to uppercase
        CMPA    #"S"        ; S?
        BNE     badex       ; exit for bad extention
        LDAA    0,X
        INX
        ANDA    #$5F        ; convert to uppercase
        CMPA    #"K"        ; K?
        BNE     badex       ; exit for bad extention

*        ldy     #ext
*
*chec09  lda     ,x+
*        anda    #$5f
*        cmpa    ,y+
*        bne     badex
*        cmpy    #ext+3     ; test auf DSK string ende
*        bne     chec09

chec10  inc     chrcnt      ;  no, inc character count
        ldaa     0,X        ; x+   check next character
        INX
        bra     chec08

chec12  ldaa    chrcnt        ;  check character count
        cmpa    #2            ;  less than 2 characters?
        blo     badfnm        ;  yes, report bad file name
*
* ---------------------------------------------------------------
*
main    clr     ttyeol        ;  disable TTYEOL

        ldaa    #"M"          ; send M(ount) command to remote host
        JSR     schar
        bcc     nwrkng        ; time out, communication not working
*
main04  jsr     nxtch         ; skip leading spaces
        cmpa    #$20
        beq     main04

main08  JSR     schar         ; send one character to remote host
        bcc     nwrkng        ; time out, communication not working
        cmpa    #cr           ; last character in line?
        beq     main12
        jsr     nxtch         ; get next character
        cmpa    #"."           ; substitute cr for dot
        bne     main08
        ldaa    #cr
        bra     main08
*
main12  JSR     rchar         ; get response
        bcc     nwrkng        ; time out, communication not working
        cmpa    #ack          ; got an ack?
        bne     badfnm        ; no, report bad file name
*
* Check for "R" or "W" after the ack
*
        JSR     rchar         ; get character
        bcc     nwrkng        ; time out, not working
        cmpa    #"R"          ; Read only?
        beq     read
        cmpa    #"W"          ; Write only?
        beq     write
        bra     badfnm        ; otherwise, report error

*
* ---------------------------------------------------------------
badex   ldx     #exten        ; Bad extension
        bra     finish

noload  ldx     #nodrv        ; Driver not found
        bra     finish

read    ldx     #readst       ; Read-only message
        bra     finish

write   ldx     #writest      ; Full access message
        bra     finish

nwrkng  ldx     #nwrkst       ; communication is not working
        bra     finish
*
badfnm  ldx     #badfst       ; bad file name
*
finish  ldaa    eoltmp        ; restore EOL character
        staa    ttyeol
        jsr     pstrng        ; print string pointed to by XREG
        jmp     warms         ; back to FLEX
*
* ---------------------------------------------------------------
*
exten   fcc     "Illegal file extension"
        FCB     4
nwrkst  fcc     "Communication is not working!"
        FCB     4
badfst  fcc     "Could not open file"
        FCB     4
readst  fcc     "File open in read-only mode"
        FCB     4
writest fcc     "File opened with full access (read/write)"
        FCB     4
succst  fcc     "Command executed OK."
        FCB     4
nodrv   fcc     "NETDRV is not loaded in memory, no action taken."
        FCB     4

* Extension string
ext     fcc    "DSK"

        end  ;   start
