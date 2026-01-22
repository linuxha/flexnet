* NAM RLIST
*
* REMOTE DIRECTORY LISTING THROUGH NETPC
*
*
*       02.01   2002-08-31 js Use signature string
*       02.02   2002-09-19 js New vectors
*       02.03   2024-08-02 Wrede adepted to SBC6803
* -------------------------------------------------
* LIB FLEXEQU
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
*
* SEPARATOR IN THE OUTPUT STREAM
SEP     EQU CR

* LINES PER SCREEN
SCREEN  EQU 20

  ORG $A100
  BRA COLD
* VERSION NUMBER
VN    FCB 2,3
* TEMP STORAGE
COUNT RMB 1   ; LINE COUNTER
PTR   RMB 2   ; POINTER
*
*
* Serial input/output vectors
* The following 2 JMPs are initialized
* with the addresses of the serial in/out
* vectors which are at the start of NETDRV
* The default (WARMS) is a dummy value
*
schar JMP WARMS
rchar JMP WARMS
*
COLD EQU *     ; START OF CODE

memend  equ     $AC2B      ;     FLEX end of user RAM

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
* -------------------------------------------------
*

*INITIALIZE THE BUFFER
        LDX    #BUFFER
        STX    PTR       ; INITIALIZE POINTER

* PUT THE "RLIST" COMMAND
        LDAA   #"I"
        JSR    PUTIT

* SEND A <CR>
        LDAA   #SEP
        JSR    PUTIT

* NOW TERMINATE THE STRING
        CLRA
        JSR    PUTIT

* NOW SEND OUT THE CONTENTS OF
* THE BUFFER AS ONE SERIAL STREAM
        LDX    #BUFFER
LOOP    LDAA   0,X       ;X+
        INX
        BEQ    SEREND
        JSR    schar
        BCC    NOWORK
        BRA    LOOP
SEREND  EQU *
*
* ADDED CODE
* SEND A SPACE TO START THE FIRST LINE
        LDAA   #$20
        JSR    schar
        BCC    NOWORK
*
* START A NEW SCREEN
NEW     LDAA   #SCREEN
        STAA   COUNT

* RECEIVE ONE LINE
ONELIN  EQU *
        LDX    #BUFFER    ; INITIALIZE POINTER
        STX    PTR
LP1     JSR    rchar      ; GET CHAR
        BCC    NOWORK
        CMPA   #ACK       ; FINISHED?
        BEQ    EXIT
* STORE THE CHARACTER
        JSR    PUTIT
* LOOP IF NOT <LF>
        CMPA   #LF
        BNE    LP1
* LINE FEED RECEIVED, DISPLAY LINE ON CRT
        CLRA          ; ADD TERMINATOR
        JSR    PUTIT
        LDX    #BUFFER
        JSR    PDATA

* COUNT DOWN LINES
        DEC    COUNT
        BEQ    ASK

* SEND A SPACE FOR NEXT LINE
        LDAA   #$20
        JSR    schar
        BCC    NOWORK
        BRA    ONELIN

* ASK THE USER
ASK     LDX    #ASKUSR
        JSR    PDATA
        JSR    GETCHR
        CMPA   #ESC
        BEQ    EX1
        CMPA   #$20
        BNE    ASK

* GO FOR ANOTHER SCREEN
        JSR    schar
        BRA    NEW

* ESCAPE RECEIVED, SEND ESCAPE TO MSD0S
EX1     JSR    schar
        BCC    NOWORK
        JSR    PCRLF

* WAIT FOR ACK
WTACK   JSR    rchar
        BCC    NOWORK
        CMPA   #ACK
        BNE    WTACK
        BRA    EXIT

noload  ldx    #nodrv    ; Inform that drivers are not loaded
        bra    finish

NOWORK  LDX    #TIMOUT
finish  JSR    PDATA

EXIT    JMP    WARMS

* LOW-LEVEL ROUTINES
* PRINT A STRING
PDATA2  JSR    PUTCHR
PDATA   LDAA   0,X
        INX
        CMPA   #0
        BNE    PDATA2
        RTS

* PUT A CHARACTER IN BUFFER
PUTIT   LDX    PTR         ;GET POINTER
        STAA   0,X         ; X+ STORE BYTE AND BUMP PTR
        INX
        STX    PTR
        RTS

* CHARACTER STRINGS

ASKUSR FCB CR
       FCC "Press spacebar to continue, ESC to stop "
       fcb 0

TIMOUT FCB CR,LF
       FCC "Communication time-out error"
       FCB 0

nodrv  FCB CR,LF
       FCC "NETDRV is not loaded in memory, no action taken."
       FCB 0

* BUFFER AREA
BUFFER RMB 256

 END    ; $A100
