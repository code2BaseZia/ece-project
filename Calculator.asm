; Calculator.asm
; Describes behavior for a six-function calculator

; Operations Definitions:
; SW0: Set argument A (1)
; SW1: Set argument B (2)
; SW2: Set current operation (4)
; SW3: Return to outputs (8)
; SW8: Clear arguments and outputs (256)
; DURING OUTPUT PHASE: SW0 toggles between OUT_A and OUT_B

; LED Definitions:
; LED 0: Setting argument A
; LED 1: Setting argument B
; LED 2: Setting current operation
; LED 3: Displaying output A
; LED 4: Displaying output B
; LED 0 & 9: Setting mode
; LEDs 4-0 Snaking: Working
; LEDs 9-0 Blinking: ERROR

; CURR_OP Definitions
; SW0: ADD (1)
; SW1: SUB (2)
; SW2: MULT (4)
; SW2&0: MULT_UNSIGNED (5)
; SW3: DIV (8)
; SW3&0: DIV_UNSIGNED (9)
; SW4: SQRT (16)
; SW5: SIN/COS (32)

; CTRL / STATUS bits
; bit 0: START (write 1 to begin)
; bit 1: OP_DIV (1 = DIV, 0 = MUL unless SQRT/CORDIC selected)
; bit 2: SIGNED (1=signed, 0=unsigned) for MUL/DIV
; bit 3: OP_SQRT (1=SQRT)
; bit 4: OP_CORDIC (1=CORDIC)
; Status bits 5-7
; ST_DONE : 0
; ST_BUSY : 1
; ST_DIV0 : 2 (set for divide-by-zero)



ORG 0
CLEAR:  ; Reset/set values on startup/clear
		; TODO, reset all peripheral values to 0
	LOADI 0
	STORE ARG_A
	STORE ARG_B
    STORE OUT_A
	STORE OUT_B
    STORE CURR_OP
    STORE CURR_LED_VALUE
    STORE CURR_OUT
    STORE CURR_MODE
    STORE CURR_CTRL
    CALL DISPLAY_LEDS
    CALL DISPLAY_OP
    CALL DISPLAY_OUT
OUTPUTS:
	IN SWITCHES ; Check if SW0 is active
    AND BIT0_MASK
    ADDI -1
    JZERO OUTPUTS_B ; When SW0 is active show output B
	LOADI LED_OUTA
    STORE CURR_LED_VALUE
    LOAD OUT_A
    STORE CURR_OUT
    JUMP OUTPUTS_D
OUTPUTS_B:
    LOADI LED_OUTB
    STORE CURR_LED_VALUE
    LOAD OUT_B
    STORE CURR_OUT
OUTPUTS_D:
    CALL DISPLAY_LEDS
    CALL DISPLAY_OUT
    CALL CHECK_SW9
    JZERO SET_MODE ; If switch 9 is on, go to set mode
    JUMP OUTPUTS ; If switch 9 is not on, continue looping outputs
    
SET_MODE:    
    LOADI LED_SETM
    STORE CURR_LED_VALUE
    CALL DISPLAY_LEDS
	CALL CHECK_SW9
    JNZ MODE_CONFIRMED ; When switch 9 is lowered go to mode confirmed
    JUMP SET_MODE
    
MODE_CONFIRMED: 
    IN SWITCHES
    AND CURR_OP_MASK
    STORE CURR_MODE
    ADDI -8
    JZERO OUTPUTS ; If the next mode to go to is outputs should not wait for 9 to go back up
    LOAD CURR_MODE ; If the next mode is clearing, should not wait for 9 to go back up
    ADDI -64 ; I think both -128 and -256 are too big for immediate
    ADDI -64
    ADDI -64
    ADDI -64
    JZERO CLEAR
    JUMP WAITING
    
SET_ARG_A:
	LOADI LED_SETA
    STORE CURR_LED_VALUE
    CALL DISPLAY_LEDS
    IN SWITCHES
    AND CURR_OP_MASK
    OUT Hex0
    CALL CHECK_SW9
    JNZ ARG_A_CONFIRMED ; When switch 9 is lowered go to arg a confirmed
    JUMP SET_ARG_A
    
ARG_A_CONFIRMED:
	LOADI 0
    STORE CURR_MODE
	IN SWITCHES
    AND CURR_OP_MASK
    STORE ARG_A
    JUMP WAITING
    
SET_ARG_B:
	LOADI LED_SETB
    STORE CURR_LED_VALUE
    CALL DISPLAY_LEDS
    IN SWITCHES
    AND CURR_OP_MASK
    OUT Hex0
    CALL CHECK_SW9
    JNZ ARG_B_CONFIRMED ; When switch 9 is lowered go to arg b confirmed
    JUMP SET_ARG_B

ARG_B_CONFIRMED:
	LOADI 0
    STORE CURR_MODE
	IN SWITCHES
    AND CURR_OP_MASK
    STORE ARG_B
    JUMP WAITING
	
SET_OP:
	LOADI LED_SETOP
    STORE CURR_LED_VALUE
    CALL DISPLAY_LEDS
    IN SWITCHES
    AND CURR_OP_MASK
    OUT Hex0
    CALL CHECK_SW9
    JNZ OP_CONFIRMED ; When switch 9 is lowered go to op confirmed
    JUMP SET_OP

OP_CONFIRMED:
	LOADI 0
    STORE CURR_MODE
	IN SWITCHES
    AND CURR_OP_MASK
    STORE CURR_OP
    JUMP RUN_OP


; 1: ADD
; 2: SUB
; 4: MULT
; 5: MULT_UNSIGNED
; 8: DIV
; 9: DIV_UNSIGNED
; 16: SQRT
; 32: SIN/COS
RUN_OP: ; Logic for running the correct operation
	LOADI 0
    OUT Hex0
    CALL DISPLAY_OP
    LOAD CURR_OP
    ADDI -1
    JZERO OP_ADD
    LOAD CURR_OP
    ADDI -2
    JZERO OP_SUB
    LOAD CURR_OP
    ADDI -4
    JZERO OP_MULT
    LOAD CURR_OP
    ADDI -5
    JZERO OP_MULT
    LOAD CURR_OP
    ADDI -8
   	JZERO OP_DIV
    LOAD CURR_OP
    ADDI -9
    JZERO OP_DIV
    LOAD CURR_OP
    ADDI -16
    JZERO OP_SQRT
    LOAD CURR_OP
    ADDI -32
    JZERO OP_CORDIC
    JUMP MODE_ERROR ; If an invalid op is selected it just goes to error and locks-up
    
WAITING: ; Wait for switch 9 to be turned back on before continuing
	LOADI 0
    STORE CURR_LED_VALUE
    OUT Hex0
    CALL DISPLAY_LEDS
    CALL CHECK_SW9
    JZERO GO_NEXT ; When SW9 is up go to the next mode
    JUMP WAITING
    
GO_NEXT: ; Logic for deciding what mode was selected and jumping accordingly
    LOAD CURR_MODE
    JZERO SET_MODE
    ADDI -1
    JZERO SET_ARG_A
    LOAD CURR_MODE
    ADDI -2
    JZERO SET_ARG_B
    LOAD CURR_MODE
    ADDI -4
    JZERO SET_OP
    JUMP MODE_ERROR ; If an invalid mode is selected it just goes to error and locks-up
    
    
    

CHECK_SW9: ; AC = 0 IF SW9 = 1
	IN Switches
    SHIFT -9
    AND BIT0_MASK
    ADDI -1
    RETURN
    
READ_STATUS: ; Read the status from the status register into AC
	IN CTRL/STATUS
    AND STATUS_MASK
    RETURN

SET_CTRL:	
	LOAD CURR_CTRL
	RETURN
    
CHECK_DONE:
	CALL READ_STATUS
    JZERO OUTPUTS
    RETURN
    
DELAY:
	OUT Timer
DELAY_L:
	IN Timer
    ADDI -10
    JNEG DELAY_L
DELAY_E:
	RETURN
	
DISPLAY_LEDS:
	LOAD CURR_LED_VALUE
    OUT LEDs
    RETURN
    
DISPLAY_OP:
	LOAD CURR_OP
	OUT Hex1
    RETURN
    
DISPLAY_OUT:
	LOAD CURR_OUT
    OUT Hex0
    RETURN

LED_WORKING_LOOP:
	CALL CHECK_DONE
	LOADI 16
    STORE CURR_LED_VALUE
    CALL DISPLAY_LEDS
    CALL DELAY
    CALL CHECK_DONE
    LOADI 8
    STORE CURR_LED_VALUE
    CALL DISPLAY_LEDS
    CALL DELAY
    CALL CHECK_DONE
    LOADI 4
    STORE CURR_LED_VALUE
    CALL DISPLAY_LEDS
    CALL DELAY
    CALL CHECK_DONE
    LOADI 2
    STORE CURR_LED_VALUE
    CALL DISPLAY_LEDS
    CALL DELAY
    CALL CHECK_DONE
    LOADI 1
    STORE CURR_LED_VALUE
    CALL DISPLAY_LEDS
    CALL DELAY
    CALL CHECK_DONE
    JUMP LED_WORKING_LOOP

EXIT_WORKING_LOOP:
	LOAD CURR_OP
    ADDI -4
    JZERO RES_MULT
    LOAD CURR_OP
    ADDI -5
    JZERO RES_MULT
    LOAD CURR_OP
    ADDI -8
    JZERO RES_DIV
    LOAD CURR_OP
    ADDI -9
    JZERO RES_DIV
    LOAD CURR_OP
    ADDI -16
    JZERO RES_SQRT
    LOAD CURR_OP
    ADDI -32
    JZERO RES_CORDIC
    JUMP MODE_ERROR ; If somehow invalid op happens then give up and explode

RES_MULT:
	; check for overflow
    IN LO
    STORE OUT_A
    IN HI
    STORE OUT_B
    JUMP OUTPUTS
    
RES_DIV:
	CALL READ_STATUS
    ADDI -2
    JZERO MODE_ERROR ; If ST_DIV0 is raised go to error 
    IN QUO
    STORE OUT_A
    IN REM
    STORE OUT_B
    JUMP OUTPUTS

RES_SQRT:
	IN SQR_OU
    STORE OUT_A
    JUMP OUTPUTS

RES_CORDIC:
	IN SIN
    STORE OUT_A
    IN COS
    STORE OUT_B

LOAD_ARGS:
	LOAD ARG_A
    OUT ARG_AIO
    LOAD ARG_B
    OUT ARG_BIO
    RETURN

OP_ADD:
	LOAD ARG_A
    ADD ARG_B
    STORE OUT_A
	JUMP OUTPUTS
    
OP_SUB:
	LOAD ARG_A
    SUB ARG_B
    STORE OUT_A
	JUMP OUTPUTS
    
OP_MULT: 
	CALL LOAD_ARGS
    LOAD CURR_OP
    ADDI -4
    JZERO OP_MULTS ; Jump to perform signed multiplication
    LOADI 1
    STORE CURR_CTRL
    CALL SET_CTRL ; This will start the peripheral
	JUMP OP_MULT_C
OP_MULTS:
	LOADI 5
    STORE CURR_CTRL
    CALL SET_CTRL ; This will start the peripheral for signed mult
OP_MULT_C:
    JUMP LED_WORKING_LOOP
    
OP_DIV: 
	CALL LOAD_ARGS
    LOAD CURR_OP
    ADDI -8
    JZERO OP_DIVS
    LOADI 3
    STORE CURR_CTRL
    CALL SET_CTRL ; This will start the peripheral
    JUMP OP_DIV_C
OP_DIVS:
	LOADI 7
    STORE CURR_CTRL
    CALL SET_CTRL ; This will start the peripheral
OP_DIV_C:
	JUMP LED_WORKING_LOOP
    
OP_SQRT:
	LOAD ARG_A
    OUT ARG_AIO
    LOADI 8
    STORE CURR_CTRL
    CALL SET_CTRL ; This will start the peripheral
    JUMP LED_WORKING_LOOP
    
OP_CORDIC:
	LOAD ARG_A
    OUT ARG_AIO
	LOADI 16
    STORE CURR_CTRL
    CALL SET_CTRL ; This will start the peripheral
	JUMP LED_WORKING_LOOP
    
MODE_ERROR:
	LOAD LED_ERROR
    STORE CURR_LED_VALUE
    CALL DISPLAY_LEDS
    CALL DELAY
    LOADI 0
    STORE CURR_LED_VALUE
    CALL DISPLAY_LEDS
    CALL DELAY
    JUMP MODE_ERROR
    
; Memory constants/masks
ARG_A: DW 0
ARG_B: DW 0
OUT_A: DW 0
OUT_B: DW 0
CURR_OP: DW 0
CURR_OP_MASK: DW &H01FF
BIT0_MASK: DW &H0001
STATUS_MASK: DW &H00E0
CURR_CTRL: DW 0
CURR_OUT: DW 0
CURR_MODE: DW 0

; LED Constants
CURR_LED_VALUE: DW 0
LED_SETA: EQU 001
LED_SETB: EQU 002
LED_OUTA: EQU 008
LED_OUTB: EQU 016
LED_SETM: EQU 513
LED_SETOP: EQU 004
LED_ERROR: DW &H03FF

; IO address constants
Switches:  EQU 000
LEDs:      EQU 001
Timer:     EQU 002
Hex0:      EQU 004
Hex1:      EQU 005

CTRL/STATUS: EQU &H90
ARG_AIO:     EQU &H92
ARG_BIO:     EQU &H93
LO:        EQU &H94
HI:        EQU &H95
QUO:       EQU &H96
REM:       EQU &H97
SQR_OU:    EQU &H98
SIN:        EQU &H99
COS:        EQU &H9A