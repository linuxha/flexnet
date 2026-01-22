*   File name:  RCD.TXT
*
*   This utility will Change to a new Directory (hence CD)
*   on a remote host computer, that is running NETPC.
*   netdrv must already be running on the FLEX computer.
*
*   Syntax: RCD <path>
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
*       02.03   2024-08-01 Wrede adepted to SBC6803
* ---------------------------------------------------------------
*
*   FLEX equates.
*
warms   equ     $AD03     ;      FLEX warm start
pstrng  equ     $AD1E     ;      write string to display
pcrlf   equ     $AD24     ;      write cr/lf to display
nxtch   equ     $AD27     ;      get next buffer character
memend  equ     $AC2B     ;      memory end pointer
*
ttylbp  equ     $AC14     ;      line buffer pointer location
ttyeol  equ     $AC02     ;      end of line character location
*
* ---------------------------------------------------------------
*
ack     equ     $06       ;     acknowledge character
cr      equ     $0d       ;     carriage return character

*
* ***************************************************************
*
        org     $A100


start EQU *
        bra     COLD

versn   fcb     2,3       ;      version number
eoltmp  rmb     1         ;      temp storage for EOL character
chrcnt  rmb     1         ;      character counter
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
COLD EQU *               ; START OF CODE
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
* ---------------------------------------------------------------
*
*
        jsr     pcrlf

        ldaa    ttyeol         ; save EOL character
        sta     eoltmp

        clr     chrcnt         ; check file name length
        ldx     ttylbp

chec04  ldaa    0,X            ; x+  get character
        INX
        cmpa    #$20           ; skip leading spaces
        beq     chec04

chec08  cmpa    #cr            ; carriage return?
        beq     chec12
        inc     chrcnt         ; no, inc character count
        ldaa    0,X            ; x+  check next character
        INX
        bra     chec08

chec12  ldaa    chrcnt         ; check character count
        cmpa    #2             ; less than 2 characters?
        blo     badfnm         ; yes, report bad file name
*
* ---------------------------------------------------------------
*
        clr     ttyeol         ; disable TTYEOL

        ldaa    #"P"           ; send P (Point) command to remote host
        JSR     schar
        bcc     nwrkng         ; time out, communication not working
*
main04  jsr     nxtch          ; skip leading spaces
        cmpa    #$20
        beq     main04

main08  JSR     schar          ; send one character to remote host
        bcc     nwrkng         ; time out, communication not working
        cmpa    #cr            ; last character in line?
        beq     main12
        jsr     nxtch          ; get next character
        bra     main08
*
main12  JSR     rchar          ; get response
        bcc     nwrkng         ; time out, communication not working
        cmpa    #ack           ; got an ack?
        bne     badfnm         ; no, report bad file name
        ldx     #succst        ; report success
        bra     finish
*
* ---------------------------------------------------------------
*
nwrkng  ldx     #nwrkst        ; communication is not working
        bra     finish

noload  ldx     #nodrv         ; Inform that drivers are not loaded
        bra     finis2

badfnm  ldx     #badfst        ; bad file name

finish  ldaa    eoltmp         ; restore EOL character
        staa    ttyeol
finis2  jsr     pstrng         ;print string pointed to by XREG
        jmp     warms          ; back to FLEX
*
* ---------------------------------------------------------------
*
nwrkst  fcc     "Communication is not working!:"
        FCB     8,4
badfst  fcc     "Bad directory name!:"
        FCB     8,4
succst  fcc     "Command executed OK."
        FCB     4
nodrv   FCC     "NETDRV is not loaded in memory, no action taken."
        FCB     4

 end   ; start
