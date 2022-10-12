;; Sumary: This is a starting shell for writing a PCJr IPL Cartridge
;  Note: Since we don't define the stack MASM will throw a warning
;  Build steps:
;		1.) MASM to assemble to an exe
;		2.) EXE2BIN.EXE to convert to COM/Binary
;		3.) Externally calculate the CRC bytes
;		4.) Write to PCJr ROM chip

; Interrupt Vectors
int18_offset					EQU	018h * 004h ;; BIOS System Start Call, used to hand final control to cartridge
int18_segment					EQU	int18_offset + 002h

int21_offset					EQU	021h * 004h ;; Would be DOS INT 21 service
int21_segment					EQU	int21_offset + 002h

;; CART Equates
cart_rom_len					EQU	2000h

;; BIOS Service Interrupt CONSTANTS
int_video						EQU	10h
	svc_video_mode					EQU	00h
	svc_video_set_cursor_pos		EQU	02h	
	svc_video_write_char_tty		EQU	0Eh
	svc_video_get_current_mode		EQU	0Fh
int_dos_21						EQU 21h
	svc_dos_print_str				EQU 09h

;; Memory map
;0000:00 - 0030:00 - Interrupt Vector table
interrupt_vector_table_segment	EQU	0000h
;0030:00 - 0040:00 - Stack
	val_top_of_stack					EQU 0100h
;0040:00 - 0050:00 - BIOS Data
;0050:00 - 0800:00 - System RAM
system_ram_segment				EQU	0050h
;0800:00 - 0C00:00 - Video Page 2 (Alias to 6)
;0C00:00 - 1000:00 - Video Page 3 (Alias to 7)
;------------------------------
;B800:00 - BC00:00 - Video RAM (Alias to one of the two video pages)
video_ram_segment				EQU	0B800h
;D000:00 - D800:00 - CART ROM
;E000:00 - E800:00 - CART RAM (Read)
;E800:00 - F000:00 - CART RAM (Write)
;F000:00 - 		   - BIOS
bios_rom_segment				EQU	0F000h

;; Program Equates

CARTSEG segment
assume CS:CARTSEG, DS:CARTSEG 

ORG	0000h

HEADER: ; PC Jr Cartridge Header
	cartridgeid			dw		0AA55h
	cartridgelength		db		cart_rom_len/512	;; TODO - can the assembler calculate this 		
	jmp					INIT					;; ENTRY POINT
	headerend			db		00h
;; INIT Function
INIT PROC FAR
	; The BIOS pushes DX (the current ROM block being checked for signatures) to the stack
	; and then does a call (far) (which pushes the segment and offset before jumping)
	; Assumes your init didn't push additional data to the stack
	mov		bp,sp ; Set the base pointer
	mov		ax,bios_rom_segment ;
	mov		[bp+4],ax ; Set the "current ROM block" to be after the end of the cartridge
	
	; Set up the interrupt vector to boot into the cartridge
	mov		ax,interrupt_vector_table_segment
	mov		es,ax ; Set ES to 0000h (the interrupt vector segment)
	mov		ax,cs
	mov		es:int18_segment,ax ; Move the current Code Segment to the Interrupt Vector 2nd 2 bytes
	mov		ax,offset MAIN
	mov		es:int18_offset,ax ; Move the Main Offset to the Interrupt Vector 1st 2 bytes
	ret
INIT ENDP

LOAD_DOS_INT21H MACRO
	mov		ax,interrupt_vector_table_segment
	mov		es,ax ; Set ES to 0000h (the interrupt vector segment)
	mov		ax,cs
	mov		es:int21_segment,ax ; Move the current Code Segment to the Interrupt Vector 2nd 2 bytes
	mov		ax,offset DOS_INT_21
	mov		es:int21_offset,ax ; Move the DOS_INT_21 Offset to the Interrupt Vector 1st 2 bytes
ENDM

LONG_DELAY MACRO
	local LONG_DELAY_LOOP
	push	cx
	mov		cx,0FFFFh
LONG_DELAY_LOOP:
	loop	LONG_DELAY_LOOP
	pop		cx
ENDM

UTIL_PRINT_NEWLINE MACRO
	;; Print \r\n
	mov		al,00Dh
	mov		ah,svc_video_write_char_tty
	int		int_video
	mov		al,00Ah
	mov		ah,svc_video_write_char_tty
	int		int_video
ENDM

PRINT_TEST_STRING MACRO
	mov		dx,offset TEST_STRING
	mov		ah,svc_dos_print_str
	int		int_dos_21
	UTIL_PRINT_NEWLINE
ENDM

;; TODO LIST
; 0.) Implement DOS Int 21h, Service 9
; 1.) Move Stand-alone RAM values from cart space to ram space
; 2.) Fix references to those values (including segment)
; 3.) Output Str has 5 bytes RAM used, either seperate it or copy it
; 4.) Update references to the Output Str's

DOS_INT_21 PROC FAR ; Need to load this vector
	sti ; re-enable interrupts
	cmp		ah,09h ; Check if service 9
	jne		short DOS_INT_21_END ; If not, exit
DOS_INT21_SVC_9:
	push	ax
	push	bx ; Save user regs
	
	mov		ah,svc_video_get_current_mode
	int		int_video ; Set's BH
	
	xchg	si,dx ; Can't use DX to index, swap with SI
DOS_INT21_LOOP:
	mov		al,[si] ; Read next character
	cmp		al,'$' ; Compare to terminator
	je		short DOS_INT_21_CLEANUP ; Leave if terminator

	mov		ah,svc_video_write_char_tty ; Else Print the character
	int		int_video
	
	inc		si ; increment to the next one
	jmp		short DOS_INT21_LOOP ; loop again
DOS_INT_21_CLEANUP:
	xchg	si,dx ; Swap SI back
	
	pop		bx ; Restore user regs
	pop		ax
DOS_INT_21_END:
	iret
DOS_INT_21 ENDP

DEFAULT_CART_SEGMENTS MACRO ; Normally DS == Cart ROM, ES == System RAM
	mov		ax,cs
	mov		ds,ax ;; Set DS == CS
	mov		ax,system_ram_segment
	mov		es,ax ;; Set ES == System Ram Segment
ENDM

PRINT_RAM_SEGMENTS MACRO ; DS needs to be RAM when printing RAM values
	mov		ax,cs
	mov		es,ax ; Set ES == CS
	mov		ax,system_ram_segment
	mov		ds,ax ; Set DS == System Ram Segment
ENDM

;; Zen Timer RAM Values (ES offsets)
OriginalFlags	EQU 0000h ; 1 Byte ;OriginalFlags	db	?
TimedCount		EQU 0001h ; 2 Bytes ;TimedCount		dw	?
	TimedCount1		EQU 0001h
	TimedCount2		EQU 0002h
ReferenceCount	EQU 0003h ; 2 Bytes ;ReferenceCount	dw	?
	ReferenceCount1		EQU 0003h
	ReferenceCount2		EQU 0004h
OverflowFlag	EQU 0005h ; 1 Byte ;OverflowFlag	db	?
OutputStrVars	EQU 0006h ; 5 Bytes ; New variable to cover the Vars in OutputStr
	OutputStrVars1		EQU 0006h
	OutputStrVars2		EQU 0007h
	OutputStrVars3		EQU 0008h
	OutputStrVars4		EQU 0009h
	OutputStrVars5		EQU 000Ah
	OutputStrVars6		EQU 000Bh ; Used for $ terminator

BASE_8253		EQU 40h
TIMER_0_8253	EQU BASE_8253 + 0
MODE_8253		EQU BASE_8253 + 3
OCW3			EQU 20h
IRR				EQU 20h

MPOPF MACRO
	local P1,P2
	jmp short P2
P1:	iret
P2:	push cs
	call P1
ENDM

DELAY MACRO
	jmp		$+2
	jmp		$+2
	jmp		$+2
ENDM

OutputStr	label byte
	db 0Dh,0Ah,'Timed count: ','$'
ASCIICountEnd	label byte
	db ' microseconds',0Dh,0Ah
	db '$'
OverflowStr	label byte
	db 0Dh, 0Ah
	db '*************************************************'
	db 0Dh, 0Ah
	db '* The timer overflowed, so the interval was     *'
	db 0Dh, 0Ah
	db '* too long for the precision timer to measure.  *'
	db 0Dh, 0Ah
	db '* Please perform the timing test again with the *'
	db 0Dh, 0Ah
	db '* long-period timer.                            *'
	db 0Dh, 0Ah
	db '*************************************************'
	db 0Dh, 0Ah
	db '$'

ZTimerOn PROC NEAR
	push	ax
	pushf
	pop		ax ; Get flags
	mov		es:OriginalFlags,ah
	and		ah,0FDh ; Set pushed interrupt flag to 0
	push	ax
	
	sti ; Let timer interrupt occur if pending
	
	mov		al,00110100b ; Mode 2
	out		MODE_8253,al
	
	; Set timer count to 0
	DELAY
	sub		al,al
	out		TIMER_0_8253,al ; lsb
	DELAY
	out		TIMER_0_8253,al ; msb
	
	; Wait before clearing interrupts
	REPT	10
	jmp		$+2
	ENDM
	
	; Disable interrupts
	cli
	
	; Set timer count to 0 again
	mov		al,00110100b
	out		MODE_8253,al
	DELAY
	sub		al,al
	out		TIMER_0_8253,al
	DELAY
	out		TIMER_0_8253,al
	
	MPOPF
	pop		ax
	
	ret
ZTimerOn ENDP

ZTimerOff PROC NEAR
	push	ax
	push	cx
	pushf
	
	; Latch the count
	mov		al,00000000b
	out		MODE_8253,al
	
	; Check if overflowed
	mov		al,00001010b
	out		OCW3,al
	DELAY
	in		al,IRR
	and		al,1
	mov		es:OverflowFlag,al
	
	; Allow interrupts to happen
	sti
	
	in		al,TIMER_0_8253 ; LSB
	DELAY
	mov		ah,al
	in		al,TIMER_0_8253 ; MSB
	xchg	ah,al
	neg		ax
	mov		es:TimedCount,ax
	
	; mov	es:ReferenceCount,0
		push ax
	sub		ax,ax
	mov		es:ReferenceCount,ax ; TODO, find a way to load word constant 16 bits
		pop ax
		
	mov		cx,16
	cli
RefLoop:
	call	ReferenceZTimerOn
	call	ReferenceZTimerOff
	loop	RefLoop
	
	sti
	add		es:ReferenceCount,low 8
	mov		cl,4
	;shr		es:ReferenceCount,cl ; TODO, find a way to do this without AX
		push	ax
	mov		ax,es:ReferenceCount
	shr		ax,cl
	mov		es:ReferenceCount,ax 
		pop		ax
	pop		ax
	mov		ch,es:OriginalFlags
	and		ch,NOT 0FDh
	and		ah,0FDh
	or		ah,ch
	push	ax
	MPOPF
	pop		cx
	pop		ax
	ret
ZTimerOff ENDP

ReferenceZTimerOn PROC NEAR
	push	ax
	pushf
	
	mov		al,00110100b
	out		MODE_8253,al
	DELAY
	
	; Set timer count to 0
	sub		al,al
	out		TIMER_0_8253,al ; load lsb
	DELAY
	out		TIMER_0_8253,al ; load msb
	MPOPF
	pop		ax
	ret
ReferenceZTimerOn ENDP

ReferenceZTimerOff PROC NEAR
	push	ax
	push	cx
	pushf
	
	; latch/read count
	mov		al,00000000b
	out		MODE_8253,al
	DELAY
	
	in		al,TIMER_0_8253 ; lsb
	DELAY
	mov		ah,al
	in		al,TIMER_0_8253 ; msb
	xchg	ah,al
	neg		ax
	add		es:ReferenceCount,ax
	
	MPOPF
	pop		cx
	pop		ax
	ret
ReferenceZTimerOff ENDP

INITIALIZE_VALS MACRO
	;mov		al,0
	;mov		es:OverflowFlag,al 

	;mov		ax,12345
	;mov		es:TimedCount,ax
	;mov		ax,02345
	;mov		es:ReferenceCount,ax
	

	;mov		al,'1'
	;mov		es:OutputStrVars1,al
	;mov		al,'2'
	;mov		es:OutputStrVars2,al
	;mov		al,'3'
	;mov		es:OutputStrVars3,al
	;mov		al,'4'
	;mov		es:OutputStrVars4,al
	;mov		al,'5'
	;mov		es:OutputStrVars5,al
	mov		al,'$'
	mov		es:OutputStrVars6,al
ENDM

ZTimerReport PROC NEAR
	INITIALIZE_VALS ; Initialize the string terminator
	
	pushf
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	ds
	push	es
	
	DEFAULT_CART_SEGMENTS ; For cartridge, expect DS to be ROM, ES to be RAM
	
	cmp		es:OverflowFlag,low 0
	jz		PrintGoodCount
	mov		dx,offset OverflowStr
	mov		ah,svc_dos_print_str
	int		int_dos_21
	jmp		short EndZTimerReport
PrintGoodCount:
	mov		ax,es:TimedCount
	sub		ax,es:ReferenceCount
	
	mov		si,OutputStrVars5 ; Lowest byte offset OutputStrVars excluding $ terminator
	
	; Convert Count to microseconds by multiplying by .8381
	mov		dx,8381
	mul		dx 
	mov		bx,10000
	div		bx ; (TimedCount - ReferenceCount) * 8381/10000
	
	; Convert time in mciroseconds to 5 decimal ASCII digits
	mov		bx,10 ; Each digit is "10"
	mov		cx,5 ; 5 digits
CTSLoop:
	sub		dx,dx ; Zero DX
	div		bx ; Divide AX / 10 ; I assume this leaves a remainder in dl?
	add		dl,'0'
	mov		es:[si],dl
	dec		si
	loop	CTSLoop

	;; Print OutputStr intro (from ROM)
	mov		dx,offset OutputStr
	mov		ah,svc_dos_print_str
	int		int_dos_21
		
	; Print ASCII OutputStrVars (from RAM, needs to swap the segments)
	PRINT_RAM_SEGMENTS
	mov		dx,OutputStrVars
	mov		ah,svc_dos_print_str
	int		int_dos_21
	DEFAULT_CART_SEGMENTS
	
	; Print end of OutputStr ASCIICountEnd (from ROM)
	mov		dx,offset ASCIICountEnd
	mov		ah,svc_dos_print_str
	int		int_dos_21
	
EndZTimerReport:
	pop		es
	pop		ds
	pop		si
	pop		dx
	pop		cx
	pop		bx
	pop		ax
	MPOPF
	ret
ZTimerReport ENDP

;; MAIN Function
MAIN:
	mov		ax,val_top_of_stack ; Top of the stack
	mov		sp,ax ;; Reset the stack pointer
	sti		;; Re-enable interrupts to stop disk drive from spinning indefinitely
	
	LONG_DELAY
	LONG_DELAY ; Long Delay to let disk drive timeout
	LOAD_DOS_INT21H ; Load the DOS INT21h 
	
	DEFAULT_CART_SEGMENTS
	
	PRINT_TEST_STRING

	;;;;;;;;;;;;;;;;;;;;;;;;
	;; USER SETUP CODE HERE
	;;;;;;;;;;;;;;;;;;;;;;;;
	;;;;;;;;;;;;;;;;;;;;;;;;
	call	ZTimerOn
	;;;;;;;;;;;;;;;;;;;;;;;;
	;; USER TEST CODE HERE
	;;;;;;;;;;;;;;;;;;;;;;;;
	;;;;;;;;;;;;;;;;;;;;;;;;
	
	call	ZTimerOff
	
	call ZTimerReport
	
GAMELOOP:	; Fall into Gameloop
	jmp		GAMELOOP

DATA:
TEST_STRING db 'Hola Mundo!$'

ORG	cart_rom_len - 16; 15(name) + 2(chksum) ;; TODO - can the assembler calculate this
FOOTER: ; PCJr Cartridge Footer
	;;								"123456789ABCDE"
	cart_name					db	"Start Project$" ; 
	cart_chksum					dw	0000h ;; TODO - can the assembler calculate this?

CARTSEG ENDS
END ; End program
