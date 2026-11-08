# BiSS-C Encoder Emulator - FPGA Design Requirements

## 1. Purpose and scope

Implement an FPGA-based **BiSS-C slave / encoder emulator**. The FPGA shall emulate a rotary absolute encoder and return a position that advances at a configurable constant rotational speed. This document defines the functional and timing architecture for an FPGA clocked at **75 MHz**.

The design is an encoder-side implementation: a BiSS master supplies the MA clock and consumes the returned SLO data. Electrical line drivers, isolation, and connector protection are outside the FPGA, but their signal polarity and timing must be preserved at the FPGA pins.

The implementation language shall be **synthesizable VHDL**. Use VHDL-2008 where supported by the selected FPGA toolchain; otherwise use portable VHDL-93 constructs. Do not use vendor-specific primitives in the protocol core. The host-facing configuration contract is defined separately in [BISS_EMULATOR_REGISTER_INTERFACE.md](BISS_EMULATOR_REGISTER_INTERFACE.md).

The target family is **Altera/Intel MAX 10** and the build flow is Quartus Prime. The exact MAX 10 orderable device and package are still required before assigning pins, I/O standards, or compiling final timing constraints.

## 2. Required operating envelope

| Item | Requirement |
| --- | --- |
| FPGA system clock | 75 MHz nominal |
| Encoder protocol | BiSS-C, encoder/slave response |
| Single-turn resolution | Configurable, integer 18-32 bits |
| Multi-turn resolution | Configurable, integer 0-12 bits; zero disables the field |
| Emulated speed | Configurable 1.0 to 10.0 revolutions/second |
| MA clock frequency | Support 1, 2, 5, and 10 MHz |
| Optional safety mode | BiSS Safety BP3S-style CPW + SPW frame generation for test/emulation |
| Rotation direction | Configurable positive or negative |
| Position behaviour | Continuous modulo-single-turn position with multi-turn carry/borrow |
| Default power-up behaviour | Position = 0, speed = 1 rev/s, positive direction, output idle/released |

The total reported position width is `single_turn_bits + multi_turn_bits` and therefore ranges from 18 to 44 bits. Internally, retain all 44 bits even if a particular BiSS device/profile transmits a smaller configured field.

## 3. Top-level architecture

```
                         75 MHz FPGA clock domain
  configuration bus --> register bank --> motion generator --> position snapshot
                                                     |                 |
  MA input --> input synchroniser / edge detector --> BiSS-C frame FSM --> SLO output
                                                     |
                                                     +--> CRC generator
```

Use a single 75 MHz clock domain for the motion generator, configuration registers and serializer. MA is asynchronous to this clock and shall pass through a two-flop synchroniser before edge detection. The serial response is only enabled while the frame FSM owns SLO; otherwise SLO is driven to the electrical idle state or tri-stated as required by the selected physical layer.

## 4. Motion generator

### 4.1 Fixed-point phase accumulator

Use a 64-bit unsigned phase accumulator:

- Bits `[63:32]` are the current 32-bit single-turn count.
- Bits `[31:0]` are fractional counts, preventing speed quantisation at low resolution or low speed.
- A 64-bit configurable phase increment is added on every 75 MHz clock.

For an `N`-bit configured single-turn position, transmit:

```
single_turn = phase_accumulator[63 : 64-N]
```

For speed `v` in revolutions/second, calculate the increment in the host or configuration logic as:

```
phase_increment = round(v × 2^64 / 75,000,000)
```

Subtract this increment for negative rotation. This formulation is independent of the selected single-turn resolution and supports the full 1–10 rev/s range with negligible average speed error. A configuration write shall reject a zero increment and values outside the specified speed limits.

### 4.2 Multi-turn counter

Increment the unsigned 12-bit multi-turn counter when the 32-bit integer phase count wraps from `0xFFFF_FFFF` to zero; decrement it on the reverse wrap. The counter wraps modulo `2^multi_turn_bits` when multi-turn is enabled. When `multi_turn_bits = 0`, maintain the counter internally but omit it from the BiSS payload.

### 4.3 Coherent snapshots

Capture the single-turn and multi-turn values once per valid BiSS frame, at the frame-start event. Serialize only this snapshot through frame completion. A motion update must never cause a torn value (for example, old multi-turn with new single-turn) within one response.

## 5. BiSS-C response engine

### 5.1 Frame FSM

Implement the following fixed-format states:

1. `IDLE` - detect the BiSS frame start / SLO request condition.
2. `ACK` - drive the required acknowledgement level for the configured number of MA clocks.
3. `START` - transmit the mandatory start bit.
4. `DATA` - shift the position snapshot MSB first, with multi-turn bits first when both fields are enabled.
5. `STATUS` - transmit the standard active-low error and warning bits, `nE` then `nW`.
6. `CRC` - transmit the standard six-bit CRC, MSB first.
7. `STOP/TIMEOUT` - transmit the stop bit, then return SLO to idle when timeout expires.

Generate a `frame_abort` if MA stops before a complete response. Abort returns SLO to idle, discards the partial serializer state, and must not alter position or the current configuration.

### 5.2 Standard process-data frame format

Use the standard point-to-point BiSS-C encoder frame. SLO is idle high. The
first rising MA edge is `LAT` and latches the position snapshot; it does not
consume a serial output bit. On subsequent MA rising edges the emulator drives:

```
ACK=0, STR=1, CDS=0,
MT[MT_BITS-1:0], ST[ST_BITS-1:0], nE, nW, CRC[5:0], STP=0
```

- `ACK` is always `0`; `STR` is `1` because this emulator has no start-bit
  processing delay; and `CDS` is `0` while optional BiSS control communication
  is not implemented.
- Multi-turn (`MT`) is omitted when `MT_BITS=0`. Both position fields are sent
  most-significant bit first.
- `nE` and `nW` are the standard active-low status flags. A healthy position is
  therefore `nE=1, nW=1`; an injected error or warning drives the respective
  transmitted bit to `0`.
- Calculate CRC over `MT || ST || nE || nW` in that transmitted bit order.
  Do not include `ACK`, `STR`, `CDS`, or `STP`.
- Use a six-bit MSB-first CRC with initial value `0x00` and polynomial `0x43`
  (`x^6 + x + 1`). Invert all six CRC result bits before placing them on SLO.
- `STP=0` is transmitted after CRC. When MA stops, begin timeout measurement;
  after the configured timeout, drive SLO high to signal completion and return
  to `IDLE`.

The implementation shall keep the data-channel CRC and field layout fixed to
this standard encoder format. Only implementation timing parameters (for
example timeout choice) may be configured. Any future EDS or control-register
implementation must preserve this process-data frame.

### 5.3 Optional BiSS Safety frame mode

Provide a selectable, disabled-by-default BiSS Safety mode for test and
integration use. It extends the normal header and frame termination as follows:

```
ACK, STR, CDS,
CPW: MT, ST, nE, nW, CRC6[5:0],
SPW: MT_S, ST_S, nE_S, nW_S, LC[5:0], CRC16[15:0],
STP
```

The Control Position Word (CPW) uses the normal configured encoder position,
active-low error/warning flags and standard inverted CRC-6 (`0x43`). The Safety
Position Word (SPW) is a separately configured position representation of 1 to
40 bits, then its active-low error/warning flags and a six-bit Sign-of-Life
counter (`LC`). Calculate its 16-bit CRC with start value `0x0000` and
polynomial `0x190D9`; transmit the CRC bits inverted and MSB first. The CRCs
are calculated separately. `LC` advances once for each successfully started
frame and follows `1, 2, ..., 63, 1`; its reset value is 1.

The exact safety-mode configuration registers and SPW mapping are defined in
[BISS_EMULATOR_REGISTER_INTERFACE.md](BISS_EMULATOR_REGISTER_INTERFACE.md).
This optional mode emulates the communication format only. It does **not** make
the FPGA, emulator, or connected system functionally safe, certified, or
suitable for a safety function without a separate safety lifecycle, analysis,
and certification programme.

### 5.4 MA timing capability

The supported MA clock rates are **1 MHz, 2 MHz, 5 MHz and 10 MHz**. The FPGA does not generate MA; it detects and responds to the master-selected rate. With a 75 MHz system clock and a two-flop MA synchroniser, the fastest supported rate, 10 MHz, has at least 7.5 FPGA clocks per MA period. The response engine shall therefore be edge-driven and rate-independent across the four supported frequencies.

The actual SLO setup/hold and propagation-delay margin at each supported MA rate must be confirmed by static timing analysis and bench testing with the selected I/O standard and line receiver. MA rates above 10 MHz are out of scope; supporting them requires a source-synchronous or dedicated input/DDR output implementation.

The motion-rate requirement (10 rev/s) is independent of MA frequency; it sets position update accuracy, not serial clock rate.

## 6. Configuration and status interface

Expose the following registers over the project-selected host interface (for example SPI, UART, APB, or Avalon). Configuration writes take effect only at a frame boundary, preventing a mixture of old and new format in a response.

| Register | Contents |
| --- | --- |
| `CONTROL` | enable, direction, reset-position strobe |
| `SINGLE_TURN_BITS` | 18-32; invalid writes set an error flag |
| `MULTI_TURN_BITS` | 0-12; invalid writes set an error flag |
| `SPEED_INCREMENT` | unsigned 64-bit phase-increment magnitude, range checked against 1-10 rev/s; direction is a separate control bit |
| `POSITION_SET` | 32-bit single-turn and 12-bit multi-turn preload |
| `STATUS_INJECT` | logical error/warning inputs and optional forced CRC error for system tests |
| `TIMING` | supported MA-rate selection/monitoring and timeout parameters |
| `STATUS` | active configuration, frame count, abort count, invalid-config flag |

The interface shall include an `apply`/commit bit or equivalent shadow-register scheme. On commit, validate all fields and atomically copy the configuration into active registers at the next `IDLE` state.

## 7. Reset, error handling and diagnostics

- Reset must place SLO in its safe idle/released state before enabling any serializer output.
- An invalid configuration must retain the last valid active configuration and set `invalid_config`.
- A loss of MA or malformed frame must only abort the frame; the motion engine continues to run.
- Provide synthesizable counters for completed frames, aborted frames, and CRC injections. Counters may saturate.
- Provide a simulation-only debug port for position snapshot, FSM state and calculated CRC.

## 8. Timing and resource expectations

The core is small: a 64-bit accumulator/adder, a 12-bit turn counter, a 44-bit snapshot register, a shift register up to the configured frame length, CRC logic, and the MA FSM. No PLL is required if a clean 75 MHz clock is supplied. Constrain MA as asynchronous input, constrain the 75 MHz clock, and define output timing from the detected MA edge to SLO at the FPGA pin according to the target master timing budget.

### 8.1 VHDL RTL structure

Partition the VHDL design into these synthesizable units:

| Unit | Responsibility |
| --- | --- |
| `biss_emulator_pkg` | Types, constants, bit-width checks, CRC-6/CRC-16 functions and phase-increment limits |
| `biss_motion_generator` | 64-bit phase accumulator, direction handling, multi-turn wrap detection and position preload |
| `biss_frame_engine` | MA synchroniser, edge detector, fixed BiSS-C FSM, snapshot, serializer, timeout and SLO control |
| `biss_config_regs` | Shadow/active configuration registers, validation, atomic commit and diagnostic counters |
| `biss_emulator_top` | Clock/reset, host-interface integration and external MA/SLO ports |

Use `ieee.numeric_std` with `unsigned`/`signed` types; do not use
`std_logic_arith`, `std_logic_unsigned`, or `std_logic_signed`. Use synchronous
processes driven only by `rising_edge(clk_75m)`; MA must not be used as an RTL
clock. The MA input synchroniser should carry the FPGA vendor's asynchronous
register attribute in the top-level constraints or RTL, as appropriate for the
target toolchain.

The testbench may use VHDL-2008 features and shall include a behavioural BiSS
master plus a software-equivalent CRC reference function. Keep simulation-only
code separate from synthesizable entities.

### 8.2 Quartus in-system debug and direct control

Include an optional, synthesisable `biss_quartus_debug` wrapper for bench bring-up
on MAX 10. It shall instantiate the Quartus **In-System Sources and Probes** IP
(`altsource_probe`) and connect through JTAG. This is the mechanism for directly
driving internal emulator controls; Signal Tap is used to capture and inspect
signals, not to provide run-time stimulus.

The debug wrapper shall be enabled by a VHDL generic (`G_ENABLE_JTAG_DEBUG`) so
production builds can omit it. JTAG-controlled values must be synchronized to
the 75 MHz domain and passed through the same shadow/`APPLY` validation path as
the normal register interface; a JTAG change must not alter a partially shifted
BiSS frame. The debug source/probe allocation and operating procedure are
specified in [BISS_EMULATOR_QUARTUS_DEBUG.md](BISS_EMULATOR_QUARTUS_DEBUG.md).

## 9. Verification acceptance criteria

1. For every single-turn width 18-32 and multi-turn width 0-12, the serial bit count and field order match `ACK, STR, CDS, MT, ST, nE, nW, CRC, STP`; CRC must match the 0x43 reference model.
2. At 1, 5 and 10 rev/s in both directions, simulated position matches the fixed-point reference model for at least ten minutes with no missed or extra wraps.
3. A snapshot taken across a single-turn wrap contains either the complete pre-wrap or complete post-wrap position, never a torn result.
4. MA frequencies of 1, 2, 5 and 10 MHz meet SLO setup/hold at the line-driver output in timing simulation and hardware measurement.
5. Reset, mid-frame MA stop, invalid configuration, direction reversal and forced CRC/error-status injection are covered by automated testbench tests.
6. In optional safety mode, CPW and SPW data fields, the 1-to-63 Sign-of-Life sequence, CRC-6 and CRC-16 all match independent reference models; unsupported SPW configurations are rejected.

## 10. Open integration decisions

The following are deliberately not assumed and must be fixed from the target master/physical interface before RTL sign-off:

- BiSS physical layer and voltage/I/O standard (RS-422, RS-485, TTL, etc.).
- MA edge convention, timeout and SLO propagation budget. Supported frequencies are fixed at 1, 2, 5 and 10 MHz.
- Whether an Electronic Data Sheet / BiSS Profile 3 register interface is required in addition to process-data emulation.
- Configuration transport and permitted run-time update rate.
- Whether a fault input must automatically assert ERR/WRN.
