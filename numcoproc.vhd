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
    --------------------------------------------------------------------------
    -- Address map (0x90–0x9F)
    --
    -- 0x90 : CTRL / STATUS
    -- 0x91 : (unused / reserved, reads as 0)
    -- 0x92 : OP_A   (A / NUM / IN / ANG)
    -- 0x93 : OP_B   (B / DEN)
    -- 0x94 : MUL_LO
    -- 0x95 : MUL_HI
    -- 0x96 : DIV_QUO
    -- 0x97 : DIV_REM
    -- 0x98 : SQRT_OUT
    -- 0x99 : CORDIC_SIN   (currently cordic_unit output)
    -- 0x9A : CORDIC_COS   (placeholder, currently 0)
    --------------------------------------------------------------------------

    constant BASE_ADDR  : unsigned(10 downto 0) := to_unsigned(16#090#, 11);
    constant LAST_ADDR  : unsigned(10 downto 0) := to_unsigned(16#09F#, 11);

    constant OFF_CTRL      : unsigned(3 downto 0) := "0000"; -- 0x90
    constant OFF_UNUSED    : unsigned(3 downto 0) := "0001"; -- 0x91
    constant OFF_OPA       : unsigned(3 downto 0) := "0010"; -- 0x92
    constant OFF_OPB       : unsigned(3 downto 0) := "0011"; -- 0x93
    constant OFF_MUL_LO    : unsigned(3 downto 0) := "0100"; -- 0x94
    constant OFF_MUL_HI    : unsigned(3 downto 0) := "0101"; -- 0x95
    constant OFF_DIV_QUO   : unsigned(3 downto 0) := "0110"; -- 0x96
    constant OFF_DIV_REM   : unsigned(3 downto 0) := "0111"; -- 0x97
    constant OFF_SQRT_OUT  : unsigned(3 downto 0) := "1000"; -- 0x98
    constant OFF_CORDIC_SIN: unsigned(3 downto 0) := "1001"; -- 0x99
    constant OFF_CORDIC_COS: unsigned(3 downto 0) := "1010"; -- 0x9A

    --------------------------------------------------------------------------
    -- CTRL / STATUS bits
    -- bit 0 : START (write 1 to begin operation)
    -- bit 1 : OP_DIV       (1 = DIV, 0 = MUL unless SQRT/CORDIC selected)
    -- bit 2 : SIGNED       (1 = signed, 0 = unsigned) for MUL/DIV
    -- bit 3 : OP_SQRT      (1 = SQRT)
    -- bit 4 : OP_CORDIC    (1 = CORDIC)
    --
    -- Status bits (always reported in these positions on read of CTRL/STATUS):
    -- ST_DONE : 0
    -- ST_BUSY : 1
    -- ST_DIV0 : 2 (set for divide-by-zero)
    --------------------------------------------------------------------------

    signal addr_u   : unsigned(10 downto 0);
    signal sel      : std_logic;
    signal offset   : unsigned(3 downto 0);

    signal data_in  : std_logic_vector(15 downto 0);
    signal data_out : std_logic_vector(15 downto 0);
    signal rd_oe    : std_logic;

    signal reg_ctrl   : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_status : std_logic_vector(15 downto 0) := (others => '0');
    constant ST_DONE  : integer := 0;
    constant ST_BUSY  : integer := 1;
    constant ST_DIV0  : integer := 2;

    signal reg_op_a      : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_op_b      : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_mul_lo    : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_mul_hi    : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_div_q     : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_div_r     : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_sqrt_out  : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_cordic_sin: std_logic_vector(15 downto 0) := (others => '0');
    signal reg_cordic_cos: std_logic_vector(15 downto 0) := (others => '0');

    -- Control helper functions
    function ctrl_start   (v: std_logic_vector(15 downto 0)) return std_logic is
    begin
        return v(0);
    end function;

    function ctrl_op_div  (v: std_logic_vector(15 downto 0)) return std_logic is
    begin
        return v(1);
    end function;

    function ctrl_signed  (v: std_logic_vector(15 downto 0)) return std_logic is
    begin
        return v(2);
    end function;

    function ctrl_op_sqrt (v: std_logic_vector(15 downto 0)) return std_logic is
    begin
        return v(3);
    end function;

    function ctrl_op_cordic (v: std_logic_vector(15 downto 0)) return std_logic is
    begin
        return v(4);
    end function;

    --------------------------------------------------------------------------
    -- Engine control / handshake
    --------------------------------------------------------------------------
    signal mul_start   : std_logic := '0';
    signal mul_busy    : std_logic;
    signal mul_done    : std_logic;
    signal mul_lo      : std_logic_vector(15 downto 0);
    signal mul_hi      : std_logic_vector(15 downto 0);
    signal mul_active  : std_logic := '0';

    signal div_start   : std_logic := '0';
    signal div_busy    : std_logic;
    signal div_done    : std_logic;
    signal div_q       : std_logic_vector(15 downto 0);
    signal div_r       : std_logic_vector(15 downto 0);
    signal div_active  : std_logic := '0';

    signal sqrt_start  : std_logic := '0';
    signal sqrt_busy   : std_logic;
    signal sqrt_done   : std_logic;
    signal sqrt_out_u  : unsigned(15 downto 0);
    signal sqrt_active : std_logic := '0';

    signal cordic_start  : std_logic := '0';
    signal cordic_busy   : std_logic;
    signal cordic_done   : std_logic;
    signal cordic_cos_s  : signed(15 downto 0);
    signal cordic_sin_s  : signed(15 downto 0);
    signal cordic_valid  : std_logic;
    signal cordic_active : std_logic := '0';
begin
    ----------------------------------------------------------------------
    -- Address decode and IO bus interface
    ----------------------------------------------------------------------
    addr_u  <= unsigned(io_addr);
    sel     <= '1' when (addr_u >= BASE_ADDR and addr_u <= LAST_ADDR) else '0';
    offset  <= unsigned(io_addr(3 downto 0));
    data_in <= io_data;

    rd_oe   <= '1' when (sel = '1' and io_read = '1') else '0';
    io_data <= data_out when rd_oe = '1' else (others => 'Z');

    ----------------------------------------------------------------------
    -- Engine instantiations
    ----------------------------------------------------------------------

    -- Multiplier
    u_mul : entity work.mul_unit
        port map (
            clk       => clock,
            resetn    => resetn,
            start     => mul_start,
            is_signed => ctrl_signed(reg_ctrl),
            op_a      => reg_op_a,
            op_b      => reg_op_b,
            busy      => mul_busy,
            done      => mul_done,
            prod_lo   => mul_lo,
            prod_hi   => mul_hi
        );

    -- Divider
    u_div : entity work.div_unit
        port map (
            clk       => clock,
            resetn    => resetn,
            start     => div_start,
            is_signed => ctrl_signed(reg_ctrl),
            dividend  => reg_op_a,
            divisor   => reg_op_b,
            busy      => div_busy,
            done      => div_done,
            quotient  => div_q,
            remainder => div_r
        );

    -- Integer square root unit
    u_sqrt : entity work.sqrt_unit
        port map (
            clk      => clock,
            resetn   => resetn,
            start    => sqrt_start,
            root_in  => unsigned(reg_op_a),
            busy     => sqrt_busy,
            done     => sqrt_done,
            output   => sqrt_out_u
        );

    -- CORDIC unit (sine and cosine outputs)
    u_cordic : entity work.cordic_unit
        port map (
            clk      => clock,
            resetn   => resetn,
            start    => cordic_start,
            busy     => cordic_busy,
            done     => cordic_done,
            theta_in => signed(reg_op_a),
            cos_out  => cordic_cos_s,
            sin_out  => cordic_sin_s,
            valid    => cordic_valid
        );


    ----------------------------------------------------------------------
    -- Readback mux
    ----------------------------------------------------------------------
    process(sel,
            offset,
            reg_ctrl,
            reg_status,
            reg_op_a,
            reg_op_b,
            reg_mul_lo,
            reg_mul_hi,
            reg_div_q,
            reg_div_r,
            reg_sqrt_out,
            reg_cordic_sin,
            reg_cordic_cos)
        variable v : std_logic_vector(15 downto 0);
    begin
        data_out <= (others => '0');

        if sel = '1' then
            case offset is
                when OFF_CTRL =>
                    -- Merge control bits with status bits in low positions
                    v := reg_ctrl;
                    v(ST_DONE) := reg_status(ST_DONE);
                    v(ST_BUSY) := reg_status(ST_BUSY);
                    v(ST_DIV0) := reg_status(ST_DIV0);
                    data_out   <= v;

                when OFF_UNUSED =>
                    data_out <= (others => '0');

                when OFF_OPA =>
                    data_out <= reg_op_a;

                when OFF_OPB =>
                    data_out <= reg_op_b;

                when OFF_MUL_LO =>
                    data_out <= reg_mul_lo;

                when OFF_MUL_HI =>
                    data_out <= reg_mul_hi;

                when OFF_DIV_QUO =>
                    data_out <= reg_div_q;

                when OFF_DIV_REM =>
                    data_out <= reg_div_r;

                when OFF_SQRT_OUT =>
                    data_out <= reg_sqrt_out;

                when OFF_CORDIC_SIN =>
                    data_out <= reg_cordic_sin;

                when OFF_CORDIC_COS =>
                    data_out <= reg_cordic_cos;

                when others =>
                    data_out <= (others => '0');
            end case;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Register writes, operation start, and status handling
    ----------------------------------------------------------------------
    process(clock, resetn)
        variable start_now : std_logic;
    begin
        if resetn = '0' then
            reg_ctrl        <= (others => '0');
            reg_status      <= (others => '0');

            reg_op_a        <= (others => '0');
            reg_op_b        <= (others => '0');
            reg_mul_lo      <= (others => '0');
            reg_mul_hi      <= (others => '0');
            reg_div_q       <= (others => '0');
            reg_div_r       <= (others => '0');
            reg_sqrt_out    <= (others => '0');
            reg_cordic_sin  <= (others => '0');
            reg_cordic_cos  <= (others => '0');

            mul_start       <= '0';
            div_start       <= '0';
            sqrt_start      <= '0';
            cordic_start    <= '0';

            mul_active      <= '0';
            div_active      <= '0';
            sqrt_active     <= '0';
            cordic_active   <= '0';

        elsif rising_edge(clock) then
            -- default pulse signals
            mul_start    <= '0';
            div_start    <= '0';
            sqrt_start   <= '0';
            cordic_start <= '0';

            start_now    := '0';

            ------------------------------------------------------------------
            -- Clear DONE/DIV0 on read of CTRL/STATUS
            ------------------------------------------------------------------
            if (sel = '1' and io_read = '1' and offset = OFF_CTRL) then
                reg_status(ST_DONE) <= '0';
                reg_status(ST_DIV0) <= '0';
            end if;

            ------------------------------------------------------------------
            -- Register writes
            ------------------------------------------------------------------
            if (sel = '1' and io_write = '1') then
                case offset is
                    when OFF_CTRL =>
                        reg_ctrl <= data_in;
                        if ctrl_start(data_in) = '1' then
                            start_now := '1';
                        end if;

                    when OFF_OPA =>
                        reg_op_a <= data_in;

                    when OFF_OPB =>
                        reg_op_b <= data_in;

                    when others =>
                        null;
                end case;
            end if;

            ------------------------------------------------------------------
            -- Start a new operation if requested
            ------------------------------------------------------------------
            if start_now = '1' then
                -- Clear previous status
                reg_status(ST_DONE) <= '0';
                reg_status(ST_DIV0) <= '0';

                -- stop tracking any previous op
                mul_active    <= '0';
                div_active    <= '0';
                sqrt_active   <= '0';
                cordic_active <= '0';

                if ctrl_op_sqrt(reg_ctrl) = '1' then
                    -- SQRT: uses OP_A as input
                    sqrt_start   <= '1';
                    sqrt_active  <= '1';
                    reg_status(ST_BUSY) <= '1';

                elsif ctrl_op_cordic(reg_ctrl) = '1' then
                    -- CORDIC: OP_A as angle input
                    cordic_start   <= '1';
                    cordic_active  <= '1';
                    reg_status(ST_BUSY) <= '1';

                elsif ctrl_op_div(reg_ctrl) = '1' then
                    -- DIV: NUM=OP_A, DEN=OP_B
                    if reg_op_b = x"0000" then
                        -- Divide by zero
                        reg_status(ST_BUSY) <= '0';
                        reg_status(ST_DONE) <= '1';
                        reg_status(ST_DIV0) <= '1';
                        reg_div_q          <= (others => '0');
                        reg_div_r          <= (others => '0');
                    else
                        div_start          <= '1';
                        div_active         <= '1';
                        reg_status(ST_BUSY) <= '1';
                    end if;

                else
                    -- MUL: A=OP_A, B=OP_B
                    mul_start          <= '1';
                    mul_active         <= '1';
                    reg_status(ST_BUSY) <= '1';
                end if;
            end if;

            ------------------------------------------------------------------
            -- Latch results when engines signal DONE
            ------------------------------------------------------------------
            if mul_done = '1' then
                reg_mul_lo <= mul_lo;
                reg_mul_hi <= mul_hi;
                mul_active <= '0';
                reg_status(ST_BUSY) <= '0';
                reg_status(ST_DONE) <= '1';
            end if;

            if div_done = '1' then
                reg_div_q  <= div_q;
                reg_div_r  <= div_r;
                div_active <= '0';
                reg_status(ST_BUSY) <= '0';
                reg_status(ST_DONE) <= '1';
            end if;

            if sqrt_done = '1' then
                reg_sqrt_out        <= std_logic_vector(sqrt_out_u);
                sqrt_active         <= '0';
                reg_status(ST_BUSY) <= '0';
                reg_status(ST_DONE) <= '1';
            end if;

            if cordic_done = '1' then
                reg_cordic_sin <= std_logic_vector(cordic_sin_s);
                reg_cordic_cos <= std_logic_vector(cordic_cos_s);
                cordic_active  <= '0';
            end if;

            ------------------------------------------------------------------
            -- BUSY=1 whenever any engine is working
            ------------------------------------------------------------------
            if (mul_busy = '1') or (div_busy = '1') or
               (cordic_busy = '1') or (sqrt_active = '1') then
                reg_status(ST_BUSY) <= '1';
            end if;
        end if;
    end process;

end architecture;
