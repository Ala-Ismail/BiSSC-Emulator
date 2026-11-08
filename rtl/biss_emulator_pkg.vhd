-- Copyright (c) 2026 Ala-Ismail
-- SPDX-License-Identifier: MIT
-- See LICENSE in the repository root for the full license text.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package biss_emulator_pkg is
  constant C_CLK_HZ : positive := 75_000_000;
  constant C_CRC6_POLY  : unsigned(5 downto 0)  := "000011"; -- x^6+x+1 (0x43)
  constant C_CRC16_POLY : unsigned(15 downto 0) := x"90D9";  -- x^16+x^15+x^12+x^7+x^6+x^4+x^3+1

  function crc6_step (crc : unsigned(5 downto 0); bit_in : std_logic) return unsigned;
  function crc16_step(crc : unsigned(15 downto 0); bit_in : std_logic) return unsigned;
  function mask_width(width : natural; maximum : natural) return unsigned;
end package;

package body biss_emulator_pkg is
  function crc6_step(crc : unsigned(5 downto 0); bit_in : std_logic) return unsigned is
    variable r : unsigned(5 downto 0);
    variable fb : std_logic;
  begin
    fb := crc(5) xor bit_in;
    r := crc(4 downto 0) & '0';
    if fb = '1' then r := r xor C_CRC6_POLY; end if;
    return r;
  end function;

  function crc16_step(crc : unsigned(15 downto 0); bit_in : std_logic) return unsigned is
    variable r : unsigned(15 downto 0);
    variable fb : std_logic;
  begin
    fb := crc(15) xor bit_in;
    r := crc(14 downto 0) & '0';
    if fb = '1' then r := r xor C_CRC16_POLY; end if;
    return r;
  end function;

  function mask_width(width : natural; maximum : natural) return unsigned is
    variable r : unsigned(maximum-1 downto 0) := (others => '0');
  begin
    for i in 0 to maximum-1 loop
      if i < width then r(i) := '1'; end if;
    end loop;
    return r;
  end function;

end package body;
