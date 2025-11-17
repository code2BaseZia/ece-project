library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cordic_unit is
    port (
        clk       : in  std_logic;
        resetn    : in  std_logic;
        start     : in  std_logic;
        root_in  	: in  unsigned(15 downto 0);
        busy      : out std_logic;
        done      : out std_logic;
        output  	: out unsigned(15 downto 0)
    );
end entity;

architecture rtl of cordic_unit is
    type state_t is (IDLE, RUN, FINISH);
    signal st      : state_t := IDLE;
	 signal busy_s  : std_logic := '0';
    signal done_s  : std_logic := '0'; 

    signal remainder : unsigned(15 downto 0) := (others => '0');
	 signal root 		: unsigned(7 downto 0) := (others => '0');
    signal count 		: integer range 0 to 7 := 0;
	 
	 signal root_out   : unsigned(15 downto 0) := (others => '0');

    
begin
    busy      <= busy_s;
    done      <= done_s;
    output    <= root_out;

    process(clk, resetn)
        --variable rem_next : signed(16 downto 0);
    begin
        if resetn = '0' then
            st <= IDLE; 
				busy_s <= '0'; 
				done_s <= '0';
				
            remainder <= (others => '0'); 
				root <= (others => '0');
            count <= 0; 
				
				root_out <= (others => '0');
        elsif rising_edge(clk) then
            done_s <= '0';
            case st is
                when IDLE =>
                    busy_s <= '0';
                    if start = '1' then
								st <= RUN;
								busy_s <= '1'; 
								done_s <= '0';	
								
								remainder <= (others => '0'); 
								root <= (others => '0');
								count <= 7;
                    end if;

                when RUN =>
						  -- shift remainder left by 2 and bring in next 2 bits from root_in
						  remainder <= shift_left(remainder, 2);
						  remainder(1 downto 0) <= root_in(15 downto 14);
						  root <= shift_left(root, 2);
						  
						  -- trial subtraction
						  if remainder >= ((shift_left(root, 2)) + 1) then
								remainder <= remainder - ((shift_left(root, 2)) + 1);
								root <= shift_left(root, 1) + 1;
						  else
							   root <= shift_left(root, 1);
						  end if;
						  
						  if count = 0 then
							   st <= FINISH;
						  else
							   count <= count - 1;
						  end if;

                when FINISH =>
						  root_out <= root(7 downto 0);
						  
						  busy_s <= '0';
						  done_s <= '1';
						  st <= IDLE;
            end case;
        end if;
    end process;
end architecture;