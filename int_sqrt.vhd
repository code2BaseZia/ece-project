library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sqrt_unsigned is
    generic (
        WIDTH : integer := 16  -- input bit width
    );
    port (
        clk     : in  std_logic;
        start   : in  std_logic;
        x       : in  unsigned(WIDTH-1 downto 0);
        root    : out unsigned((WIDTH/2)-1 downto 0);
        done    : out std_logic
    );
end entity;

architecture rtl of sqrt_unsigned is
    signal rem      : unsigned(WIDTH downto 0);
    signal root_reg : unsigned((WIDTH/2) downto 0);
    signal bit_mask : unsigned((WIDTH/2) downto 0);
    signal x_reg    : unsigned(WIDTH-1 downto 0);
    signal busy     : std_logic := '0';
begin

    process(clk)
    begin
        if rising_edge(clk) then
            if start = '1' and busy = '0' then
                busy <= '1';
                x_reg <= x;
                root_reg <= (others => '0');
                bit_mask <= (others => '0');
                bit_mask((WIDTH/2)) <= '1'; -- initialize top bit
                rem <= (others => '0');
                done <= '0';
            elsif busy = '1' then
                if bit_mask = 0 then
                    busy <= '0';
                    done <= '1';
                    root <= root_reg((WIDTH/2)-1 downto 0);
                else
                    rem <= shift_left(rem, 2);
                    rem(WIDTH-1 downto WIDTH-2) <= x_reg(WIDTH-1 downto WIDTH-2);
                    x_reg <= shift_left(x_reg, 2);

                    if rem >= (shift_left(root_reg, 1) + bit_mask) then
                        rem <= rem - (shift_left(root_reg, 1) + bit_mask);
                        root_reg <= shift_right(root_reg, 1) + bit_mask;
                    else
                        root_reg <= shift_right(root_reg, 1);
                    end if;

                    bit_mask <= shift_right(bit_mask, 1);
                end if;
            end if;
        end if;
    end process;

end architecture;
