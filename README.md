# BiSS-C Encoder Emulator

An FPGA encoder emulator that receives the MA clock from a BiSS master and
returns rotary position data on SLO. The repository contains synthesizable
VHDL for Intel/Altera MAX 10, a Quartus Prime project, and a separate bare-metal
C reference core for a dedicated TI AM6442 R5F.

**Status: development prototype.** Standard and safety FPGA revisions compile
and meet the constrained internal 75 MHz timing checks. Frame-engine simulation
passes for both formats. Board integration, external timing constraints, and
hardware measurements are still required.

## Features and scope

The implemented FPGA core provides:

- A 64-bit fixed-point motion accumulator with forward/reverse motion and
  position preload.
- Configurable single-turn (18–32 bits) and multi-turn (0–12 bits) fields.
- Standard point-to-point BiSS-C process-data serialization and inverted CRC-6
  using polynomial `0x43`.
- Compile-time BiSS Safety selection: CPW with CRC-6, SPW with CRC-16, and a
  six-bit Sign-of-Life counter. `G_SAFETY_MODE=false` selects standard frames;
  `true` selects safety frames. No runtime mode switch is present.
- Position snapshot at frame start, MA synchronization, frame timeout handling,
  and completed/aborted frame counters.
- Error, warning, and bad-CRC fault injection controls.

The design targets a 75 MHz FPGA clock, MA rates of 1, 2, 5, and 10 MHz, and
rotation speeds of 1–10 revolutions per second. These are design targets;
complete interface timing and hardware measurements are pending.

The documented frame sequence is:

```text
LAT, ACK=0, STR=1, CDS=0, MT, ST, nE, nW, inverted CRC-6, STP=0
```

Multi-turn data is omitted when its configured width is zero. Position and CRC
fields are transmitted most-significant bit first.

## Repository layout

| Path | Purpose |
| --- | --- |
| `rtl/` | VHDL package, motion generator, frame engine, and top-level entity |
| `r5f/` | Bare-metal C reference core and platform-porting instructions |
| `biss_emulator.qpf` | Quartus project entry point |
| `biss_emulator.qsf` | Device, source files, and virtual-pin assignments |
| `biss_emulator_safety.qsf` | Safety revision with a 24 ST / 12 MT SPW |
| `biss_emulator.sdc` | 75 MHz clock constraint and asynchronous MA exception |
| `sim/` | Self-checking VHDL frame testbench and ModelSim/Questa runner |
| `BISS_EMULATOR_*.md` | User guide, design requirements, and planned interfaces |
| `output_files/` | Generated compilation reports and programming files; ignored by Git |

## Build the FPGA project

Install Quartus Prime Lite with MAX 10 device support. The full compile was
run with Quartus Prime Lite **25.1std.0 Build 1129**.

```powershell
git clone https://github.com/Ala-Ismail/BiSSC-Emulator.git
cd BiSSC-Emulator
quartus_sh --flow compile biss_emulator -c biss_emulator
# Build the safety revision separately:
quartus_sh --flow compile biss_emulator -c biss_emulator_safety
```

If Quartus is not on PATH, invoke its executable directly. For the local 25.1
installation used for this project:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe' --flow compile biss_emulator -c biss_emulator
```

Alternatively, open `biss_emulator.qpf` in Quartus and select **Processing →
Start Compilation**. The top-level entity is `biss_emulator_top`.

### Current compile result

The compile on 8 November 2026 produced:

| Check | Standard | Safety (SPW 24 ST / 12 MT) |
| --- | --- | --- |
| Full compilation | 0 errors, 3 warnings | 0 errors, 3 warnings |
| Logic elements (of 49,760) | 731 | 845 |
| Registers | 275 | 310 |
| Worst setup slack at 75 MHz | +3.349 ns | +3.246 ns |

These results cover the provisional device and constrained internal paths.
The earlier whole-word combinational CRC implementation failed timing; the
current serializer accumulates CRC state as protected bits are transmitted.
Inspect `output_files/biss_emulator.flow.rpt`, `biss_emulator.fit.summary`,
`biss_emulator.sta.summary`, and `biss_emulator.sta.rpt` after rebuilding.
Safety reports have prefix `biss_emulator_safety` under `output_files/safety/`.
Warnings concern LogicLock licensing and incomplete pin assignments. External
interface timing is not fully constrained; positive internal slack does not
establish timing at a connected master's pins.

### Device and board setup

The project uses **10M50DAF484C7G** as a provisional MAX 10 target.
Configuration and status signals use virtual pins; clock, reset, MA, and SLO
are automatically placed for compilation. The project does not yet provide a
board control interface.

Before programming hardware:

1. Select the actual FPGA device and package.
2. Set pin locations and I/O standards from the board schematic.
3. Connect the active configuration/status ports to board logic or a control
   wrapper.
4. Complete external timing constraints and check timing for the actual board.
5. Verify the MA/SLO electrical interface and measure timing at the board pins.

MA is asynchronous to the FPGA clock and is synchronized internally; it is not
a second RTL clock. RS-422 signals require suitable receivers/drivers and must
not connect directly to FPGA I/O.

## Configure the emulator

The current top level exposes `cfg_*` inputs directly. The serializer captures
position, widths, fault controls, and timeout at LAT for the entire frame.
Atomic host updates and motion configuration validation are part of the planned
register interface; configure controls while disabled and idle.

For a 24-bit single-turn, 12-bit multi-turn encoder at 5 revolutions per second:

| Input | Value |
| --- | --- |
| `cfg_st_bits` | `24` |
| `cfg_mt_bits` | `12` |
| `cfg_phase_increment` | `0x0000011E54C67285` |
| `cfg_timeout_ticks` | `1500` (20 µs at 75 MHz) |
| `cfg_direction_neg` | `0` for forward; `1` for reverse |
| `cfg_force_error`, `cfg_force_warning`, `cfg_force_bad_crc` | `0` for a healthy frame |

Disable responses with `cfg_enable=0` while setting up. Set the position
preload inputs, pulse `cfg_load_position` for one FPGA clock, then set
`cfg_enable=1`. Position continues moving while responses are disabled.

Speed magnitude is calculated as:

```text
phase_increment = round(speed_rps × 2^64 / 75,000,000)
```

See the [user guide](BISS_EMULATOR_USER_GUIDE.md) for all top-level controls,
speed examples, frame checks, and fault-injection procedures.

### Select BiSS Safety at compile time

Set these generics on `biss_emulator_top` (forwarded to `biss_frame_engine`):

| Generic | Default | Purpose |
| --- | --- | --- |
| `G_SAFETY_MODE` | `false` | Standard or CPW+SPW frame selection |
| `G_SPW_ST_BITS` | `18` | SPW single-turn width, 1–32 bits |
| `G_SPW_MT_BITS` | `0` | SPW multi-turn width, 0–12 bits |

In a safety build, SPW ST+MT must be at most 40 bits and each field must fit
its corresponding CPW field. SPW widths are fixed at compile time. The supplied
safety revision uses 24 ST / 12 MT; configure CPW for at least those widths.

```text
LAT, ACK=0, STR=1, CDS=0,
CPW_MT, CPW_ST, nE, nW, inverted CRC6,
SPW_MT, SPW_ST, nE, nW, LC[5:0], inverted CRC16, STP=0
```

Both words use one position/fault snapshot. SPW transmits the leading requested
bits of CPW's MT and ST fields. CRC16 uses polynomial `0x190D9`, initial zero,
and covers SPW position, status, and LC. LC starts at 1 and wraps from 63 to 1;
each accepted LAT consumes a value, including frames later aborted. Bad-CRC
injection flips the final bit of both CRCs. Incompatible CPW widths or zero
timeout reject a start without consuming LC.

See [the safety setup guide](BISS_EMULATOR_USER_GUIDE.md#11-biss-safety-option)
for Quartus generic assignments, mapping, and validation rules.

## R5F reference core

**Not maintained.** The R5F implementation is retained for reference only.
Active development and verification focus on the FPGA RTL; R5F does not
receive new features or fixes and does not support BiSS Safety.

The C implementation in `r5f/` is intended for functional logic checking at
**1 MHz MA** on a dedicated AM6442 R5F. It needs a board-specific timer and
direct GPIO access in a tight polling loop, with the loop and emulator code
placed in TCM. No complete board firmware project or platform driver is
included.

See [R5F setup and limitations](r5f/README.md) before integrating it.

## Verification and remaining work

Run the self-checking frame-engine regression with ModelSim/Questa on PATH:

```powershell
./sim/run.ps1
```

It checks standard mode and five safety configurations against independent
polynomial-division CRC references, including supported MA rates, CPW widths,
SPW boundary widths, life-counter rollover, fault injection, coherent frame
snapshots, abort/recovery, disabled/invalid starts, and reset. An expected-failure
test checks rejection of an oversized SPW. See [simulation coverage](sim/README.md).
This is functional RTL verification; it does not establish board timing or
safety certification.

Remaining work includes:

- Completing board-specific constraints and measuring external MA/SLO timing.
- Extending verification to long-duration motion, position wraps, and direction changes.
- Implementing the documented shadow/active configuration register bank.
- Integrating optional Quartus In-System Sources and Probes debug IP.
- Implementing EDS/profile discovery and validating against a physical safety master.

BiSS Safety here emulates process-data communication using a shared motion
source. It does not provide independent redundant sensing or a safety function.
This project is not safety certified. The R5F reference remains standard mode only.

## Documentation

| Document | Contents |
| --- | --- |
| [User guide](BISS_EMULATOR_USER_GUIDE.md) | Setup, controls, speed calculations, and bench checks |
| [FPGA design](BISS_EMULATOR_FPGA_DESIGN.md) | Architecture, requirements, and verification acceptance criteria |
| [Register interface](BISS_EMULATOR_REGISTER_INTERFACE.md) | Planned host registers and configuration update behavior |
| [Quartus debug](BISS_EMULATOR_QUARTUS_DEBUG.md) | Planned JTAG controls and Signal Tap workflow |
| [RTL status](rtl/README.md) | Current RTL integration and compilation notes |
| [Simulation guide](sim/README.md) | Running the regression and its coverage limits |
| [R5F guide](r5f/README.md) | Bare-metal reference core integration |

## License

No license file is currently included in this repository.
