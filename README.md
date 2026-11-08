# BiSS-C Encoder Emulator

An FPGA encoder emulator that receives the MA clock from a BiSS master and
returns rotary position data on SLO. The repository contains synthesizable
VHDL for Intel/Altera MAX 10, a Quartus Prime project, and a separate bare-metal
C reference core for a dedicated TI AM6442 R5F.

**Status: development prototype.** The FPGA project compiles, but does not yet
meet its 75 MHz timing constraint. Board integration and automated simulation
are still required before relying on it in hardware.

## Features and scope

The implemented FPGA core provides:

- A 64-bit fixed-point motion accumulator with forward/reverse motion and
  position preload.
- Configurable single-turn (18–32 bits) and multi-turn (0–12 bits) fields.
- Standard point-to-point BiSS-C process-data serialization and inverted CRC-6
  using polynomial `0x43`.
- Position snapshot at frame start, MA synchronization, frame timeout handling,
  and completed/aborted frame counters.
- Error, warning, and bad-CRC fault injection controls.

The design targets a 75 MHz FPGA clock, MA rates of 1, 2, 5, and 10 MHz, and
rotation speeds of 1–10 revolutions per second. These are design targets;
timing closure and hardware measurements are pending.

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
| `biss_emulator.sdc` | 75 MHz clock constraint and asynchronous MA exception |
| `BISS_EMULATOR_*.md` | User guide, design requirements, and planned interfaces |
| `output_files/` | Generated compilation reports and programming files; ignored by Git |

## Build the FPGA project

Install Quartus Prime Lite with MAX 10 device support. The full compile was
run with Quartus Prime Lite **25.1std.0 Build 1129**.

```powershell
git clone https://github.com/Ala-Ismail/BiSSC-Emulator.git
cd BiSSC-Emulator
quartus_sh --flow compile biss_emulator
```

If Quartus is not on PATH, invoke its executable directly. For the local 25.1
installation used for this project:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe' --flow compile biss_emulator
```

Alternatively, open `biss_emulator.qpf` in Quartus and select **Processing →
Start Compilation**. The top-level entity is `biss_emulator_top`.

### Current compile result

The compile on 8 November 2026 produced:

| Check | Result |
| --- | --- |
| Synthesis, fitting, and assembly | Successful |
| Full compilation | 0 errors, 10 warnings |
| Logic elements | 1,380 of 49,760 (3%) |
| Registers | 237 |
| Worst setup slack at 75 MHz | **−18.195 ns — timing failed** |

Successful compilation does not establish that the design operates at 75 MHz.
Inspect `output_files/biss_emulator.flow.rpt`, `biss_emulator.fit.summary`,
`biss_emulator.sta.summary`, and `biss_emulator.sta.rpt` after rebuilding.
External interface timing is not fully constrained.

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
4. Complete external timing constraints and resolve the setup timing failures.
5. Verify the MA/SLO electrical interface and measure timing at the board pins.

MA is asynchronous to the FPGA clock and is synchronized internally; it is not
a second RTL clock. RS-422 signals require suitable receivers/drivers and must
not connect directly to FPGA I/O.

## Configure the emulator

The current top level exposes `cfg_*` inputs directly. Keep configuration
stable during a frame; atomic configuration updates are part of the planned
register interface.

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

## R5F reference core

The C implementation in `r5f/` is intended for functional logic checking at
**1 MHz MA** on a dedicated AM6442 R5F. It needs a board-specific timer and
direct GPIO access in a tight polling loop, with the loop and emulator code
placed in TCM. No complete board firmware project or platform driver is
included.

See [R5F setup and limitations](r5f/README.md) before integrating it.

## Verification and remaining work

There is currently **no simulation testbench, simulator project, or automated
test suite** in this repository. Quartus compilation checks synthesis, fitting,
assembly, and static timing; it does not validate protocol behavior.

Remaining work includes:

- Closing 75 MHz timing and completing board-specific constraints.
- Adding a behavioral BiSS master testbench and independent CRC reference checks.
- Verifying position wraps, direction changes, timeouts, reset behavior, and
  fault injection.
- Implementing the documented shadow/active configuration register bank.
- Integrating optional Quartus In-System Sources and Probes debug IP.
- Implementing the optional BiSS Safety CPW/SPW serializer and its verification.

BiSS Safety behavior described in the design documents is planned functionality.
This project is not safety certified.

## Documentation

| Document | Contents |
| --- | --- |
| [User guide](BISS_EMULATOR_USER_GUIDE.md) | Setup, controls, speed calculations, and bench checks |
| [FPGA design](BISS_EMULATOR_FPGA_DESIGN.md) | Architecture, requirements, and verification acceptance criteria |
| [Register interface](BISS_EMULATOR_REGISTER_INTERFACE.md) | Planned host registers and configuration update behavior |
| [Quartus debug](BISS_EMULATOR_QUARTUS_DEBUG.md) | Planned JTAG controls and Signal Tap workflow |
| [RTL status](rtl/README.md) | Current RTL integration and compilation notes |
| [R5F guide](r5f/README.md) | Bare-metal reference core integration |

## License

No license file is currently included in this repository.
