# SCOMP Arithmetic Coprocessor — Project Documentation

## Overview
This project implements a simple peripheral arithmetic coprocessor for the SCOMP architecture that performs four hardware-accelerated operations: 16x16 multiplication, 16÷16 division, integer square root, and CORDIC sine/cosine. These operations run much faster than their software equivalents and require no modification to the SCOMP core. All interaction occurs through the reserved I/O window 0x90–0x9F.

## Motivation
SCOMP's software math is slow, especially for repeated or advanced operations. Moving these functions to hardware provides:
- Faster execution
- A uniform peripheral API
- Support for more complex operations like sqrt and trig
- No changes to SCOMP itself

The goal is a drop-in hardware accelerator usable by any SCOMP program.

## Supported Operations
MUL: 16x16 multiply, produces 32-bit result  
DIV: 16÷16 division, produces quotient and remainder  
SQRT: Integer square root of a 16-bit value  
CORDIC: Computes sine and cosine of an input angle  

## I/O Window (0x90–0x9F)
All communication between SCOMP and the peripheral occurs through this address range. The design never drives IO_DATA outside this window.

## Hardware API and Register Map
General rules:
- 16-bit word size  
- START/BUSY/DONE protocol  
- Signed/unsigned toggle for MUL and DIV  
- STATUS read clears DONE  

Address map:

Multiplication  
A = 0x92  
B = 0x93  
LO = 0x94  
HI = 0x95  
CTRL/STATUS = 0x90

Division  
NUM = 0x92  
DEN = 0x93  
QUO = 0x96  
REM = 0x97  
CTRL/STATUS = 0x90

Square Root  
IN = 0x92  
OUT = 0x98  
CTRL/STATUS = 0x90

CORDIC (Sine/Cosine)  
ANG = 0x92  
SIN = 0x99  
COS = 0x9A  
CTRL/STATUS = 0x90

## Data Formats and Conventions
- Word size: 16-bit  
- Signed arithmetic uses 2’s complement and a mode bit for MUL/DIV  
- CORDIC uses Q-format fixed point  
  - Angle: Q9.7  
  - Sine/Cosine results: Q1.14  
- Protocol:  
  write operands → write START → wait for BUSY to clear → read result → STATUS read clears DONE  

## Architecture Summary
1. Bus interface  
   Detects reads and writes within 0x90–0x9F and exposes internal registers on reads only.

2. Register file  
   Stores operands, results, and the CTRL/STATUS register.

3. Control logic  
   START latches operands and begins computation  
   BUSY stays high during execution  
   DONE goes high when results are ready  
   Reading STATUS clears DONE (and DIV0 for division)

4. Compute engines  
   Dedicated modules for MUL, DIV, SQRT, and CORDIC.  
   Each starts on START and writes back results when finished.

5. Readback multiplexer  
   Selects the correct register output onto IO_DATA during read operations.

## Demo Plan
Calculator application running on SCOMP:
- Uses switches on the DE10 board as input  
- SW9: mode-select toggle  
- SW0–2: operation select  
- Input numbers through switches  
- Result displayed on the 7-segment display  
- Supports all four hardware operations plus add/subtract for completeness  

This demo shows the peripheral operating in a practical, interactive use case and validates that all four operations behave correctly in hardware.
