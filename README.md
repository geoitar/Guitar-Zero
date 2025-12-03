## FPGA Rhythm Game (Final Project)
### DE1-SoC FPGA | Digital Systems Design  
### AuthorS: Ashton Geoit and Naveen Gnanavelan

## Table of Contents
1. High-Level Problem Description  
2. Background Information  
3. System Design Overview  
4. Hardware Description  
5. Software / Verilog Architecture  
6. Gameplay Logic  
7. Results  
8. Conclusion  
9. Media Documentation  
10. Citations & Inspirations  

## Problem Description
The purpose of this project was to design and implement a real-time rhythm game
(Guitar Hero-style) fully in Verilog on the DE1-SoC FPGA.

The system needed to:
- Generate a 640×480 VGA signal in hardware  
- Draw four note lanes with falling notes  
- Detect timing accuracy (OK, Good, Perfect)  
- Use scoring and dynamic difficulty  
- Include a 3-minute countdown with a win/lose condition  

## Background Information
Several core digital-design concepts were required:

### VGA Timing  
The project uses a 25 MHz pixel clock, horizontal/vertical counters, sync pulses,
and active region detection to display 640×480 at 60 Hz.

### Hardware-Based Rendering  
Every pixel is computed in real time inside an always@(*) block.
The circuit computes colors as the VGA beam scans.

### Frame-Tick Timing  
Game logic updates once per frame (~60 Hz) at the top-left pixel.

### Note Objects  
Falling notes are modeled as a pool of objects with Y-position, active flag,
lane assignment, and removal on hit or miss.

### User Input  
Pushbuttons must be edge-detected (rising edges) to register single presses.

### Game Mechanics  
Difficulty escalates as the score rises.  
A timer ensures the game ends after 3 minutes, and the score bar must reach 100%.

## Hardware Description

### Board
DE1-SoC FPGA development board
50 MHz system clock

### Inputs
- KEY0–KEY3: gameplay buttons
- SW9: reset (flip on and off)

### Outputs
- VGA: R, G, B, HSYNC, VSYNC, BLANK, SYNC, CLOCK  
- LEDR: button visualizer
- PFM: Incoprporated initially but we removed it due to issues trying to incorpoarte the audio

### Physical Gameplay Interface
The game is played using the four pushbuttons on the DE1-SoC FPGA board and displayed on any VGA monitor.

## Verilog Architecture

All project logic is contained inside a single Verilog file:  
`top.v`

Modules inside `top.v` include:

### VGA Timing Block
- Generates sync pulses
- Produces 25 MHz clock
- Tracks pixel coordinates on screen

### Frame Update FSM
- Runs gameplay logic once per frame
- Updates falling notes
- Updates score, timer, spawn logic

### Note Pool Manager
- Stores up to 16 notes at the same time  
- Handles spawning, movement, removal, and hit testing  

### Combo System
- Tracks when the player makes consecutive hits  
- Applies a multiplier:
  - 10 hits → 1.1×
  - 20 hits → 1.2×

### Rendering Engine
Draws:
- Lanes
- Notes
- Score bar (right-hand side)
- Combo bar (left-hand side)
- 100% target line (faded gray line above score bar)
- Timer bar (top)
- End-of-game “END” text

## Gameplay Logic

### Timing Zones
The hit window includes:
- Perfect zone (WHITE STRIPE)
- Good zone (YELLOW STRIPES)
- OK zone (DARK BLUE STRIPES)
- Miss (ELSEWHERE)

### Scoring
Base values:
- Perfect = +2  
- Good = +1  
- OK = 0  

Combo multiplier:
- Combo ≥ 10 Consecutive Hits → ×1.1  
- Combo ≥ 20 Consecutive Hits → ×1.2  

Misses or mis-presses deduct 2 points and reset the combo.

### Difficulty
Score < 33% → slow notes  
Score 33–66% → medium speed  
Score > 66% → fast speed  

Spawn rate also increases.

### Win Condition
Fill score bar fully before the 3-minute timer expires.
Needs 255 Points (8-bit)

### Lose Condition
Timer on the top reaches zero before bar fills (lack of completion after 3 minutes).

### End Screen
Displays a large “END” in:
- Green (win)  
- Red (lose)  

## Results

### Display Output
The VGA output is stable at 640×480@60Hz.  
All lanes, falling notes, hit windows, score bar, combo logic, and the timer bar render correctly.

### Gameplay
Gameplay difficulty scales a little choppy but fairly smooth for the application of this game.  
Dynamic button pressing according to bllock generation. The game operates as intended, creating hit blocks at pseudo-random frequency where the player may have to make consecutive hits on the same color.

### Performance
No timing violations occured during compilation or operation of the game.
The system runs indefinitely without instability (at least up to 3 minutes).

### Achievements
- Fully hardware-driven game  
- Real-time rendering  
- Realistic note behavior  
- Accuracy detection  
- Combo multiplier  
- End-game logic 

## Conclusion

This final project demostrates a real-time interactive game implemented in Verilog. All of the gaming mechanics, timing, and logic are hardware-ciontrolled without the use of a CPU or external software.

This design is manipulable and extendable for ofuture rework or redesign. In terms of this project we were unable to find an appropriate device to output sound so some future improvement could be:
- Audio playback  
- Hold notes (Typ. in Guitar Hero)  
- Menu interface
- Custom songs
- Difficulty presets/selection

This final project showcases:
- VGA generation  
- FSM-based game logic  
- Real-time signal processing  
- Hardware optimization  
- ECE 287 Practices

## Media Documentation

Embedded YouTube demo of the project:
[https://youtu.be/rTtvYkgnA-M]

Pictures:
- Refer to repository
- 
## Citations & Inspirations

### Lane/Note Concept
Concept inspired by rhythm games including Guitar Hero and Piano Tiles

### Code Assistance
Heavy implementation and assistance from ChatGPT for general project structure.

