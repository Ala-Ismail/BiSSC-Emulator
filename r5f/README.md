# AM6442 R5F 1 MHz BiSS-C emulator

This is a bare-metal C reference core for a **dedicated R5F** used only to
functionally emulate a point-to-point BiSS-C encoder at 1 MHz MA. It is not an
RS-422 implementation and it is not safety certified.

## Board port

Create one EVM-specific tight loop that reads MA, calls `biss_emulator_poll`,
and writes the returned SLO state using direct GPIO registers. Do not place an
RTOS call, `printf`, lock, cache maintenance operation, or conventional GPIO
driver function in this loop.

```c
for (;;) {
    const uint32_t now = platform_fast_timer_read();
    const bool ma = platform_gpio_read_ma();
    platform_gpio_write_slo(biss_emulator_poll(&encoder, ma, now));
}
```

Place the loop and the emulator source in R5F TCM. `platform_fast_timer_read`,
`platform_gpio_read_ma`, and `platform_gpio_write_slo` must be inline,
board-specific direct-register functions.

For an EVM CMOS loopback, connect MA output to MA input and SLO output to a
separate SLO input, using the same compatible I/O voltage bank and common
ground. Do not connect two outputs together.

## Initial configuration

Set `timer_hz` to the actual free-running timer clock. For 1 rev/s:

```
phase_increment = round(2^64 / timer_hz)
```

For 10 rev/s, multiply that value by ten. The example assumes a 20 us timeout:

```
timeout_ticks = timer_hz / 50000
```

Measure MA-to-SLO delay at the EVM pins before relying on the test. This source
is for logic checking at 1 MHz; it intentionally avoids claiming hard real-time
guarantees for a production encoder.
