-- Copyright (c) 2026 Ala-Ismail
-- SPDX-License-Identifier: MIT
-- See LICENSE in the repository root for the full license text.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_biss_frame_engine is
  generic (
    G_SAFETY_MODE : boolean := false;
    G_SPW_ST_BITS : positive := 18;
    G_SPW_MT_BITS : natural := 0
  );
end entity;

architecture test of tb_biss_frame_engine is
  signal clk : std_logic := '0';
  signal rst_n, enable : std_logic := '0';
  signal ma : std_logic := '1';
  signal slo, idle : std_logic;
  signal st_bits : natural range 18 to 32 := 32;
  signal mt_bits : natural range 0 to 12 := 12;
  signal st : unsigned(31 downto 0) := x"A5793C81";
  signal mt : unsigned(11 downto 0) := x"A53";
  signal err, warn, bad_crc : std_logic := '0';
  signal timeout_ticks : unsigned(23 downto 0) := to_unsigned(1500, 24);
  signal frames, aborts : unsigned(31 downto 0);

  -- Independent reference: polynomial long division of the complete message
  -- with zero padding. Does not call the RTL CRC step functions.
  function reference_crc(data : std_logic_vector; polynomial : std_logic_vector)
    return std_logic_vector is
    constant width : positive := polynomial'length-1;
    variable dividend : std_logic_vector(data'length+width-1 downto 0) := (others => '0');
  begin
    dividend(dividend'high downto width) := data;
    for i in dividend'high downto width loop
      if dividend(i) = '1' then
        dividend(i downto i-width) := dividend(i downto i-width) xor polynomial;
      end if;
    end loop;
    return not dividend(width-1 downto 0);
  end function;
begin
  clk <= not clk after 6.666 ns;
  process
  begin
    wait for 150 ms;
    assert false report "Testbench watchdog expired" severity failure;
    wait;
  end process;
  dut : entity work.biss_frame_engine
    generic map (G_SAFETY_MODE, G_SPW_ST_BITS, G_SPW_MT_BITS)
    port map (clk, rst_n, ma, enable, st_bits, mt_bits, timeout_ticks,
              st, mt, err, warn, bad_crc, slo, idle, frames, aborts);

  process
    variable half_period : time := 500 ns;
    variable expected : std_logic_vector(0 to 127);
    variable used, cpw_end, spw_start, expected_lc : natural := 0;
    variable completed, aborted : natural := 0;
    variable crc6 : std_logic_vector(5 downto 0);
    variable crc16 : std_logic_vector(15 downto 0);
    variable captured : std_logic;

    procedure pulse(variable bit_out : out std_logic) is
    begin
      ma <= '0'; wait for half_period;
      ma <= '1'; wait for 45 ns;
      bit_out := slo;
      wait for half_period-45 ns;
    end procedure;

    procedure reset is
    begin
      rst_n <= '0'; ma <= '1'; wait for 200 ns;
      rst_n <= '1'; wait for 100 ns;
      expected_lc := 1; completed := 0; aborted := 0;
      assert slo = '1' and idle = '1' and frames = 0 and aborts = 0
        report "Reset failed" severity failure;
    end procedure;

    procedure append(value : std_logic_vector) is
    begin
      for i in value'range loop expected(used) := value(i); used := used+1; end loop;
    end procedure;

    procedure make_expected is
    begin
      used := 0;
      append("010"); -- ACK, STR, CDS
      for i in mt_bits-1 downto 0 loop append(std_logic_vector(mt(i downto i))); end loop;
      for i in 31 downto 32-st_bits loop append(std_logic_vector(st(i downto i))); end loop;
      append(std_logic_vector'(0 => not err)); append(std_logic_vector'(0 => not warn));
      cpw_end := used;
      crc6 := reference_crc(expected(3 to cpw_end-1), "1000011");
      if bad_crc = '1' then crc6(0) := not crc6(0); end if;
      append(crc6);
      if G_SAFETY_MODE then
        spw_start := used;
        for i in mt_bits-1 downto mt_bits-G_SPW_MT_BITS loop
          append(std_logic_vector(mt(i downto i)));
        end loop;
        for i in 31 downto 32-G_SPW_ST_BITS loop append(std_logic_vector(st(i downto i))); end loop;
        append(std_logic_vector'(0 => not err)); append(std_logic_vector'(0 => not warn));
        append(std_logic_vector(to_unsigned(expected_lc, 6)));
        crc16 := reference_crc(expected(spw_start to used-1), '1' & x"90D9");
        if bad_crc = '1' then crc16(0) := not crc16(0); end if;
        append(crc16);
      end if;
      append("0"); -- STP
    end procedure;

    procedure finish_timeout is
    begin
      wait for 21 us;
      assert idle = '1' and slo = '1' report "Timeout did not release SLO" severity failure;
      assert frames = completed and aborts = aborted report "Frame counters differ" severity failure;
    end procedure;

    procedure frame(mutate : boolean := false) is
    begin
      make_expected;
      pulse(captured); -- LAT
      assert captured = '1' and idle = '0' report "LAT not accepted" severity failure;
      if G_SAFETY_MODE then expected_lc := (expected_lc mod 63)+1; end if;
      if mutate then
        -- All active frame fields must survive changing live inputs after LAT.
        st <= not st; mt <= not mt; err <= not err; warn <= not warn;
        bad_crc <= not bad_crc; st_bits <= 18; mt_bits <= 0;
        timeout_ticks <= to_unsigned(1, 24); enable <= '0';
      end if;
      for i in 0 to used-1 loop
        pulse(captured);
        assert captured = expected(i)
          report "Serial bit mismatch at " & integer'image(i) &
                 " safety=" & boolean'image(G_SAFETY_MODE) severity failure;
      end loop;
      completed := completed+1;
      assert frames = completed and idle = '0' report "STP/count incorrect" severity failure;
      finish_timeout;
    end procedure;
  begin
    reset; enable <= '1'; wait for 100 ns;
    -- All CPW widths at all supported MA rates; includes MT omission.
    for rate in 0 to 3 loop
      case rate is
        when 0 => half_period := 500 ns;
        when 1 => half_period := 250 ns;
        when 2 => half_period := 100 ns;
        when others => half_period := 50 ns;
      end case;
      for s in 18 to 32 loop
        for m in 0 to 12 loop
          if not G_SAFETY_MODE or (G_SPW_ST_BITS <= s and G_SPW_MT_BITS <= m) then
            st_bits <= s; mt_bits <= m; wait for 100 ns; frame;
          end if;
        end loop;
      end loop;
    end loop;
    half_period := 50 ns;
    st_bits <= 32; mt_bits <= 12; wait for 100 ns;
    -- More than one full LC cycle, with independently checked CRC16 each time.
    for i in 1 to 65 loop frame; end loop;
    err <= '1'; wait for 100 ns; frame;
    err <= '0'; warn <= '1'; wait for 100 ns; frame;
    err <= '1'; bad_crc <= '1'; wait for 100 ns; frame;
    err <= '0'; warn <= '0'; bad_crc <= '0'; wait for 100 ns;
    frame(true);
    enable <= '1'; timeout_ticks <= to_unsigned(1500, 24);
    st_bits <= 32; mt_bits <= 12; wait for 100 ns;
    -- Interrupt both an early CPW and a late SPW (or standard CRC).
    for late in 0 to 1 loop
      make_expected; pulse(captured);
      if G_SAFETY_MODE then expected_lc := (expected_lc mod 63)+1; end if;
      if late = 0 then pulse(captured);
      else
        for i in 0 to used-4 loop pulse(captured); end loop;
      end if;
      aborted := aborted+1; finish_timeout; frame;
    end loop;
    enable <= '0'; wait for 100 ns;
    for i in 1 to 8 loop
      pulse(captured);
      assert captured = '1' and idle = '1' report "Disabled core responded" severity failure;
    end loop;
    enable <= '1'; timeout_ticks <= (others => '0'); wait for 100 ns;
    pulse(captured);
    assert idle = '1' and captured = '1' report "Zero timeout accepted" severity failure;
    timeout_ticks <= to_unsigned(1500, 24);
    if G_SAFETY_MODE and (G_SPW_ST_BITS > 18 or G_SPW_MT_BITS > 0) then
      st_bits <= 18; mt_bits <= 0; wait for 100 ns;
      for i in 1 to 8 loop
        pulse(captured);
        assert idle = '1' and captured = '1' report "Incompatible widths accepted" severity failure;
      end loop;
    end if;
    st_bits <= 32; mt_bits <= 12; wait for 100 ns; frame;
    pulse(captured); pulse(captured); -- reset in a partially transmitted frame
    reset; enable <= '1'; wait for 100 ns; frame;
    report "PASS: frame format, independent CRCs, LC, widths, rates, faults, snapshot, abort, reset" severity note;
    finish;
  end process;
end architecture;
