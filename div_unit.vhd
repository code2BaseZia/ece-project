library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity div_unit is
    port (
        clk       : in  std_logic;
        resetn    : in  std_logic;
        start     : in  std_logic;
        is_signed : in  std_logic;
        dividend  : in  std_logic_vector(15 downto 0);
        divisor   : in  std_logic_vector(15 downto 0);
        busy      : out std_logic;
        done      : out std_logic;
        quotient  : out std_logic_vector(15 downto 0);
        remainder : out std_logic_vector(15 downto 0)
    );
end entity;

architecture rtl of div_unit is
    type state_t is (IDLE, RUN, FINISH);
    signal st      : state_t := IDLE;

    signal A_abs   : unsigned(15 downto 0) := (others => '0');
    signal B_abs   : unsigned(15 downto 0) := (others => '0');
    signal sign_q  : std_logic := '0';
    signal sign_r  : std_logic := '0';

    signal rem_reg : signed(16 downto 0) := (others => '0');
    signal quo_reg : unsigned(15 downto 0) := (others => '0');
    signal div_reg : unsigned(15 downto 0) := (others => '0');
    signal bit_cnt : integer range 0 to 16 := 0;

    signal busy_s  : std_logic := '0';
    signal done_s  : std_logic := '0';
    signal q_out   : std_logic_vector(15 downto 0) := (others => '0');
    signal r_out   : std_logic_vector(15 downto 0) := (others => '0');

    function to_abs16(v : std_logic_vector(15 downto 0)) return unsigned is
    begin
        if v(15) = '1' then
            return unsigned(-signed(v));
        else
            return unsigned(v);
        end if;
    end function;
begin
    busy      <= busy_s;
    done      <= done_s;
    quotient  <= q_out;
    remainder <= r_out;

    process(clk, resetn)
        variable rem_next : signed(16 downto 0);
    begin
        if resetn = '0' then
            st <= IDLE; busy_s <= '0'; done_s <= '0';
            A_abs <= (others => '0'); B_abs <= (others => '0');
            sign_q <= '0'; sign_r <= '0';
            rem_reg <= (others => '0'); quo_reg <= (others => '0');
            div_reg <= (others => '0'); bit_cnt <= 0;
            q_out <= (others => '0'); r_out <= (others => '0');

        elsif rising_edge(clk) then
            done_s <= '0';
            case st is
                when IDLE =>
                    busy_s <= '0';
                    if start = '1' then
                        if is_signed = '1' then
                            A_abs  <= to_abs16(dividend);
                            B_abs  <= to_abs16(divisor);
                            sign_q <= dividend(15) xor divisor(15);
                            sign_r <= dividend(15);
                        else
                            A_abs  <= unsigned(dividend);
                            B_abs  <= unsigned(divisor);
                            sign_q <= '0';
                            sign_r <= '0';
                        end if;

                        if unsigned(divisor) = to_unsigned(0,16) then
                            q_out <= (others => '0'); r_out <= (others => '0');
                            busy_s <= '0'; done_s <= '1'; st <= IDLE;
                        else
                            rem_reg <= (others => '0'); quo_reg <= (others => '0');
                            div_reg <= unsigned(divisor); bit_cnt <= 16;
                            busy_s <= '1'; st <= RUN;
                        end if;
                    end if;

                when RUN =>
                    rem_next := shift_left(rem_reg, 1);
                    rem_next(0) := std_logic(A_abs(bit_cnt-1));

                    if (rem_next - signed('0' & B_abs)) >= to_signed(0,17) then
                        rem_reg <= rem_next - signed('0' & B_abs);
                        quo_reg <= shift_left(quo_reg, 1) + to_unsigned(1,16);
                    else
                        rem_reg <= rem_next;
                        quo_reg <= shift_left(quo_reg, 1);
                    end if;

                    bit_cnt <= bit_cnt - 1;
                    if bit_cnt = 1 then st <= FINISH; end if;

                when FINISH =>
                    if sign_q = '1' then
                        q_out <= std_logic_vector(-signed(quo_reg));
                    else
                        q_out <= std_logic_vector(quo_reg);
                    end if;

                    if sign_r = '1' then
                        r_out <= std_logic_vector(-signed(rem_reg(15 downto 0)));
                    else
                        r_out <= std_logic_vector(rem_reg(15 downto 0));
                    end if;

                    busy_s <= '0'; done_s <= '1'; st <= IDLE;
            end case;
        end if;
    end process;
end architecture;
