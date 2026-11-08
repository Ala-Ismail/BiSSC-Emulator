# BiSS Emulator Register Interface

## 1. Purpose

This is the planned register wrapper contract; `biss_config_regs` is not yet
implemented. The current RTL exposes active ports directly. Safety selection
and SPW widths are compile-time generics, never writable register fields.

This document specifies the host-visible register interface for the VHDL BiSS-C encoder emulator. It is bus-neutral: a thin wrapper may expose the same 32-bit register map through SPI, UART, APB, Avalon-MM, AXI4-Lite, or another host transport.

All addresses are byte addresses. Registers are 32 bits wide, aligned on 4-byte boundaries, and use normal read/write transactions. A bus wrapper is responsible for byte ordering on a serial transport; each field is defined by its bit number and is not dependent on host byte endianness.

The interface configures the emulated position format, rotation, fault injection, and timeout. It does not configure MA frequency: MA is supplied by the master and the frame engine accepts 1, 2, 5, or 10 MHz.

For MAX 10 laboratory builds, the optional Quartus JTAG debug interface can
temporarily override these pending controls. Its source/probe allocation and
safe handover rules are specified in [BISS_EMULATOR_QUARTUS_DEBUG.md](BISS_EMULATOR_QUARTUS_DEBUG.md).

## 2. Register-map overview

| Address | Name | Access | Purpose |
| --- | --- | --- | --- |
| 0x00 | ID_VERSION | RO | Core identifier and register-map revision |
| 0x04 | CONTROL | RW / command | Enable, direction, apply and command strobes |
| 0x08 | FORMAT_SHADOW | RW | Pending single-turn and multi-turn widths |
| 0x0C | TIMEOUT_SHADOW | RW | Pending static timeout in 75 MHz clocks |
| 0x10 | SPEED_INC_LO_SHADOW | RW | Pending phase-increment bits 31:0 |
| 0x14 | SPEED_INC_HI_SHADOW | RW | Pending phase-increment bits 63:32 |
| 0x18 | POSITION_ST_SHADOW | RW | Pending 32-bit single-turn preload |
| 0x1C | POSITION_MT_SHADOW | RW | Pending 12-bit multi-turn preload |
| 0x20 | FAULT_SHADOW | RW | Pending error, warning and CRC-injection controls |
| 0x24 | STATUS | RO | Run state and configuration status |
| 0x28 | ACTIVE_FORMAT | RO | Currently active position format |
| 0x2C | ACTIVE_TIMEOUT | RO | Currently active timeout |
| 0x30 | ACTIVE_SPEED_INC_LO | RO | Active phase-increment bits 31:0 |
| 0x34 | ACTIVE_SPEED_INC_HI | RO | Active phase-increment bits 63:32 |
| 0x38 | ACTIVE_POSITION_ST | RO | Current 32-bit single-turn position |
| 0x3C | ACTIVE_POSITION_MT | RO | Current 12-bit multi-turn position |
| 0x40 | FRAME_COUNT | RO | Saturating completed-frame count |
| 0x44 | ABORT_COUNT | RO | Saturating aborted-frame count |
| 0x48 | CRC_INJECT_COUNT | RO | Saturating forced-CRC-error count |
| 0x4C | SAFETY_FORMAT | RO | Compiled SPW field widths |
| 0x50 | SAFETY_STATUS | RO | Compiled safety mode and last latched Sign-of-Life counter |

Addresses 0x54 through 0x7F are reserved and must read as zero. Writes to reserved addresses are ignored.

## 3. Configuration model

Writes to registers marked SHADOW modify only the pending configuration. Write CONTROL.APPLY=1 after all related fields have been written. The VHDL core validates the complete pending configuration and, if valid, atomically copies it to the active configuration at the next BiSS frame boundary while the frame engine is in IDLE.

APPLY is self-clearing. Software shall poll STATUS.APPLY_PENDING until it is zero before reusing the shadow configuration. If validation fails, the existing active configuration remains unchanged, APPLY_PENDING clears, and STATUS.INVALID_CONFIG is set.

CONTROL.LOAD_POSITION=1 is also self-clearing and requests an atomic preload from POSITION_ST_SHADOW and POSITION_MT_SHADOW. It is performed at an IDLE boundary and does not reset the frame or diagnostic counters. LOAD_POSITION may be asserted with APPLY; both configuration and preload take effect at the same boundary.

A reset initializes active and shadow configuration as follows:

| Item | Reset value |
| --- | --- |
| Enabled | 0 |
| Direction | positive |
| Single-turn bits | 18 |
| Multi-turn bits | 0 |
| Speed | 1 rev/s |
| Timeout | 1500 clocks (20 us at 75 MHz) |
| Position | 0 |
| Error / warning | healthy |
| CRC injection | off |
| Safety mode | Fixed by `G_SAFETY_MODE` (default false) |
| SPW single-turn / multi-turn bits | Fixed by `G_SPW_ST_BITS` / `G_SPW_MT_BITS` (defaults 18 / 0) |

## 4. Register definitions

### 4.1 ID_VERSION (0x00, read-only)

| Bits | Field | Value |
| --- | --- | --- |
| 31:16 | CORE_ID | ASCII BE (0x4245) for BiSS Emulator |
| 15:8 | MAP_MAJOR | 0x02 (compile-time safety selection) |
| 7:0 | MAP_MINOR | 0x00 |

### 4.2 CONTROL (0x04, read/write and command)

| Bit | Field | Meaning |
| --- | --- | --- |
| 0 | ENABLE | 1: respond to BiSS frames; 0: hold SLO idle-high and continue position motion |
| 1 | DIRECTION | 0: positive rotation; 1: negative rotation |
| 8 | APPLY | Write 1 to commit all shadow configuration at the next safe boundary |
| 9 | LOAD_POSITION | Write 1 to preload the pending position at the next safe boundary |
| 10 | CLEAR_DIAGNOSTICS | Write 1 to clear frame, abort and CRC-injection counters |
| 31:11, 7:2 | Reserved | Write zero; read zero |

Bits 0 and 1 are shadowed and take effect with APPLY. Bit 2 is reserved;
software cannot change the frame mode. Command bits are write-one strobes
and always read as zero.

### 4.3 FORMAT_SHADOW (0x08, read/write)

| Bits | Field | Legal values |
| --- | --- | --- |
| 5:0 | ST_BITS | Decimal 18 to 32 |
| 12:8 | MT_BITS | Decimal 0 to 12 |
| 31:13, 7:6 | Reserved | Write zero |

The standard BiSS payload contains MT[MT_BITS-1:0] followed by ST[ST_BITS-1:0]. MT_BITS=0 omits the multi-turn field.

### 4.4 TIMEOUT_SHADOW (0x0C, read/write)

| Bits | Field | Legal values |
| --- | --- | --- |
| 23:0 | TIMEOUT_TICKS | 1 to 16,777,215 75 MHz clocks |
| 31:24 | Reserved | Write zero |

This is the static delay between the final STP=0 and SLO returning high. Reset value 1500 equals 20 us. The target BiSS master must wait at least this time before beginning another frame.

### 4.5 SPEED_INC_LO_SHADOW and SPEED_INC_HI_SHADOW (0x10, 0x14, read/write)

Together these registers form the unsigned 64-bit phase increment:

~~~
SPEED_INCREMENT = (SPEED_INC_HI_SHADOW << 32) | SPEED_INC_LO_SHADOW
~~~

The VHDL motion generator adds this magnitude on every 75 MHz system-clock cycle for positive direction and subtracts it for negative direction. The legal range is inclusive:

~~~
ceil(2^64 / 75,000,000) <= SPEED_INCREMENT
                         <= floor(10 * 2^64 / 75,000,000)
~~~

For a requested speed v rev/s, host software shall write:

~~~
round(v * 2^64 / 75,000,000)
~~~

The core rejects values outside the 1 to 10 rev/s range on APPLY. The magnitude is not signed; use CONTROL.DIRECTION for reverse motion.

### 4.6 POSITION_ST_SHADOW (0x18, read/write)

All 32 bits supply the pending single-turn preload. At position load, the core retains only the upper ST_BITS significant position bits and clears lower unreported bits. For example, with ST_BITS=18, bits 31:14 are the preload value and bits 13:0 become zero.

### 4.7 POSITION_MT_SHADOW (0x1C, read/write)

| Bits | Field | Meaning |
| --- | --- | --- |
| 11:0 | MT_VALUE | Pending multi-turn preload |
| 31:12 | Reserved | Write zero |

At position load, the core retains the least-significant MT_BITS of MT_VALUE. It loads zero when MT_BITS=0.

### 4.8 FAULT_SHADOW (0x20, read/write)

| Bit | Field | Meaning |
| --- | --- | --- |
| 0 | FORCE_ERROR | 1 transmits nE=0; 0 transmits healthy nE=1 |
| 1 | FORCE_WARNING | 1 transmits nW=0; 0 transmits healthy nW=1 |
| 2 | FORCE_BAD_CRC | 1 inverts CRC bit 0 after normal CRC inversion, once per frame |
| 31:3 | Reserved | Write zero |

FORCE_BAD_CRC deliberately makes every enabled frame fail CRC validation. The calculated, standard inverted CRC is modified only at output; it does not change the position data or error/warning flags.

### 4.9 STATUS (0x24, read-only)

| Bit | Field | Meaning |
| --- | --- | --- |
| 0 | ENABLED_ACTIVE | Active ENABLE state |
| 1 | APPLY_PENDING | Validated commit/preload waiting for an IDLE boundary |
| 2 | INVALID_CONFIG | Sticky; clear with a valid APPLY or reset |
| 3 | FRAME_ACTIVE | BiSS FSM is not in IDLE |
| 4 | MA_RATE_VALID | Most recently measured MA rate is 1, 2, 5, or 10 MHz within tolerance |
| 7:5 | MA_RATE_CODE | 001: 1 MHz, 010: 2 MHz, 011: 5 MHz, 100: 10 MHz; 000: unknown/invalid |
| 8 | ERROR_ACTIVE | Active forced-error state |
| 9 | WARNING_ACTIVE | Active forced-warning state |
| 10 | BAD_CRC_ACTIVE | Active forced-bad-CRC state |
| 11 | SAFETY_MODE_ACTIVE | Constant readback of `G_SAFETY_MODE` |
| 31:11 | Reserved | Read zero |

### 4.10 Active configuration and position registers

ACTIVE_FORMAT (0x28) uses the same bit fields as FORMAT_SHADOW. ACTIVE_TIMEOUT (0x2C) exposes TIMEOUT_TICKS in bits 23:0. ACTIVE_SPEED_INC_LO (0x30) and ACTIVE_SPEED_INC_HI (0x34) expose the active 64-bit speed increment.

ACTIVE_POSITION_ST (0x38) returns the live 32-bit single-turn accumulator integer portion. ACTIVE_POSITION_MT (0x3C) returns the live multi-turn count in bits 11:0. These live readbacks are diagnostic values and need not be coherent with each other. The BiSS serializer always uses its separate coherent frame snapshot.

### 4.11 Counters (0x40 to 0x48, read-only)

All counters are unsigned, 32-bit and saturating. FRAME_COUNT increments when STP is transmitted; ABORT_COUNT increments when a frame ends before STP; CRC_INJECT_COUNT increments once per completed frame affected by forced bad CRC. Write CONTROL.CLEAR_DIAGNOSTICS=1 to clear all three counters.

### 4.12 SAFETY_FORMAT (0x4C, read-only)

This register reports the compiled SPW width generics. Writes are ignored.
These widths are only used when `G_SAFETY_MODE=true`.

| Bits | Field | Readback |
| --- | --- | --- |
| 5:0 | SPW_ST_BITS | `G_SPW_ST_BITS`, decimal 1 to 32 |
| 11:8 | SPW_MT_BITS | `G_SPW_MT_BITS`, decimal 0 to 12 |
| 31:12, 7:6 | Reserved | Read zero |

SPW_ST_BITS + SPW_MT_BITS must be from 1 to 40, and each SPW field width must
not exceed its corresponding CPW width. A total over 40 is rejected by a
static RTL assertion in safety builds. The future wrapper rejects incompatible
CPW widths on APPLY; today's frame engine rejects such starts at LAT without
consuming LC. SPW is derived from the same position snapshot as CPW: it
transmits the leading requested bits of the configured CPW multi-turn field,
followed by the leading requested bits of the CPW single-turn field. CPW ST
is itself taken from the most significant configured bits of the full 32-bit
single-turn accumulator. This permits SPW at equal or lower resolution than CPW and
ensures both position words describe the same emulated shaft position.

In safety mode the frame after CDS is:

~~~
CPW_MT, CPW_ST, nE, nW, inverted CRC6,
SPW_MT, SPW_ST, nE, nW, LC[5:0], inverted CRC16, STP=0
~~~

CRC6 uses polynomial 0x43 and CRC16 uses polynomial 0x190D9. Both start with
zero, protect only their respective data-channel fields, and are inverted before
transmission. The first accepted LAT after reset captures LC=1; subsequent
accepted starts capture 2 through 63, then 1. An aborted frame still consumes
its captured LC. Disabled/rejected starts do not advance LC. Error, warning, and forced-CRC
injection controls apply to both CPW and SPW; forced bad CRC flips bit 0 of each
transmitted CRC.

### 4.13 SAFETY_STATUS (0x50, read-only)

| Bits | Field | Meaning |
| --- | --- | --- |
| 0 | SAFETY_ACTIVE | Constant value of `G_SAFETY_MODE` |
| 6:1 | LC_VALUE | Last latched frame LC; resets to 1, meaningful only in safety builds |
| 31:7 | Reserved | Read zero |

## 5. Recommended host configuration sequence

1. Read SAFETY_STATUS and SAFETY_FORMAT to determine the compiled frame format. Write CONTROL with the desired ENABLE and DIRECTION bits; leave command and reserved bits zero.
2. Write FORMAT_SHADOW, TIMEOUT_SHADOW, both speed-increment words, POSITION_ST_SHADOW, POSITION_MT_SHADOW, and FAULT_SHADOW. In a safety build, CPW widths must accommodate the compiled SPW widths.
3. Write CONTROL again with the same persistent bits and APPLY=1. Set LOAD_POSITION=1 if a position preload is required.
4. Poll STATUS.APPLY_PENDING until clear. If STATUS.INVALID_CONFIG=1, correct the pending values and repeat from step 2.
5. Confirm STATUS.MA_RATE_VALID=1 once the connected master is clocking at 1, 2, 5, or 10 MHz.

For a running emulator, repeat the same sequence. The active BiSS frame completes using its original snapshot and configuration; the new settings begin only at the following safe frame boundary.

## 6. VHDL implementation requirements

Implement the register file in biss_config_regs using a bus-wrapper-independent request interface such as cfg_addr, cfg_wr, cfg_rd, cfg_wdata, cfg_rdata, and cfg_ready. A transport adapter converts its external protocol into this interface.

All shadow writes, active-register updates, counter updates, and command strobes shall be synchronized to the 75 MHz FPGA clock. If the physical host bus runs in another clock domain, the wrapper must use a request/response handshake or asynchronous FIFO; individual multi-bit register fields must not cross clock domains without a coherent transfer mechanism.
