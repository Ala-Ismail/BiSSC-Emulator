# BiSS Emulator User Guide

## 1. What this project does

The BiSS Emulator is an FPGA implementation for emulating a rotary BiSS-C encoder. It accepts the MA clock from a BiSS master and returns position data on SLO.

The configured operating range is:

| Feature | Range |
| --- | --- |
| FPGA clock | 75 MHz |
| MA clock | 1, 2, 5, or 10 MHz |
| Single-turn position | 18 to 32 bits |
| Multi-turn position | 0 to 12 bits |
| Rotation speed | 1 to 10 revolutions per second |
| Direction | Positive or negative |

The normal output frame is:

~~~
LAT, ACK=0, STR=1, CDS=0, MT, ST, nE, nW, inverted CRC-6, STP=0
~~~

MT is omitted when its configured width is zero. Position bits and CRC bits are sent most-significant bit first. The normal CRC is six bits using polynomial 0x43 and an initial value of zero.

## 2. Hardware required

You need:

- An Altera/Intel MAX 10 FPGA board with a stable 75 MHz clock.
- A JTAG programming connection compatible with Quartus Prime.
- A BiSS master or drive configured for 1, 2, 5, or 10 MHz MA.
- An electrical interface between the FPGA and master. BiSS installations commonly use RS-422 line receivers/drivers; do not connect an RS-422 signal directly to ordinary FPGA pins.
- A board-specific pin plan for clock, MA receiver output, SLO driver input, JTAG, and I/O supply banks.

The exact MAX 10 device/package and board schematic are required before creating final pin assignments or timing constraints.

## 3. Current RTL implementation status

The current RTL supports standard BiSS-C or a BiSS Safety process-data frame,
selected at elaboration with `G_SAFETY_MODE`:

| Block | Status |
| --- | --- |
| Fixed-point motion generator | Implemented |
| Configurable ST/MT width inputs | Implemented |
| Positive and negative motion | Implemented |
| Standard BiSS-C process-data serializer | Implemented |
| CRC-6, E/W status, timeout and counters | Implemented |
| Host register bus wrapper | Pending integration |
| Quartus In-System Sources and Probes wrapper | Pending generation/integration |
| BiSS Safety CPW/SPW serializer | Implemented; compile-time generic selection |
| MAX 10 project and 75 MHz SDC | Included; device is provisional, board pins and interface timing pending |

The top-level currently exposes active configuration signals directly. This allows the core to be connected to external board logic or a temporary test wrapper while the documented register and JTAG wrappers are added.

## 4. Quartus project setup

Open `biss_emulator.qpf` to use the included compile-check project, or run
`quartus_sh --flow compile biss_emulator -c biss_emulator` from the repository root. Its
10M50DAF484C7G target is provisional. Configuration/status ports are virtual;
clock/reset/MA/SLO are automatically placed. The included SDC constrains the
75 MHz clock and cuts the asynchronous MA path to its first synchronizer stage.
External input/output delays remain unspecified until board timing is known.
Do not program a board with this project until its device, pins, I/O standards,
and external timing constraints have been checked against the board schematic.

For a board-specific project:

1. Create a Quartus Prime project for the exact MAX 10 part.
2. Add every VHDL file in the rtl directory. Compile order is:
   1. biss_emulator_pkg.vhd
   2. biss_motion_generator.vhd
   3. biss_frame_engine.vhd
   4. biss_emulator_top.vhd
3. Set biss_emulator_top as the top-level entity.
4. Add an SDC file with a 75 MHz clock constraint:

   ~~~
   create_clock -name clk_75m -period 13.333 [get_ports {clk_75m}]
   ~~~

5. Add board-specific pin locations and I/O standards only after checking the schematic.
6. Compile, inspect the Timing Analyzer report, and program through JTAG.

MA is asynchronous to clk_75m and is synchronized internally. Do not create MA as a second FPGA clock domain.

## 5. Connecting the top-level controls

The current top-level active-control inputs are listed below.

| Input | Meaning |
| --- | --- |
| cfg_enable | Enable SLO responses. Position continues moving when disabled. |
| cfg_direction_neg | 0 positive rotation; 1 negative rotation. |
| cfg_st_bits | Single-turn width, 18 to 32. |
| cfg_mt_bits | Multi-turn width, 0 to 12. |
| cfg_phase_increment | 64-bit speed magnitude. |
| cfg_timeout_ticks | Static timeout in 75 MHz clock ticks. |
| cfg_force_error | Sends nE=0. |
| cfg_force_warning | Sends nW=0. |
| cfg_force_bad_crc | Deliberately corrupts the final transmitted CRC bit. |
| cfg_load_position | One 75 MHz-clock pulse to load the two position inputs. |
| cfg_position_st | 32-bit single-turn preload. |
| cfg_position_mt | 12-bit multi-turn preload. |

The outputs status_position_st and status_position_mt expose live motion state. status_frame_count and status_abort_count are useful for confirming communications.

## 6. Configuring speed

The motion generator requires a 64-bit phase increment:

~~~
phase_increment = round(speed_rps * 2^64 / 75,000,000)
~~~

Examples:

| Speed | Decimal phase increment | Hexadecimal |
| --- | ---: | --- |
| 1 rev/s | 245,956,587,649 | 0x000000394427B081 |
| 5 rev/s | 1,229,782,938,245 | 0x0000011E54C67285 |
| 10 rev/s | 2,459,565,876,490 | 0x0000023CA98CE50A |

Use the magnitude above for either direction. Select reverse motion with cfg_direction_neg instead of using a negative phase increment.

## 7. Example normal-encoder setup

This example emulates a 24-bit single-turn, 12-bit multi-turn encoder at 5 rev/s.

1. Set cfg_enable to 0 while changing configuration.
2. Set cfg_st_bits to 24 and cfg_mt_bits to 12.
3. Write 0x0000011E54C67285 to cfg_phase_increment.
4. Set cfg_timeout_ticks to 1500, giving a 20 us static timeout.
5. Set cfg_position_st and cfg_position_mt to the desired start position.
6. Pulse cfg_load_position for one 75 MHz clock.
7. Set cfg_direction_neg to 0 for forward motion.
8. Set cfg_force_error, cfg_force_warning, and cfg_force_bad_crc to 0.
9. Set cfg_enable to 1.
10. Start MA at one of the supported frequencies and verify frame_count increments.

For a reverse-direction test, set cfg_direction_neg to 1. The single-turn position decrements and the multi-turn count decrements when the position wraps through zero.

## 8. Frame checks

Use a logic analyser or Quartus Signal Tap to check this sequence:

1. The first MA rising edge is LAT and snapshots the position.
2. The next MA rising edge produces ACK=0.
3. The following edges produce STR=1 and CDS=0.
4. MT then ST are transmitted MSB first.
5. Healthy status is nE=1 and nW=1.
6. Six inverted CRC bits follow.
7. STP=0 follows the CRC.
8. When MA stops, SLO rises after the configured timeout.

If the master stops MA before STP, the core abandons the incomplete frame and increments abort_count after timeout.

## 9. Quartus debug workflow

The planned MAX 10 debug wrapper uses Quartus In-System Sources and Probes for direct JTAG control and Signal Tap for observation.

When that wrapper is integrated:

1. Build with G_ENABLE_JTAG_DEBUG=true.
2. Program the FPGA through JTAG.
3. Open Tools > In-System Sources and Probes Editor.
4. Write source fields for enable, direction, resolution, speed, position, and fault injection.
5. Toggle the APPLY control to commit at an idle frame boundary.
6. Read probes for MA rate, FSM state, position snapshot, CRC values, and SLO state.
7. Use Signal Tap to capture MA and SLO during a frame.

The direct-control source-word layout is defined in BISS_EMULATOR_QUARTUS_DEBUG.md.

## 10. Fault-injection tests

Use the following tests before connecting to a real drive application:

| Test | Configuration | Expected result |
| --- | --- | --- |
| Error status | cfg_force_error=1 | nE is transmitted as 0 |
| Warning status | cfg_force_warning=1 | nW is transmitted as 0 |
| CRC failure | cfg_force_bad_crc=1 | Master reports CRC failure |
| Bad MA rate | Use a rate other than 1/2/5/10 MHz | Do not rely on communication correctness |
| Interrupted frame | Stop MA before STP | Frame abort counter increments |
| Position wrap | Start close to maximum ST count | MT changes by one at ST wrap |

## 11. BiSS Safety option

The FPGA top level and frame engine expose these VHDL generics:

| Generic | Default | Meaning |
| --- | --- | --- |
| `G_SAFETY_MODE` | `false` | `false`: standard BiSS-C; `true`: CPW followed by SPW |
| `G_SPW_ST_BITS` | `18` | SPW single-turn width, 1 to 32 |
| `G_SPW_MT_BITS` | `0` | SPW multi-turn width, 0 to 12 |

Mode and SPW widths are fixed during elaboration/synthesis. Changing them
requires rebuilding the FPGA image. There is no software or JTAG mode switch.
SPW width generics are unused in standard mode.

The `biss_emulator` Quartus revision builds standard mode. The included
`biss_emulator_safety` revision builds safety mode with 24 ST and 12 MT SPW
bits. Select the revision in Quartus, or run:

```powershell
quartus_sh --flow compile biss_emulator -c biss_emulator_safety
```

Set the top-level generics in the revision's QSF using `set_parameter`, e.g.:

```tcl
set_parameter -name G_SAFETY_MODE true
set_parameter -name G_SPW_ST_BITS 24
set_parameter -name G_SPW_MT_BITS 12
```

The safety revision requires `cfg_st_bits >= 24` and `cfg_mt_bits = 12`.
Its reports and programming files are under `output_files/safety/`.

After LAT, a safety frame transmits:

```text
ACK=0, STR=1, CDS=0,
CPW_MT, CPW_ST, nE, nW, inverted CRC6,
SPW_MT, SPW_ST, nE, nW, LC[5:0], inverted CRC16, STP=0
```

Both words use the same position and fault snapshot taken at LAT. CPW ST
contains the most significant `cfg_st_bits` bits of the full 32-bit turn;
CPW MT contains the configured low `cfg_mt_bits` bits of the turn counter.
SPW uses the leading requested bits of each CPW field. MT is omitted when
its width is zero. All fields are sent MSB first.

CRC6 covers CPW position and its nE/nW using polynomial `0x43`. CRC16 covers
SPW position, nE/nW and LC using polynomial `0x190D9`. Both start at zero and
are transmitted inverted. CRC state advances with each transmitted protected
bit; headers, the other word, and STP are excluded. Fault inputs affect both
words; `cfg_force_bad_crc` flips the last bit of each CRC.

The first accepted frame after reset transmits LC=1, followed by 2 through 63,
then 1. LC advances at each accepted LAT, including frames later aborted.
Disabled or rejected starts do not consume LC. Reset restarts the sequence.

In safety builds, SPW ST+MT must not exceed 40 bits (a static assertion rejects
larger builds), and each SPW width must be no greater than its CPW width.
Incompatible CPW widths or a zero timeout keep SLO idle and do not start a
frame. The pending register wrapper is still needed to expose a host-visible
invalid-configuration flag. Widths, timeout and fault controls are captured at
LAT, so input changes cannot alter an in-flight frame.

Run `./sim/run.ps1` with ModelSim/Questa tools on PATH to check both formats.
See [simulation instructions](sim/README.md) for coverage and tool selection.
The R5F C reference core remains standard BiSS-C only. EDS/profile register
discovery and independent redundant sensing are not implemented.

This feature is communication-format emulation only. It does not make the FPGA, board, or system safety certified.

## 12. Related documents

- BISS_EMULATOR_FPGA_DESIGN.md: design architecture and timing requirements.
- BISS_EMULATOR_REGISTER_INTERFACE.md: planned production register interface.
- BISS_EMULATOR_QUARTUS_DEBUG.md: planned MAX 10 JTAG source/probe interface.
- rtl/README.md: RTL source status.
