library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mul_unit is
    port (
        clk       : in  std_logic;
        resetn    : in  std_logic;
        start     : in  std_logic;
        is_signed : in  std_logic;
        op_a      : in  std_logic_vector(15 downto 0);
        op_b      : in  std_logic_vector(15 downto 0);
        busy      : out std_logic;
        done      : out std_logic;
        prod_lo   : out std_logic_vector(15 downto 0);
        prod_hi   : out std_logic_vector(15 downto 0)
    );
end entity;

architecture rtl of mul_unit is
    type state_t is (IDLE, RUN, FINISH);
    signal st       : state_t := IDLE;

    signal A_abs    : unsigned(15 downto 0) := (others => '0');
    signal B_abs    : unsigned(15 downto 0) := (others => '0');
    signal sign_p   : std_logic := '0';

    signal mcand    : unsigned(31 downto 0) := (others => '0');  -- shifted multiplicand
    signal mplier   : unsigned(15 downto 0) := (others => '0');  -- shifting multiplier
    signal prod_reg : unsigned(31 downto 0) := (others => '0');  -- running product
    signal bit_cnt  : integer range 0 to 16 := 0;

    signal busy_s   : std_logic := '0';
    signal done_s   : std_logic := '0';
    signal lo_out   : std_logic_vector(15 downto 0) := (others => '0');
    signal hi_out   : std_logic_vector(15 downto 0) := (others => '0');

    function to_abs16(v : std_logic_vector(15 downto 0)) return unsigned is
    begin
        if v(15) = '1' then
            return unsigned(-signed(v));
        else
            return unsigned(v);
        end if;
    end function;
begin
    busy    <= busy_s;
    done    <= done_s;
    prod_lo <= lo_out;
    prod_hi <= hi_out;

    process(clk, resetn)
        variable prod_signed : signed(31 downto 0);
        variable prod_u      : unsigned(31 downto 0);
        variable abs_a       : unsigned(15 downto 0);
        variable abs_b       : unsigned(15 downto 0);
    begin
        if resetn = '0' then
            st       <= IDLE;
            busy_s   <= '0';
            done_s   <= '0';
            A_abs    <= (others => '0');
            B_abs    <= (others => '0');
            sign_p   <= '0';
            mcand    <= (others => '0');
            mplier   <= (others => '0');
            prod_reg <= (others => '0');
            bit_cnt  <= 0;
            lo_out   <= (others => '0');
            hi_out   <= (others => '0');

        elsif rising_edge(clk) then
            done_s <= '0';

            case st is
                when IDLE =>
                    busy_s <= '0';
                    if start = '1' then
                        -- Determine magnitudes and sign
                        if is_signed = '1' then
                            abs_a := to_abs16(op_a);
                            abs_b := to_abs16(op_b);
                            sign_p <= op_a(15) xor op_b(15);
                        else
                            abs_a := unsigned(op_a);
                            abs_b := unsigned(op_b);
                            sign_p <= '0';
                        end if;

                        A_abs    <= abs_a;
                        B_abs    <= abs_b;
                        mcand    <= resize(abs_a, 32);  -- multiplicand in lower bits
                        mplier   <= abs_b;
                        prod_reg <= (others => '0');
                        bit_cnt  <= 16;
                        busy_s   <= '1';
                        st       <= RUN;
                    end if;

                when RUN =>
                    if bit_cnt > 0 then
                        -- Classic shift-add multiply
                        if mplier(0) = '1' then
                            prod_reg <= prod_reg + mcand;
                        end if;

                        mcand   <= shift_left(mcand, 1);
                        mplier  <= shift_right(mplier, 1);
                        bit_cnt <= bit_cnt - 1;

                        if bit_cnt = 1 then
                            st <= FINISH;
                        end if;
                    else
                        st <= FINISH;
                    end if;

                when FINISH =>
                    -- Apply final sign to 32-bit product
                    if sign_p = '1' then
                        prod_signed := -signed(prod_reg);
                    else
                        prod_signed := signed(prod_reg);
                    end if;

                    prod_u := unsigned(prod_signed);
                    lo_out <= std_logic_vector(prod_u(15 downto 0));
                    hi_out <= std_logic_vector(prod_u(31 downto 16));

                    busy_s <= '0';
                    done_s <= '1';
                    st     <= IDLE;
            end case;
        end if;
    end process;
end architecture;
