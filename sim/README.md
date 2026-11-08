# RTL frame simulation

The VHDL-2008 testbench drives MA as a behavioral master and checks every
serialized bit. It instantiates `biss_frame_engine` with compile-time generics;
the mode cannot change during simulation or hardware operation.

## Run

Use ModelSim or Questa with `vlib`, `vcom`, and `vsim` on PATH:

```powershell
./sim/run.ps1
```

Or specify the simulator's executable directory:

```powershell
./sim/run.ps1 -SimulatorBin 'C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem'
```

The regression was run with ModelSim Intel FPGA Starter Edition 2020.1.
It compiles all RTL and the testbench into `sim/build/work`, then runs six
separate elaborations: standard mode and safety SPW ST/MT widths of 18/0,
1/0, 24/12, 32/8, and 16/6. A seventh, expected-failure simulation verifies
that a 32/12 (44-bit) SPW fails the static width assertion.

Passing tests call `std.env.finish`. Assertion failures, simulator errors,
unexpected termination, or watchdog expiry fail the runner. Generated
libraries, logs, and waveform files stay under `sim/build/`, ignored by Git.

## Coverage

- Header, CPW/SPW field order, MSB-first alignment, MT omission, status, CRCs,
  stop bit, and completion timeout.
- CPW ST widths 18–32 and MT widths 0–12 at 1, 2, 5, and 10 MHz MA, for every
  combination compatible with each compiled SPW configuration.
- Independent full-message polynomial-division references for CRC6 and CRC16;
  the checker does not call the RTL CRC helpers.
- SPW position widths at the 1-bit and 40-bit boundaries, including reduced
  ST and MT representations.
- Multiple life-counter wraps through 1–63 and restart after reset.
- Error/warning flags and corruption of each transmitted CRC's final bit.
- LAT snapshot consistency when live position, widths, flags, timeout, and
  enable change during transmission.
- Early and late aborts, counter updates, timeout recovery, disabled starts,
  zero timeout, incompatible widths, and reset in a partial frame.

## Limits and protocol references

These tests check the frame engine with supplied positions, not the motion
generator's long-duration behavior or a complete board system. They do not
test the C reference core, metastability, physical setup/hold, line drivers,
EDS/control communication, or safety certification.

The implemented process-data layout follows the project's documented mapping.
Protocol references are the [BiSS Safety overview](https://biss-interface.com/technology/biss-safety/)
and [BP3S Safety Encoder Profile](https://biss-interface.com/wp-content/uploads/2025/07/BiSS_BP3S_profile_A1en-2.pdf).
The selected life-counter policy transmits 1 first, consumes values at accepted
LAT, wraps 63 to 1, and never transmits 0.
