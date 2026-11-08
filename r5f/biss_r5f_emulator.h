#ifndef BISS_R5F_EMULATOR_H
#define BISS_R5F_EMULATOR_H

#include <stdbool.h>
#include <stdint.h>

/* This core is intentionally OS-free.  Call biss_emulator_poll() continuously
 * from one dedicated R5F core.  All timestamps use the same free-running timer. */
typedef enum {
    BISS_IDLE, BISS_ACK, BISS_STR, BISS_CDS, BISS_DATA,
    BISS_ERR, BISS_WRN, BISS_CRC, BISS_STOP, BISS_TIMEOUT
} biss_state_t;

typedef struct {
    uint8_t  st_bits;             /* 18..32 */
    uint8_t  mt_bits;             /* 0..12 */
    uint32_t timer_hz;            /* free-running timestamp frequency */
    uint32_t timeout_ticks;       /* timeout in timer ticks; 20 us recommended */
    uint64_t phase_increment;     /* speed_rps * 2^64 / timer_hz */
    bool     direction_negative;
    bool     enabled;
} biss_config_t;

typedef struct {
    biss_config_t cfg;
    uint64_t phase;               /* upper 32 bits are the full single-turn count */
    uint16_t multi_turn;
    uint32_t last_motion_tick;
    uint32_t last_ma_tick;
    uint32_t frame_count;
    uint32_t abort_count;
    uint32_t st_snapshot;
    uint16_t mt_snapshot;
    uint8_t crc6;
    uint8_t data_index;
    uint8_t crc_index;
    bool ma_previous;
    bool slo_level;
    bool force_error;
    bool force_warning;
    bool force_bad_crc;
    biss_state_t state;
} biss_emulator_t;

void biss_emulator_init(biss_emulator_t *e, const biss_config_t *cfg, uint32_t now);
bool biss_emulator_configure(biss_emulator_t *e, const biss_config_t *cfg);
void biss_emulator_set_position(biss_emulator_t *e, uint32_t st, uint16_t mt);
void biss_emulator_set_faults(biss_emulator_t *e, bool error, bool warning, bool bad_crc);

/* Call on every fast-loop iteration.  Returns the SLO output state. */
bool biss_emulator_poll(biss_emulator_t *e, bool ma_level, uint32_t now);

#endif
