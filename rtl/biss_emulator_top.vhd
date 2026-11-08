-- Copyright (c) 2026 Ala-Ismail
-- SPDX-License-Identifier: MIT
-- See LICENSE in the repository root for the full license text.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity biss_emulator_top is
  generic (
    G_SAFETY_MODE : boolean := false;
    G_SPW_ST_BITS : positive range 1 to 32 := 18;
    G_SPW_MT_BITS : natural range 0 to 12 := 0
  );
  port (
    clk_75m       : in  std_logic;
    rst_n         : in  std_logic;
    ma_in         : in  std_logic;
    slo_out       : out std_logic;

    -- These are the active-control inputs.  biss_config_regs or the optional
    -- Quartus debug wrapper drives them in an integrated build.
    cfg_enable    : in  std_logic;
    cfg_direction_neg : in std_logic;
    cfg_st_bits   : in  natural range 18 to 32;
    cfg_mt_bits   : in  natural range 0 to 12;
    cfg_phase_increment : in unsigned(63 downto 0);
    cfg_timeout_ticks   : in unsigned(23 downto 0);
    cfg_force_error     : in std_logic;
    cfg_force_warning   : in std_logic;
    cfg_force_bad_crc   : in std_logic;
    cfg_load_position   : in std_logic;
    cfg_position_st     : in unsigned(31 downto 0);
    cfg_position_mt     : in unsigned(11 downto 0);

    status_frame_idle   : out std_logic;
    status_frame_count  : out unsigned(31 downto 0);
    status_abort_count  : out unsigned(31 downto 0);
    status_position_st  : out unsigned(31 downto 0);
    status_position_mt  : out unsigned(11 downto 0)
  );
end entity;

architecture rtl of biss_emulator_top is
  signal st : unsigned(31 downto 0);
  signal mt : unsigned(11 downto 0);
begin
  u_motion : entity work.biss_motion_generator
    port map (
      clk => clk_75m, rst_n => rst_n,
      phase_increment => cfg_phase_increment, direction_neg => cfg_direction_neg,
      mt_bits => cfg_mt_bits, load_position => cfg_load_position,
      load_st => cfg_position_st, load_mt => cfg_position_mt,
      single_turn => st, multi_turn => mt
    );

  u_frame : entity work.biss_frame_engine
    generic map (
      G_SAFETY_MODE => G_SAFETY_MODE,
      G_SPW_ST_BITS => G_SPW_ST_BITS, G_SPW_MT_BITS => G_SPW_MT_BITS
    )
    port map (
      clk => clk_75m, rst_n => rst_n, ma_in => ma_in, enable => cfg_enable,
      st_bits => cfg_st_bits, mt_bits => cfg_mt_bits, timeout_ticks => cfg_timeout_ticks,
      live_st => st, live_mt => mt,
      force_error => cfg_force_error, force_warning => cfg_force_warning,
      force_bad_crc => cfg_force_bad_crc, slo_out => slo_out,
      frame_idle => status_frame_idle, frame_count => status_frame_count,
      abort_count => status_abort_count
    );
  status_position_st <= st;
  status_position_mt <= mt;
end architecture;
