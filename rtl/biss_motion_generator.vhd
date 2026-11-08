library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.biss_emulator_pkg.all;

entity biss_motion_generator is
  port (
    clk              : in  std_logic;
    rst_n            : in  std_logic;
    phase_increment  : in  unsigned(63 downto 0);
    direction_neg    : in  std_logic;
    mt_bits          : in  natural range 0 to 12;
    load_position    : in  std_logic;
    load_st           : in  unsigned(31 downto 0);
    load_mt           : in  unsigned(11 downto 0);
    single_turn       : out unsigned(31 downto 0);
    multi_turn        : out unsigned(11 downto 0)
  );
end entity;

architecture rtl of biss_motion_generator is
  signal phase : unsigned(63 downto 0) := (others => '0');
  signal turns : unsigned(11 downto 0) := (others => '0');
begin
  process(clk)
    variable next_phase : unsigned(63 downto 0);
    variable next_turns : unsigned(11 downto 0);
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        phase <= (others => '0'); turns <= (others => '0');
      elsif load_position = '1' then
        phase(63 downto 32) <= load_st;
        phase(31 downto 0) <= (others => '0');
        turns <= load_mt and mask_width(mt_bits, 12);
      else
        next_turns := turns;
        if direction_neg = '1' then
          if phase < phase_increment and mt_bits /= 0 then
            next_turns := (turns - 1) and mask_width(mt_bits, 12);
          end if;
          next_phase := phase - phase_increment;
        else
          next_phase := phase + phase_increment;
          if next_phase < phase and mt_bits /= 0 then
            next_turns := (turns + 1) and mask_width(mt_bits, 12);
          end if;
        end if;
        phase <= next_phase;
        turns <= next_turns;
      end if;
    end if;
  end process;
  single_turn <= phase(63 downto 32);
  multi_turn <= turns;
end architecture;
