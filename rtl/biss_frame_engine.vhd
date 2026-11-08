-- Copyright (c) 2026 Ala-Ismail
-- SPDX-License-Identifier: MIT
-- See LICENSE in the repository root for the full license text.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.biss_emulator_pkg.all;

entity biss_frame_engine is
  generic (
    G_SAFETY_MODE : boolean := false;
    G_SPW_ST_BITS : positive range 1 to 32 := 18;
    G_SPW_MT_BITS : natural range 0 to 12 := 0
  );
  port (
    clk          : in std_logic;
    rst_n        : in std_logic;
    ma_in        : in std_logic;
    enable       : in std_logic;
    st_bits      : in natural range 18 to 32;
    mt_bits      : in natural range 0 to 12;
    timeout_ticks: in unsigned(23 downto 0);
    live_st      : in unsigned(31 downto 0);
    live_mt      : in unsigned(11 downto 0);
    force_error  : in std_logic;
    force_warning: in std_logic;
    force_bad_crc: in std_logic;
    slo_out      : out std_logic;
    frame_idle   : out std_logic;
    frame_count  : out unsigned(31 downto 0);
    abort_count  : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of biss_frame_engine is
  type state_t is (IDLE, ACK, STR, CDS, DATA, STATUS_E, STATUS_W, CRC,
                  SPW_DATA, SPW_E, SPW_W, SPW_LC, SPW_CRC, STOP, TIMEOUT);
  signal state : state_t := IDLE;
  signal ma_meta, ma_sync, ma_last : std_logic := '1';
  signal st_snap : unsigned(31 downto 0) := (others => '0');
  signal mt_snap : unsigned(11 downto 0) := (others => '0');
  signal st_width : natural range 18 to 32 := 18;
  signal mt_width : natural range 0 to 12 := 0;
  signal timeout_snap : unsigned(23 downto 0) := (others => '0');
  signal ne_snap, nw_snap, bad_crc_snap : std_logic := '0';
  signal crc6_r : unsigned(5 downto 0) := (others => '0');
  signal crc16_r : unsigned(15 downto 0) := (others => '0');
  -- next_lc is consumed at LAT, even if the frame is subsequently aborted.
  signal next_lc, lc_snap : unsigned(5 downto 0) := to_unsigned(1, 6);
  signal data_index : natural range 0 to 43 := 0;
  signal crc_index : natural range 0 to 15 := 0;
  signal lc_index : natural range 0 to 5 := 0;
  signal quiet_count : unsigned(23 downto 0) := (others => '0');
  signal slo_r : std_logic := '1';
  signal frames_r, aborts_r : unsigned(31 downto 0) := (others => '0');
begin
  assert not G_SAFETY_MODE or G_SPW_ST_BITS + G_SPW_MT_BITS <= 40
    report "SPW position must contain 1 to 40 bits" severity failure;

  process(clk)
    variable ma_rise : boolean;
    variable b : std_logic;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        ma_meta <= '1'; ma_sync <= '1'; ma_last <= '1'; state <= IDLE;
        slo_r <= '1'; quiet_count <= (others => '0');
        frames_r <= (others => '0'); aborts_r <= (others => '0');
        crc6_r <= (others => '0'); crc16_r <= (others => '0');
        next_lc <= to_unsigned(1, 6); lc_snap <= to_unsigned(1, 6);
        data_index <= 0; crc_index <= 0; lc_index <= 0;
      else
        ma_meta <= ma_in; ma_sync <= ma_meta; ma_last <= ma_sync;
        ma_rise := (ma_sync = '1' and ma_last = '0');
        if ma_rise then
          quiet_count <= (others => '0');
        elsif state /= IDLE then
          if quiet_count /= x"FFFFFF" then quiet_count <= quiet_count + 1; end if;
        end if;

        if state /= IDLE and state /= TIMEOUT and quiet_count >= timeout_snap then
          state <= IDLE; slo_r <= '1'; aborts_r <= aborts_r + 1;
        elsif state = TIMEOUT then
          if quiet_count >= timeout_snap then state <= IDLE; slo_r <= '1'; end if;
        elsif ma_rise then
          case state is
            when IDLE =>
              slo_r <= '1';
              -- Incompatible CPW widths or zero timeout do not start a frame.
              if enable = '1' and timeout_ticks /= 0 and
                 (not G_SAFETY_MODE or
                  (G_SPW_ST_BITS <= st_bits and G_SPW_MT_BITS <= mt_bits)) then
                st_snap <= live_st; mt_snap <= live_mt;
                st_width <= st_bits; mt_width <= mt_bits;
                timeout_snap <= timeout_ticks;
                ne_snap <= not force_error; nw_snap <= not force_warning;
                bad_crc_snap <= force_bad_crc;
                crc6_r <= (others => '0'); crc16_r <= (others => '0');
                if G_SAFETY_MODE then
                  lc_snap <= next_lc;
                  if next_lc = 63 then next_lc <= to_unsigned(1, 6);
                  else next_lc <= next_lc + 1; end if;
                end if;
                state <= ACK;
              end if;
            when ACK => slo_r <= '0'; state <= STR;
            when STR => slo_r <= '1'; state <= CDS;
            when CDS => slo_r <= '0'; data_index <= 0; state <= DATA;
            when DATA =>
              if data_index < mt_width then b := mt_snap(mt_width-1-data_index);
              -- ST is the most significant requested part of the full turn.
              else b := st_snap(31-(data_index-mt_width)); end if;
              slo_r <= b; crc6_r <= crc6_step(crc6_r, b);
              if data_index = st_width+mt_width-1 then state <= STATUS_E;
              else data_index <= data_index + 1; end if;
            when STATUS_E =>
              slo_r <= ne_snap; crc6_r <= crc6_step(crc6_r, ne_snap); state <= STATUS_W;
            when STATUS_W =>
              slo_r <= nw_snap; crc6_r <= crc6_step(crc6_r, nw_snap);
              crc_index <= 0; state <= CRC;
            when CRC =>
              b := not crc6_r(5-crc_index);
              if bad_crc_snap = '1' and crc_index = 5 then b := not b; end if;
              slo_r <= b;
              if crc_index = 5 then
                if G_SAFETY_MODE then data_index <= 0; state <= SPW_DATA;
                else state <= STOP; end if;
              else crc_index <= crc_index + 1; end if;
            when SPW_DATA =>
              -- SPW MT is the leading part of the configured CPW MT field.
              if data_index < G_SPW_MT_BITS then b := mt_snap(mt_width-1-data_index);
              else b := st_snap(31-(data_index-G_SPW_MT_BITS)); end if;
              slo_r <= b; crc16_r <= crc16_step(crc16_r, b);
              if data_index = G_SPW_ST_BITS+G_SPW_MT_BITS-1 then state <= SPW_E;
              else data_index <= data_index + 1; end if;
            when SPW_E =>
              slo_r <= ne_snap; crc16_r <= crc16_step(crc16_r, ne_snap); state <= SPW_W;
            when SPW_W =>
              slo_r <= nw_snap; crc16_r <= crc16_step(crc16_r, nw_snap);
              lc_index <= 0; state <= SPW_LC;
            when SPW_LC =>
              b := lc_snap(5-lc_index);
              slo_r <= b; crc16_r <= crc16_step(crc16_r, b);
              if lc_index = 5 then crc_index <= 0; state <= SPW_CRC;
              else lc_index <= lc_index + 1; end if;
            when SPW_CRC =>
              b := not crc16_r(15-crc_index);
              if bad_crc_snap = '1' and crc_index = 15 then b := not b; end if;
              slo_r <= b;
              if crc_index = 15 then state <= STOP;
              else crc_index <= crc_index + 1; end if;
            when STOP => slo_r <= '0'; frames_r <= frames_r + 1; state <= TIMEOUT;
            when others => null;
          end case;
        end if;
      end if;
    end if;
  end process;
  slo_out <= slo_r;
  frame_idle <= '1' when state = IDLE else '0';
  frame_count <= frames_r;
  abort_count <= aborts_r;
end architecture;
