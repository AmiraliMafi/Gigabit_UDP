-------------------------------------------------------------
--	Filename:  MII_MI_V5.VHD
--	Version: 1
--	Date last modified: 1-30-11
-- Inheritance: 	MII_MI.VHD rev1 1-30-11 
--
-- description:  MII management interface.
-- Writes and read registers to/from the PHY IC through 
-- the MDC & MDIO serial interface.
-- The MCLK clock speed is set as a constant within (integer division of the reference clock CLK).
-- USAGE: adjust the constant MCLK_COUNTER_DIV within to meet the MDC/MDIO timing requirements (see PHY specs).
-- Virtex-5 use.
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity MII_MI_V6 is
	generic (
		PHY_ADDR: std_logic_vector(4 downto 0)
			-- PHY Address
	);
    Port ( 
		--// CLK, RESET
		SYNC_RESET: in std_logic;
		CLK: in std_logic;

		MI_REGAD: in std_logic_vector(4 downto 0);	
			-- 32 register address space for the PHY (ieee 802.3)
			--  0 - 15 are standard PHY registers as per IEEE specification.
			-- 16 - 31 are vendor-specific registers
		MI_TX_DATA: in std_logic_vector(15 downto 0);
		MI_RX_DATA: out std_logic_vector(15 downto 0);	
		MI_READ_START: in std_logic;
			-- 1 CLK wide pulse to start read transaction
			-- will be ignored if the previous transaction is yet to be completed.
			-- For reliable operation, the user must check MI_TRANSACTION_COMPLETE first.
		MI_WRITE_START: in std_logic;
			-- 1 CLK wide pulse to start write transaction
			-- will be ignored if the previous transaction is yet to be completed.
			-- For reliable operation, the user must check MI_TRANSACTION_COMPLETE first.

		MI_TRANSACTION_COMPLETE: out std_logic;
			-- '1' when transaction is complete 

		--// serial interface. connect to PHY 
		MCLK: out std_logic;
		MDI: in std_logic;  -- MDIO input
		MDO: out std_logic;  -- MDIO output
		MDT: out std_logic  -- MDIO tri-state
		
 );
end entity;

architecture Behavioral of MII_MI_V6 is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
signal STATE: std_logic_vector(7 downto 0) := x"00";   -- 0 is idle
signal TXRX_FRAME: std_logic_vector(63 downto 0); --32-bit idle sequence + 32-bit MI serial port frame + 2 end bit
signal MCLK_LOCAL: std_logic := '0';
signal MCLK_LOCAL_D: std_logic := '0';
signal MDOE: std_logic := '1';
signal MDI_DATA: std_logic := '0';
signal MDI_SAMPLE_CLK: std_logic := '0';
constant MCLK_COUNTER_DIV: std_logic_vector(7 downto 0) := x"17";  
	-- divide CLK by this 2*(value + 1) to generate a slower MCLK
	-- MCLK period (typ): 400 ns [Micrel KSZ9021]
	-- Example: 120 MHz clock, 400ns MCLK period => MCLK_COUNTER_DIV = 23
signal MCLK_COUNTER: std_logic_vector(7 downto 0) := x"00";
signal MI_SAMPLE_REQ: std_logic;

--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

------------------------------------------------------
-- MCLK GENERATION
------------------------------------------------------
-- Divide CLK by MCLK_COUNTER_DIV
MCLK_GEN_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			MCLK_COUNTER <= (others => '0');
			MI_SAMPLE_REQ <= '0';
		elsif(STATE = 0) then
			-- idle. awaiting a start of transaction.
			MI_SAMPLE_REQ <= '0';
			if(MI_WRITE_START = '1') or (MI_READ_START = '1') then
				-- get started. reset MCLK phase.
				MCLK_COUNTER <= (others => '0');
			end if;
		else
			-- read/write transaction in progress
			if(MCLK_COUNTER = MCLK_COUNTER_DIV) then 
				-- next sample
				MI_SAMPLE_REQ <= '1';
				MCLK_COUNTER <= (others => '0');
			else
				MI_SAMPLE_REQ <= '0';
				MCLK_COUNTER <= MCLK_COUNTER + 1;
			end if;
		end if;
	end if;
end process;

------------------------------------------------------
-- OUTPUT TO PHY
------------------------------------------------------

STATE_GEN_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			STATE <= (others => '0');
			MCLK_LOCAL <= '0';
			MDOE <= '0';
		elsif(STATE = 0) then
			if (MI_WRITE_START = '1') then
				-- was idle. start of write transaction. start counting 
				STATE <= x"01";
				MCLK_LOCAL <= '0';
				MDOE <= '1';
			elsif (MI_READ_START = '1') then
				-- was idle. start of read transaction. start counting 
				STATE <= x"81";
				MCLK_LOCAL <= '0';
				MDOE <= '1';
			end if;
		elsif (MI_SAMPLE_REQ = '1') then
			if (STATE = 128) then
				-- write transaction complete. set output enable to high impedance
				STATE <= x"00";
				MCLK_LOCAL <= '0';
				MDOE <= '0';
			elsif (STATE = 220) then
				-- read transaction: finished writing addresses. switch to read mode
				STATE <= STATE + 1;
				MCLK_LOCAL <= not MCLK_LOCAL;
				MDOE <= '0';
			elsif (STATE = 255) then
				-- read transaction complete. reset state.
				STATE <= x"00";
				MCLK_LOCAL <= '0';
				MI_RX_DATA <= TXRX_FRAME(15 downto 0);  -- complete word read from PHY
			else
				STATE <= STATE + 1;
				MCLK_LOCAL <= not MCLK_LOCAL;
			end if;
		end if;
	end if;
end process;

-- immediate turn off the 'available' message as soon as a new transaction is triggered.
MI_TRANSACTION_COMPLETE <= '0' when (STATE > 0) else
									'0' when (MI_WRITE_START = '1') else
									'0' when (MI_READ_START = '1') else
									'1';

-- send MCLK to output
MCLK <= MCLK_LOCAL;

TXRX_FRAME_GEN: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			TXRX_FRAME <= (others => '0');
		elsif(MI_WRITE_START = '1') then
			-- start of write transaction. 
			-- Note: transmission sequence starts at bit 63 
			TXRX_FRAME(63 downto 32) <= x"FFFFFFFF";	-- preamble: idle sequence 32 '1's
			TXRX_FRAME(31 downto 23)  <= "0101" & PHY_ADDR;  
			TXRX_FRAME(22 downto 18) <= MI_REGAD;
			TXRX_FRAME(17 downto 16) <= "10";
			TXRX_FRAME(15 downto 0) <= MI_TX_DATA;
		elsif(MI_READ_START = '1') then
			-- start of read transaction. 
			-- Note: transmission sequence starts at bit 63 
			TXRX_FRAME(63 downto 32) <= x"FFFFFFFF";	-- preamble: idle sequence 32 '1's
			TXRX_FRAME(31 downto 23)  <= "0110" & PHY_ADDR; 
			TXRX_FRAME(22 downto 18) <= MI_REGAD;
		elsif(MI_SAMPLE_REQ = '1') and (STATE /= 0) and (STATE(0) = '0') and (MDOE = '1') then
			-- shift TXRX_FRAME 1 bit left every two clocks
			TXRX_FRAME(63 downto 1) <= TXRX_FRAME(62 downto 0);
		elsif(MDI_SAMPLE_CLK = '1') and (STATE /= 0) and (STATE(0) = '1') and (MDOE = '0') then
			-- shift MDIO into TXRX_FRAME 1 bit left every two clocks (read at the falling edge of MCLK)
			-- do this 16 times to collect the 16-bit response from the PHY.
			TXRX_FRAME(63 downto 1) <= TXRX_FRAME(62 downto 0);
			TXRX_FRAME(0) <= MDI_DATA;
	 	end if;
  end if;
end process;

-- select output bit. 
MDO <= TXRX_FRAME(63);
MDT <= not MDOE;

------------------------------------------------------
-- INPUT FROM PHY
------------------------------------------------------


-- reclock MDI input at the falling edge of MCLK
RX_RECLOCK_001: process(CLK)
begin
	if rising_edge(CLK) then
		MCLK_LOCAL_D <= MCLK_LOCAL;
		
		if(MCLK_LOCAL = '0') and (MCLK_LOCAL_D = '1') then
			MDI_DATA <= MDI;
			MDI_SAMPLE_CLK <= '1';
		else
			MDI_SAMPLE_CLK <= '0';
		end if;
	end if;
end process;


end Behavioral;
