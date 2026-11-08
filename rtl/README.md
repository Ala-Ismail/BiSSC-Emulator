# RTL status

The first synthesizable VHDL increment implements the 75 MHz fixed-point motion
generator and the standard point-to-point BiSS-C process-data frame:

`LAT, ACK=0, STR=1, CDS=0, MT, ST, nE, nW, inverted CRC-6, STP=0`.

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
quartus_sh --flow compile biss_emulator
```

Reports and programming outputs are written to `output_files/`. This project
checks synthesis, fitting, assembly, and timing; it does not run a simulation.
