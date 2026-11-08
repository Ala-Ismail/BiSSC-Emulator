# Quartus MAX 10 Debug and Direct-Control Interface

## 1. Scope

This is a planned wrapper interface; the wrapper and generated IP are not
implemented yet. Safety format is fixed by `G_SAFETY_MODE` and SPW width
generics at compile time. JTAG cannot change them.

This interface is for laboratory bring-up of the BiSS emulator on an Altera/Intel MAX 10 FPGA using JTAG and Quartus Prime. It has two separate roles:

- Quartus In-System Sources and Probes drives selected emulator controls through JTAG.
- Signal Tap Logic Analyzer captures internal activity and timing for diagnosis.

Signal Tap is an observation tool. Direct control is provided by the In-System Sources and Probes IP, named altsource_probe in Quartus.

This debug interface is optional. It is included only when the VHDL generic G_ENABLE_JTAG_DEBUG is true. The normal host register interface remains the production configuration path.

## 2. Required VHDL hierarchy

Instantiate a wrapper named biss_quartus_debug below biss_emulator_top. The wrapper contains a generated altsource_probe instance with:

| Parameter | Value |
| --- | --- |
| Source width | 192 bits |
| Probe width | 128 bits |
| Instance index | 0 |
| Source clock | 75 MHz FPGA clock |
| Source clock enable | 1 |

Use the generated Quartus IP template for the selected Quartus version rather than hand-writing a primitive declaration. Connect source_clk to the 75 MHz clock. Synchronize the source data or register it locally before it is accepted by biss_config_regs.

## 3. JTAG source word

The JTAG editor writes the 192-bit source word. Its fields are:

| Bits | Field | Meaning |
| --- | --- | --- |
| 0 | DBG_OVERRIDE_EN | Enables debug control. 0 leaves normal host registers in control. |
| 1 | ENABLE | Requested emulator enable |
| 2 | DIRECTION | 0 positive, 1 negative |
| 3 | Reserved | Write zero; safety mode is a compile-time generic |
| 4 | FORCE_ERROR | Drives nE low when active |
| 5 | FORCE_WARNING | Drives nW low when active |
| 6 | FORCE_BAD_CRC | Corrupts the transmitted CRC for test |
| 7 | APPLY_TOGGLE | Toggle this bit to request a safe configuration commit |
| 8 | LOAD_POSITION_TOGGLE | Toggle this bit to request a safe position preload |
| 9 | CLEAR_DIAG_TOGGLE | Toggle this bit to clear diagnostic counters |
| 15:10 | ST_BITS | Single-turn bit width, 18 to 32 |
| 19:16 | MT_BITS | Multi-turn bit width, 0 to 12 |
| 29:20 | Reserved | Write zero; SPW widths are compile-time generics |
| 53:30 | TIMEOUT_TICKS | Static timeout in 75 MHz clocks |
| 117:54 | SPEED_INCREMENT | Unsigned 64-bit motion phase increment |
| 149:118 | POSITION_ST | 32-bit single-turn preload |
| 161:150 | POSITION_MT | 12-bit multi-turn preload |
| 191:162 | Reserved | Write zero |

APPLY_TOGGLE, LOAD_POSITION_TOGGLE, and CLEAR_DIAG_TOGGLE use toggle detection, not level detection. Each time the In-System Sources and Probes Editor writes a changed value to one of these bits, the wrapper emits a single 75 MHz-clock command pulse.

When DBG_OVERRIDE_EN is 1, the wrapper presents the source fields as the pending configuration. The command caused by APPLY_TOGGLE must use the same validation and IDLE-boundary commit path as the normal register interface. When DBG_OVERRIDE_EN returns to 0, normal host-register control resumes at the next safe boundary; it must not change an in-flight frame.

## 4. Probe word

The 128-bit probe word is read from the In-System Sources and Probes Editor.

| Bits | Field | Meaning |
| --- | --- | --- |
| 3:0 | FSM_STATE | Encoded BiSS frame-engine state |
| 4 | FRAME_ACTIVE | Frame FSM is not IDLE |
| 5 | MA_SYNC | Synchronized MA input |
| 6 | MA_RISE | One-clock detected MA rising-edge pulse |
| 7 | MA_FALL | One-clock detected MA falling-edge pulse |
| 11:8 | MA_RATE_CODE | 1, 2, 5, 10 MHz classification |
| 12 | MA_RATE_VALID | Current MA frequency is supported |
| 13 | SLO_OUT | FPGA-side SLO output value |
| 14 | SLO_OE | SLO output-enable value |
| 15 | SAFETY_ACTIVE | Constant readback of `G_SAFETY_MODE` |
| 47:16 | SNAPSHOT_ST | Coherent single-turn frame snapshot |
| 59:48 | SNAPSHOT_MT | Coherent multi-turn frame snapshot |
| 65:60 | LC_VALUE | Safety sign-of-life counter |
| 71:66 | CRC6_VALUE | Uninverted CPW CRC result |
| 87:72 | CRC16_VALUE | Uninverted SPW CRC result |
| 111:88 | TIMEOUT_COUNT | Current timeout counter |
| 127:112 | FRAME_COUNT_LSW | Low 16 bits of completed-frame count |

## 5. Signal Tap capture set

Add these signals to Signal Tap during initial hardware validation:

- ma_in at the FPGA pin, its synchronized form, and detected rising/falling edge pulses.
- slo_out, slo_oe, and, where available, the SLO feedback/receiver signal.
- FSM state, serializer bit index, frame snapshot, and transmitted serial bit.
- CRC input-enable, CRC-6 state, CRC-16 state, and final inverted CRC bits.
- timeout counter, MA-period measurement, rate-valid flag, and abort reason.
- active configuration values, apply-pending state, and invalid-configuration flag.

Sample Signal Tap on the 75 MHz clock. Set a trigger on MA_RISE, an unexpected abort, CRC injection, or a falling SLO output edge. At 10 MHz MA, a capture depth that includes at least 1000 samples records more than 13 MA periods and is adequate for an initial frame-timing check.

## 6. Quartus workflow

1. Generate the altsource_probe IP with the widths in section 2 and add its generated VHDL files to the Quartus project.
2. Build with G_ENABLE_JTAG_DEBUG=true and program the MAX 10 through JTAG.
3. Open Tools > In-System Sources and Probes Editor. Set the source word fields, write the source data, then toggle APPLY_TOGGLE.
4. Read the probe word to confirm the active state, snapshot, MA frequency classification, and output state.
5. Use Signal Tap for continuous frame-level capture. It is the preferred tool for validating SLO timing against MA.
6. Build the production image with G_ENABLE_JTAG_DEBUG=false after bench validation.

Quartus documents In-System Sources and Probes as a JTAG mechanism for driving and sampling logic; it requires a compiled and programmed image containing the IP instance. It is not a replacement for the external host configuration interface.

## 7. Remaining target information

The MAX 10 family selection is enough to structure the VHDL and debug path. Before a Quartus project, SDC file, or pin assignments can be completed, provide the exact MAX 10 device/package and board schematic or pin list for the 75 MHz clock, MA receiver input, SLO driver output, JTAG, and I/O supply banks.

