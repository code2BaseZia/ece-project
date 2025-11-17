library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cordic_unit is
	port (
		clk       : in  std_logic;
		resetn    : in  std_logic;
      start     : in  std_logic;
		busy      : out std_logic;
      done      : out std_logic;
		
      theta_in  : in  signed(15 downto 0);
		cos_out   : out signed(15 downto 0);
		sin_out   : out signed(15 downto 0);
		valid 	 : out std_logic
	);
end entity;

architecture rtl of cordic_unit is
	-- precomputed atan(2^-i) scaled by 2^<fraction bits>
	type atan_tab_t is array (0 to 15) of signed(15 downto 0);
	constant ATAN_TAB_16 : atan_tab_t := (
		to_signed(12868, 16), to_signed(7596, 16), to_signed(4014, 16), to_signed(2037, 16),
		to_signed(1023, 16), to_signed(512, 16), to_signed(256, 16), to_signed(128, 16),
		to_signed(64, 16), to_signed(32, 16), to_signed(16, 16), to_signed(8, 16),
		to_signed(4, 16), to_signed(2, 16), to_signed(1, 16), to_signed(0, 16)
	);
	
	-- CORDIC gain for 16 iterations scaled by 2^fraction bits>
	constant K_GAIN : signed(15 downto 0) := to_signed(9949, 16);
	
   type state_t is (IDLE, RUN, FINISH);
   signal st       : state_t := IDLE;
	signal busy_s   : std_logic := '0';
   signal done_s   : std_logic := '0';
	
	signal x, y, z  : signed(15 downto 0);
	signal x_n, y_n : signed(15 downto 0);
	signal z_n		 : signed(15 downto 0);
	
	signal count : integer range 0 to 31 := 0;
	
	signal cos_r, sin_r : signed(15 downto 0) := (others => '0');
	signal valid_r		  : std_logic := '0';
	
	function atan_i(i : integer) return signed is
		begin
		if i <= 15 then
			return ATAN_TAB_16(i);
		else
			return (others => '0'); -- not used
		end if;
	end function;
    
begin
   busy    <= busy_s;
   done    <= done_s;
   cos_out <= cos_r;
	sin_out <= sin_r;
	valid 	<= valid_r;

   process(clk, resetn)
   begin
		if resetn = '0' then
			st <= IDLE; 
			busy_s <= '0'; 
			done_s <= '0';
				
			x <= (others => '0');
			y <= (others => '0');
			z <= (others => '0');
				
			count <= 0;
			cos_r <= (others => '0');
			sin_r	<= (others => '0');
		elsif rising_edge(clk) then
			valid_r <= '0';
			done_s <= '0';
			
			case st is
				when IDLE =>
					busy_s <= '0';
               if start = '1' then
						st <= RUN;
						busy_s <= '1'; 
						done_s <= '0';
						
						x <= K_GAIN;
						y <= (others => '0');
						z <= theta_in;
						
						count <= 0;
               end if;
				when RUN =>
					-- decide direction by sign of z
					if z >= 0 then
						x_n <= x - shift_right(y, count);
						y_n <= y + shift_right(x, count);
						z_n <= z - atan_i(count);
					else
						x_n <= x + shift_right(y, count);
						y_n <= y - shift_right(x, count);
						z_n <= z + atan_i(count);
					end if;
					
					x <= x_n;
					y <= y_n;
					z <= z_n;
					
					if count = 15 then
						st <= FINISH;
					else
						count <= count + 1;
					end if;
				when FINISH =>
					cos_r <= x_n;
					sin_r <= y_n;
					valid_r <='1';
						  
					busy_s <= '0';
					done_s <= '1';
					st <= IDLE;
            end case;
        end if;
    end process;
end architecture;