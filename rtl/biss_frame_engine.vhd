library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.biss_emulator_pkg.all;

entity biss_frame_engine is
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
  type state_t is (IDLE, ACK, STR, CDS, DATA, STATUS_E, STATUS_W, CRC, STOP, TIMEOUT);
  signal state : state_t := IDLE;
  signal ma_meta, ma_sync, ma_last : std_logic := '1';
  signal st_snap : unsigned(31 downto 0) := (others => '0');
  signal mt_snap : unsigned(11 downto 0) := (others => '0');
  signal crc_snap : unsigned(5 downto 0) := (others => '0');
  signal data_index : natural range 0 to 44 := 0;
  signal crc_index : natural range 0 to 5 := 0;
  signal quiet_count : unsigned(23 downto 0) := (others => '0');
  signal slo_r : std_logic := '1';
  signal frames_r, aborts_r : unsigned(31 downto 0) := (others => '0');
begin
  process(clk)
    variable ma_rise : boolean;
    variable c : unsigned(5 downto 0);
    variable b : std_logic;
    variable pos_len : natural;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        ma_meta <= '1'; ma_sync <= '1'; ma_last <= '1'; state <= IDLE;
        slo_r <= '1'; quiet_count <= (others => '0'); frames_r <= (others => '0'); aborts_r <= (others => '0');
      else
        ma_meta <= ma_in; ma_sync <= ma_meta; ma_last <= ma_sync;
        ma_rise := (ma_sync = '1' and ma_last = '0');
        if ma_rise then
          quiet_count <= (others => '0');
        elsif state /= IDLE then
          quiet_count <= quiet_count + 1;
        end if;

        -- A missing MA edge before stop terminates an incomplete frame.
        if state /= IDLE and state /= TIMEOUT and quiet_count >= timeout_ticks then
          state <= IDLE; slo_r <= '1'; aborts_r <= aborts_r + 1;
        elsif state = TIMEOUT then
          if quiet_count >= timeout_ticks then state <= IDLE; slo_r <= '1'; end if;
        elsif ma_rise then
          pos_len := st_bits + mt_bits;
          case state is
            when IDLE =>
              slo_r <= '1';
              if enable = '1' then
                st_snap <= live_st; mt_snap <= live_mt;
                c := (others => '0');
                for i in 0 to 11 loop
                  if i < mt_bits then c := crc6_step(c, live_mt(mt_bits-1-i)); end if;
                end loop;
                for i in 0 to 31 loop
                  if i < st_bits then c := crc6_step(c, live_st(st_bits-1-i)); end if;
                end loop;
                if force_error = '1' then c := crc6_step(c, '0'); else c := crc6_step(c, '1'); end if;
                if force_warning = '1' then c := crc6_step(c, '0'); else c := crc6_step(c, '1'); end if;
                crc_snap <= c; state <= ACK;
              end if;
            when ACK => slo_r <= '0'; state <= STR;
            when STR => slo_r <= '1'; state <= CDS;
            when CDS => slo_r <= '0'; data_index <= 0; state <= DATA;
            when DATA =>
              if data_index < mt_bits then b := mt_snap(mt_bits-1-data_index);
              else b := st_snap(st_bits-1-(data_index-mt_bits)); end if;
              slo_r <= b;
              if data_index = pos_len-1 then state <= STATUS_E; else data_index <= data_index + 1; end if;
            when STATUS_E =>
              if force_error = '1' then slo_r <= '0'; else slo_r <= '1'; end if;
              state <= STATUS_W;
            when STATUS_W =>
              if force_warning = '1' then slo_r <= '0'; else slo_r <= '1'; end if;
              crc_index <= 0; state <= CRC;
            when CRC =>
              b := not crc_snap(5-crc_index);
              if force_bad_crc = '1' and crc_index = 5 then b := not b; end if;
              slo_r <= b;
              if crc_index = 5 then state <= STOP; else crc_index <= crc_index + 1; end if;
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
