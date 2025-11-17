library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cordic_sincos is
  generic (
    WIDTH : integer := 16;  -- total bits
    FRAC  : integer := 14;  -- fractional bits (Qm.FRAC)
    ITER  : integer := 16   -- iterations (≤ WIDTH)
  );
  port (
    clk      : in  std_logic;
    rst_n    : in  std_logic;                          -- active-low sync reset
    start    : in  std_logic;                          -- pulse to start
    theta_in : in  signed(WIDTH-1 downto 0);           -- angle in radians * 2^FRAC
    cos_out  : out signed(WIDTH-1 downto 0);           -- cos(theta)
    sin_out  : out signed(WIDTH-1 downto 0);           -- sin(theta)
    valid    : out std_logic                           -- high for 1 cycle when outputs ready
  );
end entity;

architecture rtl of cordic_sincos is
  -- Precomputed atan(2^-i) scaled by 2^FRAC for FRAC=14 (re-sliced to WIDTH at elaboration).
  -- Values for i=0..15: [12868, 7596, 4014, 2037, 1023, 512, 256, 128, 64, 32, 16, 8, 4, 2, 1, 0]
  type atan_tab_t is array (0 to 15) of signed(WIDTH-1 downto 0);
  constant ATAN_TAB_16 : atan_tab_t := (
    to_signed(12868, WIDTH), to_signed( 7596, WIDTH), to_signed(4014, WIDTH), to_signed(2037, WIDTH),
    to_signed( 1023, WIDTH), to_signed(  512, WIDTH), to_signed( 256, WIDTH), to_signed( 128, WIDTH),
    to_signed(   64, WIDTH), to_signed(   32, WIDTH), to_signed(  16, WIDTH), to_signed(   8, WIDTH),
    to_signed(    4, WIDTH), to_signed(    2, WIDTH), to_signed(   1, WIDTH), to_signed(   0, WIDTH)
  );

  -- CORDIC gain for 16 iterations, scaled by 2^FRAC (FRAC=14 → 9949)
  constant K_GAIN : signed(WIDTH-1 downto 0) := to_signed(9949, WIDTH);

  type state_t is (IDLE, RUN);
  signal st       : state_t := IDLE;

  signal x, y, z  : signed(WIDTH-1 downto 0);
  signal x_n, y_n : signed(WIDTH-1 downto 0);
  signal z_n      : signed(WIDTH-1 downto 0);

  signal i_cnt    : integer range 0 to 31 := 0;

  signal cos_r, sin_r : signed(WIDTH-1 downto 0) := (others => '0');
  signal valid_r      : std_logic := '0';

  -- Helper to get atan table entry i (protect if ITER < 16)
  function atan_i(i : integer) return signed is
  begin
    if i <= 15 then
      return ATAN_TAB_16(i);
    else
      return (others => '0'); -- not used
    end if;
  end function;

begin
  cos_out <= cos_r;
  sin_out <= sin_r;
  valid   <= valid_r;

  process(clk)
  begin
    if rising_edge(clk) then
      valid_r <= '0';

      if rst_n = '0' then
        st    <= IDLE;
        x     <= (others => '0');
        y     <= (others => '0');
        z     <= (others => '0');
        i_cnt <= 0;
        cos_r <= (others => '0');
        sin_r <= (others => '0');
      else
        case st is
          when IDLE =>
            if start = '1' then
              -- Initialize vector to (K, 0), angle = theta_in
              x     <= K_GAIN;
              y     <= (others => '0');
              z     <= theta_in;
              i_cnt <= 0;
              st    <= RUN;
            end if;

          when RUN =>
            -- Decide direction by sign of z
            if z >= 0 then
              x_n <= x - shift_right(y, i_cnt);
              y_n <= y + shift_right(x, i_cnt);
              z_n <= z - atan_i(i_cnt);
            else
              x_n <= x + shift_right(y, i_cnt);
              y_n <= y - shift_right(x, i_cnt);
              z_n <= z + atan_i(i_cnt);
            end if;

            -- Commit this iteration
            x <= x_n;
            y <= y_n;
            z <= z_n;

            if i_cnt = (ITER - 1) then
              -- Done
              cos_r  <= x_n;  -- cos(theta)
              sin_r  <= y_n;  -- sin(theta)
              valid_r <= '1';
              st     <= IDLE;
            else
              i_cnt <= i_cnt + 1;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
