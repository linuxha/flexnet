*   File name:  resync.asm
*
*   This utility will try to re-synchronize the communication
*   between the FLEX/netdrv and the remote host computers.
*
*   Vn  01.00   2000-09-23, BjB.
*       02.00   2002-05-01, js, use send/receive vectors
*       02.01   2002-08-31  js Use signature string
*       02.02   2002-09-19  js restore ACIA reset routine
*       02.03   2024-08-01  Wrede adepted to SBC6803
* --------------------------------------------------------------
*
*   FLEX equates.
*
warms   equ     $AD03    ;       FLEX warm start
pstrng  equ     $AD1E    ;       write string to display
pcrlf   equ     $AD24    ;       write cr/lf to display
memend  equ     $AC2B    ;       memory end pointer
*
* ---------------------------------------------------------------
*
        org     $A100

start   bra     init

versn   FCB     2,3     ;        version number
tries   rmb     1       ;        sync tries counter
tmp     rmb     1       ;        temporary storage for sync char
*
* ---------------------------------------------------------------
*
* Serial input/output vectors
* The following 2 JMPs are initialized
* with the addresses of the serial in/out
* vectors which are at the start of NETDRV
* The default (WARMS) is a dummy value
*
schar JMP warms
rchar JMP warms
reset JMP warms
*
init equ *                ; Start of code
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
        LDX     #$8023    ; address of reset vector
        STX     reset+1

*   acia reset
*
        bsr reset

*   Main routine.
*
        jsr     pcrlf
        ldaA    #$5        ;    number of tries
        staa    tries
        ldaa    #$55       ;     1:st sync character

sync    sta     tmp        ;     current sync character

sync04  JSR     schar      ;     send character
        bcc     sync16     ;     time-out, report error

        JSR     rchar      ;     get response
        bcc     sync16     ;     time-out, report error

        cmpa    tmp        ;     received char same as sent?
        beq     sync08     ;     yes
        ldaa    tmp        ;     1:st sync char?
        cmpa    #$55
        bne     sync20     ;     nope, report error

        dec     tries      ;     decrement try count
        bne     sync04     ;     try again if not = 0
        bra     sync20     ;     report error

sync08  cmpa    #$aa       ;     2:nd sync character?
        beq     sync12     ;     yes, report success
        ldaa    #$aa       ;     send 2:nd sync character
        bra     sync
*
sync12  ldx     #succst    ;     "Connection successfully.."
        bra     sync24

sync16  ldx     #timest    ;     "Time-out.."
        bra     sync24

noload  ldx     #nodrv     ; Inform that drivers are not loaded
        bra     sync24

sync20  ldx     #synest    ;     "Could not sync.."
sync24  jsr     pstrng
        jmp     warms      ;     back to FLEX
*
* ---------------------------------------------------------------
*
succst  fcc     "Connection successfully established"
        FCB      4
timest  fcc     "Time-out error, connection broken!"
        FCB      8,4
synest  fcc     "Could not synchronize the communication!"
        FCB      8,4
nodrv   FCC     "NETDRV is not loaded in memory, no action taken."
        FCB      4

        end   ;  start