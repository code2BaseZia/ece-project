-- numcoproc.vhd : SCOMP numeric co-processor (MUL + DIV) @ 0x90..0x96

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity numcoproc is
    port (
        clock    : in  std_logic;
        resetn   : in  std_logic;
        io_addr  : in  std_logic_vector(10 downto 0);
        io_data  : inout std_logic_vector(15 downto 0);
        io_read  : in  std_logic;
        io_write : in  std_logic
    );
end entity;

architecture rtl of numcoproc is
    constant BASE_ADDR  : unsigned(10 downto 0) := to_unsigned(16#090#, 11);
    constant LAST_ADDR  : unsigned(10 downto 0) := to_unsigned(16#09F#, 11);

    constant OFF_CTRL   : unsigned(3 downto 0) := "0000"; -- 0x90
    constant OFF_OPA    : unsigned(3 downto 0) := "0001"; -- 0x91
    constant OFF_OPB    : unsigned(3 downto 0) := "0010"; -- 0x92
    constant OFF_STATUS : unsigned(3 downto 0) := "0011"; -- 0x93
    constant OFF_RESL   : unsigned(3 downto 0) := "0100"; -- 0x94
    constant OFF_RESH   : unsigned(3 downto 0) := "0101"; -- 0x95
    constant OFF_REM    : unsigned(3 downto 0) := "0110"; -- 0x96

    signal addr_u   : unsigned(10 downto 0);
    signal sel      : std_logic;
    signal offset   : unsigned(3 downto 0);

    signal data_in  : std_logic_vector(15 downto 0);
    signal data_out : std_logic_vector(15 downto 0);
    signal rd_oe    : std_logic;

    signal reg_ctrl, reg_status : std_logic_vector(15 downto 0) := (others => '0');
    constant ST_DONE : integer := 0;
    constant ST_BUSY : integer := 1;
    constant ST_DIV0 : integer := 2;

    signal reg_op_a, reg_op_b : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_res_lo, reg_res_hi, reg_rem : std_logic_vector(15 downto 0) := (others => '0');

    function ctrl_start  (v: std_logic_vector(15 downto 0)) return std_logic is begin return v(0); end;
    function ctrl_op_div (v: std_logic_vector(15 downto 0)) return std_logic is begin return v(1); end;
    function ctrl_signed (v: std_logic_vector(15 downto 0)) return std_logic is begin return v(2); end;

    signal div_start, div_busy, div_done : std_logic := '0';
    signal div_q, div_r : std_logic_vector(15 downto 0);

    signal start_pulse : std_logic := '0';
begin
    addr_u  <= unsigned(io_addr);
    sel     <= '1' when (addr_u >= BASE_ADDR and addr_u <= LAST_ADDR) else '0';
    offset  <= unsigned(io_addr(3 downto 0));
    data_in <= io_data;

    rd_oe   <= '1' when (sel = '1' and io_read = '1') else '0';
    io_data <= data_out when rd_oe = '1' else (others => 'Z');

    u_div : entity work.div_unit
      port map (
        clk        => clock,
        resetn     => resetn,
        start      => div_start,
        is_signed  => ctrl_signed(reg_ctrl),
        dividend   => reg_op_a,
        divisor    => reg_op_b,
        busy       => div_busy,
        done       => div_done,
        quotient   => div_q,
        remainder  => div_r
      );

    -- readback mux
    process(sel, offset, reg_ctrl, reg_op_a, reg_op_b, reg_status, reg_res_lo, reg_res_hi, reg_rem)
    begin
        data_out <= x"0000";
        if sel = '1' then
            case offset is
                when OFF_CTRL   => data_out <= reg_ctrl;
                when OFF_OPA    => data_out <= reg_op_a;
                when OFF_OPB    => data_out <= reg_op_b;
                when OFF_STATUS => data_out <= reg_status;
                when OFF_RESL   => data_out <= reg_res_lo;
                when OFF_RESH   => data_out <= reg_res_hi;
                when OFF_REM    => data_out <= reg_rem;
                when others     => data_out <= x"0000";
            end case;
        end if;
    end process;

    -- writes and operation control
    process(clock, resetn)
        variable prod32_u  : unsigned(31 downto 0);
        variable prod32_s  : signed(31 downto 0);
        variable start_now : std_logic;
    begin
        if resetn = '0' then
            reg_ctrl   <= (others => '0');  reg_status <= (others => '0');
            reg_op_a   <= (others => '0');  reg_op_b   <= (others => '0');
            reg_res_lo <= (others => '0');  reg_res_hi <= (others => '0');  reg_rem <= (others => '0');
            div_start  <= '0';              start_pulse <= '0';

        elsif rising_edge(clock) then
            div_start   <= '0';
            start_pulse <= '0';
            start_now   := '0';
            reg_status(ST_BUSY) <= '0';

            if (sel = '1' and io_write = '1') then
                case offset is
                    when OFF_CTRL =>
                        reg_ctrl <= data_in;
                        if ctrl_start(data_in) = '1' then
                            start_now := '1'; start_pulse <= '1';
                        end if;
                    when OFF_OPA => reg_op_a <= data_in;
                    when OFF_OPB => reg_op_b <= data_in;
                    when OFF_STATUS =>
                        if data_in(ST_DONE) = '1' then reg_status(ST_DONE) <= '0'; end if;
                        if data_in(ST_DIV0) = '1' then reg_status(ST_DIV0) <= '0'; end if;
                    when others => null;
                end case;
            end if;

            if start_now = '1' then
                reg_status(ST_DONE) <= '0'; reg_status(ST_DIV0) <= '0'; reg_status(ST_BUSY) <= '1';

                if ctrl_op_div(reg_ctrl) = '1' then
                    if reg_op_b = x"0000" then
                        reg_status(ST_BUSY) <= '0'; reg_status(ST_DONE) <= '1'; reg_status(ST_DIV0) <= '1';
                        reg_res_lo <= (others => '0'); reg_res_hi <= (others => '0'); reg_rem <= (others => '0');
                    else
                        div_start <= '1';
                    end if;
                else
                    if ctrl_signed(reg_ctrl) = '1' then
                        prod32_s := resize(signed(reg_op_a) * signed(reg_op_b), 32);
                        reg_res_lo <= std_logic_vector(prod32_s(15 downto 0));
                        reg_res_hi <= std_logic_vector(prod32_s(31 downto 16));
                    else
                        prod32_u := resize(unsigned(reg_op_a) * unsigned(reg_op_b), 32);
                        reg_res_lo <= std_logic_vector(prod32_u(15 downto 0));
                        reg_res_hi <= std_logic_vector(prod32_u(31 downto 16));
                    end if;
                    reg_rem <= (others => '0');
                    reg_status(ST_BUSY) <= '0'; reg_status(ST_DONE) <= '1';
                end if;
            end if;

            if div_busy = '1' then reg_status(ST_BUSY) <= '1'; end if;

            if div_done = '1' then
                reg_res_lo <= div_q; reg_res_hi <= (others => '0'); reg_rem <= div_r;
                reg_status(ST_BUSY) <= '0'; reg_status(ST_DONE) <= '1';
            end if;
        end if;
    end process;
end architecture;
