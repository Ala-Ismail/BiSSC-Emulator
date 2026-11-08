# RTL status

The synthesizable VHDL implements a 75 MHz fixed-point motion generator and
compile-time selection of standard or BiSS Safety process-data frames.
The standard frame is:

`LAT, ACK=0, STR=1, CDS=0, MT, ST, nE, nW, inverted CRC-6, STP=0`.

`G_SAFETY_MODE=true` adds SPW after CPW's CRC6 and before STP:
`SPW_MT, SPW_ST, nE, nW, LC[5:0], inverted CRC16`.
The default is `false`. `G_SPW_ST_BITS` (default 18) and `G_SPW_MT_BITS`
(default 0) fix SPW widths at compile time. No mode/width control port exists.
SPW has 1–40 position bits and each field must fit CPW. Incompatible CPW
widths or zero timeout reject LAT. LC starts at 1, advances on accepted LAT
even for an aborted frame, and wraps from 63 to 1.

Position, widths, timeout and faults are captured at LAT. ST uses the leading
configured bits of the 32-bit turn; SPW uses the leading requested bits of each
CPW field. CRCs accumulate over serialized protected bits; CPW uses inverted
CRC6 (`0x43`), SPW uses inverted CRC16 (`0x190D9`) including status and LC.

`biss_emulator_top` intentionally exposes active configuration ports. The next
integration increment will connect those ports to the documented bus-neutral
`biss_config_regs` register bank and optional Quartus `altsource_probe` wrapper.
The root `biss_emulator.qpf` project includes all RTL and a 75 MHz SDC. It uses
a provisional MAX 10 10M50DAF484C7G device, virtual configuration/status pins,
and automatic placement of clock/reset/MA/SLO for compile checking. Replace
the target and add board pin locations, I/O standards, and interface timing
constraints before hardware use. Generated Intel debug IP is not included.

Run a full compile from the repository root with Quartus Prime on PATH:

```powershell
quartus_sh --flow compile biss_emulator -c biss_emulator
quartus_sh --flow compile biss_emulator -c biss_emulator_safety
```

The safety revision selects a 24 ST / 12 MT SPW. Its active CPW width inputs
must be at least that large. Standard reports go to `output_files/`; safety
reports go to `output_files/safety/`. Both revisions compile and meet the
constrained internal 75 MHz checks on the provisional target; external timing
and pin assignments remain incomplete.

Run the separate [frame simulation regression](../sim/README.md) with
`./sim/run.ps1` from the repository root. Register/JTAG wrappers, EDS discovery,
and independent redundant sensing are not implemented. The safety format is
for protocol emulation and is not safety certified.
