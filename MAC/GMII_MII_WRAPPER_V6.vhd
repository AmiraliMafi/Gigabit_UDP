-------------------------------------------------------------
--	Filename:  GMII_MII_WRAPPER_V5.VHD
--	Version: 1
--	Date last modified: 10/28/11
-- Inheritance: 	GMII_MII_WRAPPER.VHD, rev1 4-20-10
--
-- description:  Wrapper between the MAC and the PHY (GMII/MII interface) 
-- 10/100 Mbps: Complies with the MII interface specification in the 802.3 standard clause 22
-- 1000 Mbps:  Complies with the GMII interface specification in the 802.3 standard clause 35
-- Automatic detection of the rx speed.
-- For Virtex-5
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity GMII_MII_WRAPPER_V6 is
    Port ( 
		--// CLK, RESET
		CLK: in std_logic;
			-- 125 MHz global reference clock (fixed, independent of the tx speed)
		IDELAYREFCLK200MHZ: in std_logic;
			-- 190-210 MHz clock required for implementing IO delay(s).
		SYNC_RESET: in std_logic;
			-- block the GMII/MII output signals to the PHY during the PHY reset.
			-- minimum width 50ns for Virtex 5 (IDELAYCTRL contraint)
			-- MANDATORY at power up.
		
		--// PHY GMII/MII Interface ----------------------------------------------------------------
		-- Connect directly to FPGA pins
		TX_CLK: in std_logic;  
			-- MII tx clock from PHY. Continuous clock. (10/100 Mbps only) 
			-- 25 MHz (100 Mbps), or 2.5 MHz (10 Mbps) depending on speed
			-- accuracy: +/- 100ppm (MII)
			-- duty cycle between 35% and 65% inclusive (MII).
		GTX_CLK: out std_logic;  
			-- GMII tx clock to PHY. Continuous clock. 125MHz (1000 Mbps only)
			-- 2ns delay inside (user adjustable).
		TXD: out std_logic_vector(7 downto 0);  
			-- tx data (when TX_EN = '1' and TX_ER = '0') or special codes otherwise (carrier extend, 
			-- carrier extend error, transmit error propagation). See 802.3 table 35-1 for definitions.
		TX_EN: out std_logic;  
			-- 
		TX_ER: out std_logic;  
			-- to deliberately corrupt the contents of the frame (so as to be detected as such by the receiver)
		
		RX_CLK: in std_logic;  
			-- continuous receive reference clock recovered by the PHY from the received signal
			-- 125/25/2.5 MHz +/- 50 ppm. 
			-- Duty cycle better than 35%/65% (MII)
			-- 125 MHz must be delayed by 1.5 to 2.1 ns to prevent glitches (TBC. true for RGMII, but for GMII TOO???)
			
		RXD: in std_logic_vector(7 downto 0);  
			-- rx data. 8-bit when 1000 Mbps. 4-bit nibble (3:0) when 10/100 Mbps.
		RX_DV: in std_logic;  
		RX_ER: in std_logic;  
		CRS: in std_logic;  
			-- carrier sense
		COL: in std_logic;  
			-- collision detection
		
		--// MAC Interface ----------------------------------------------------------------
		MAC_RX_CLK: out std_logic;
			-- received clock (already a global clock, no need for any additional BUFG)
			-- 125 MHz (1000 Mbps), 25 MHz (100 Mbps) or 2.5 MHz (10 Mbps)
		-- receive signals are synchronous with the MAC_RX_CLK clock recovered by the PHY
		MAC_RXD: out std_logic_vector(7 downto 0);
			-- 8-bits of rx data
		MAC_RX_DV: out std_logic;
		MAC_RX_ER: out std_logic;
		MAC_RX_SAMPLE_CLK: out std_logic;
			-- read the above MAC_RX? signals at the rising edge of MAC_RX_CLK when MAC_RX_SAMPLE_CLK = '1'.
			-- Always '1' when the transmit speed is set at 1000 Mbps  
			-- 1-CLK pulse once every (exactly) 2 CLKs when the transmit speed is set at 10 or 100 Mbps 
			
		-- transmit signals are synchronous with the rising edge of the 125 MHz CLK 
		MAC_TXD: in std_logic_vector(7 downto 0);
			-- 8-bits of tx data
			-- tx data (when MAC_TX_EN = '1' and MAC_TX_ER = '0') or special codes otherwise (carrier extend, 
			-- carrier extend error, transmit error propagation). See 802.3 table 35-1 for definitions.
		MAC_TX_EN: in std_logic;
			-- The MAC is responsible for holding the tx enable low until it has verified that it
			-- operates at the same speed as the PHY (as reported in the SPEED_STATUS)
		MAC_TX_ER: in std_logic;
			-- use (MAC_TX_EN, MAC_TX_ER) as follows:
			-- 0,0  = transmit complete
			-- 0,1 and MAC_TXD = 0x0F = carrier extend
			-- 0,1 and MAC_TXD = 0x1F = carrier extend error
			-- 1,0 = normal transmission
			-- 1,1 = transmit error
		MAC_TX_SAMPLE_CLK: in std_logic;
			-- read the above MAC_TX? signals at the rising edge of CLK when MAC_TX_SAMPLE_CLK = '1'.
			-- MAC_TX_SAMPLE_CLK conveys the transmit speed information. 
			-- Always '1' when the transmit speed is set at 1000 Mbps  
			-- 1-CLK pulse once every (exactly) 10 CLKs when the transmit speed is set at 100 Mbps 
			-- 1-CLK pulse once every (exactly) 100 CLKs when the transmit speed is set at 10 Mbps
			
		-- MAC monitoring and control
		MAC_TX_SPEED: in std_logic_vector(1 downto 0);
			-- 00/01/10  for 10/100/1000 Mbps transmit speed (not really a control, but this component
			-- needs to know what speed it should run at).
		MAC_CRS: out std_logic;  
			-- carrier sense. Directly from PHY over MII.
		MAC_COL: out std_logic;  
			-- collision detection. Directly from PHY over MII.
		
		--// PHY status
		-- optional in-band status (must be enabled at PHY)
		LINK_STATUS: out std_logic ;  -- 0 = link down, 1 = link up
		SPEED_STATUS: out std_logic_vector(1 downto 0);
			-- Detected RX_CLK clock speed, 00 = 2.5 MHz, 01 = 25 MHz, 10 = 125 MHz, 11 = reserved
		DUPLEX_STATUS: out std_logic
			-- 0 = half duplex, 1 = full duplex
		
 );
end entity;

architecture Behavioral of GMII_MII_WRAPPER_V6 is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
constant RXC_DELAY: integer range 0 to 31 := 20;  -- adjust as needed. Here: 2ns
constant TXC_DELAY: integer range 0 to 31 := 20;  -- adjust as needed. Here: 2ns
--
--signal RGMII_EN: std_logic;
signal RX_CLK_IN: std_logic;
signal RX_CLK_IN2: std_logic;
signal RX_CLK_DELAYED: std_logic := '0';
signal RX_CLKG: std_logic := '0';	-- global clock, delayed 2ns w.r.t. received RXC.
signal RX_CLKGA: std_logic := '0';	
signal RX_DV_D: std_logic;
signal RX_DV_D2: std_logic;
signal RX_ER_D: std_logic;
signal RXD_NIBBLE_TOGGLE: std_logic := '0';
signal RXD_D: std_logic_vector(7 downto 0);
signal RX_SPEED: std_logic_vector(1 downto 0) := "10";
signal RX_CLK_COUNTER1: std_logic_vector(2 downto 0) := "000";
signal RX_CLK_COUNTER1_MSB_D: std_logic;
signal RX_CLK_COUNTER1_MSB_D2: std_logic;
signal RX_CLK_COUNTER2: std_logic_vector(9 downto 0) := "0000000000";
signal MAC_RX_ER_LOCAL: std_logic := '0';
signal rxd_delay		: std_logic_vector(7 downto 0) := "00000000";
signal rx_er_delay	: std_logic;
signal rx_dv_delay	: std_logic;
signal TXC_COUNTER: std_logic_vector(5 downto 0) := "000010";
signal TX_CLK_D: std_logic;
signal TX_CLK_D2: std_logic;
signal TXC0: std_logic;
signal MAC_TXD_D: std_logic_vector(7 downto 0);
signal MAC_TX_EN_D: std_logic;
signal MAC_TX_ER_D: std_logic;
signal TXD_NIBBLE_TOGGLE: std_logic;

--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

--RGMII_EN <= not SYNC_RESET;
--  -- disable the RGMII outputs while the PHY is being reset.
--
---------------------------------------------
-- RECEIVE SECTION
---------------------------------------------
-- force IBUF selection (otherwise tools may select the wrong primitive)
--IBUF_001: IBUF port map( I => RX_CLK, O => RX_CLK_IN);

---- delay the RX_CLK clock by 2ns so that the clock is always slightly AFTER the signal transition.
--   IDELAYCTRL_inst : IDELAYCTRL
--   port map (
--      RDY => open,       -- 1-bit output indicates validity of the REFCLK
--      REFCLK => IDELAYREFCLK200MHZ, -- 1-bit reference clock input 190-210 MHz
--      RST => SYNC_RESET        -- 1-bit reset input. Minimum width 50ns
--   );

--  IDELAYE2_inst : IDELAYE2
--   generic map (
--      CINVCTRL_SEL => "FALSE",          -- Enable dynamic clock inversion (FALSE, TRUE)
--      DELAY_SRC => "IDATAIN",           -- Delay input (IDATAIN, DATAIN)
--      HIGH_PERFORMANCE_MODE => "TRUE", -- Reduced jitter ("TRUE"), Reduced power ("FALSE")
--      IDELAY_TYPE => "FIXED",           -- FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
--      IDELAY_VALUE => 0,                -- Input delay tap setting (0-31)
--      PIPE_SEL => "FALSE",              -- Select pipelined mode, FALSE, TRUE
--      REFCLK_FREQUENCY => 200.0,        -- IDELAYCTRL clock input frequency in MHz (190.0-210.0).
--      SIGNAL_PATTERN => "CLOCK"          -- DATA, CLOCK input signal
--   )
--   port map (
--      CNTVALUEOUT => open, -- 5-bit output: Counter value output
--      DATAOUT => RX_CLK_DELAYED,         -- 1-bit output: Delayed data output
--      C => '0',                     -- 1-bit input: Clock input
--      CE => '0',                   -- 1-bit input: Active high enable increment/decrement input
--      CINVCTRL => '0',       -- 1-bit input: Dynamic clock inversion input
--      CNTVALUEIN => (OTHERS	=>	'0'),   -- 5-bit input: Counter value input
--      DATAIN => '0',           -- 1-bit input: Internal delay data input
--      IDATAIN => RX_CLK_IN,         -- 1-bit input: Data input from the I/O
--      INC => '0',                 -- 1-bit input: Increment / Decrement tap delay input
--      LD => '0',                   -- 1-bit input: Load IDELAY_VALUE input
--      LDPIPEEN => '0',       -- 1-bit input: Enable PIPELINE register to load data input
--      REGRST => SYNC_RESET            -- 1-bit input: Active-high reset tap-delay input
--   );

-- delay_gmii_rx_dv : IODELAYE1
--   generic map (
--      IDELAY_TYPE    => "FIXED",
--      DELAY_SRC      => "I"
--   )
--   port map (
--      IDATAIN        => rx_dv,
--      ODATAIN        => '0',
--      DATAOUT        => rx_dv_delay,
--      DATAIN         => '0',
--      C              => '0',
--      T              => '1',
--      CE             => '0',
--      CINVCTRL       => '0',
--      CLKIN          => '0',
--      CNTVALUEIN     => "00000",
--      CNTVALUEOUT    => open,
--      INC            => '0',
--      RST            => '0'
--   );
rx_dv_delay	<= rx_dv;
--delay_gmii_rx_er : IODELAYE1
--   generic map (
--      IDELAY_TYPE    => "FIXED",
--      DELAY_SRC      => "I"
--   )
--   port map (
--      IDATAIN        => rx_er,
--      ODATAIN        => '0',
--      DATAOUT        => rx_er_delay,
--      DATAIN         => '0',
--      C              => '0',
--      T              => '1',
--      CE             => '0',
--      CINVCTRL       => '0',
--      CLKIN          => '0',
--      CNTVALUEIN     => "00000",
--      CNTVALUEOUT    => open,
--      INC            => '0',
--      RST            => '0'
--   );
	
rx_er_delay	<=	rx_er;
--  rxdata_bus: for I in 7 downto 0 generate
--   delay_gmii_rxd : IODELAYE1
--   generic map (
--      IDELAY_TYPE    => "FIXED",
--      DELAY_SRC      => "I"
--   )
--   port map (
--      IDATAIN        => rxd(I),
--      ODATAIN        => '0',
--      DATAOUT        => rxd_delay(I),
--      DATAIN         => '0',
--      C              => '0',
--      T              => '1',
--      CE             => '0',
--      CINVCTRL       => '0',
--      CLKIN          => '0',
--      CNTVALUEIN     => "00000",
--      CNTVALUEOUT    => open,
--      INC            => '0',
--      RST            => '0'
--   );
--   end generate;
	
---------------
rxd_delay	<=	rxd;
---------------
--IBUFG_inst : IBUF
--	generic map (
--					IOSTANDARD 		=> "DEFAULT"
--					)
--	port map (
--					O 					=> RX_CLKGA, -- Clock buffer output
--					I 					=> RX_CLK -- Clock buffer input (connect directly to top-level port)
--				);
RX_CLKGA	<=	RX_CLK;
-- delay RX clock, but only in the case of 125 MHz
--RX_CLK_IN2 <= RX_CLK_DELAYED;-- when (RX_SPEED = "10") else RX_CLK_IN;

-- TODO.. It may be better to control IODELAY2 delay because the mux above delays the clock.

---- declare the RX clock as a global clock
--BUFG_001 : BUF port map (
--	O => ,     -- Clock buffer output
--	I => RX_CLKGA      -- Clock buffer input
--);

RX_CLKG	<=	RX_CLKGA;
-------------------
-- immediately reclock rx input signals 
--RECLOCK_RX_001: process(RX_CLKG, RXD, RX_DV, RX_ER)
RECLOCK_RX_001: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		RXD_D 	<= rxd_delay;
		RX_DV_D 	<= rx_dv_delay;
		RX_ER_D 	<= rx_er_delay;
	end if;
end process;

-- re-assemble 8-bit rx data (from 4-bit nibbles at 10/100 Mbps)
RX8B_001: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		RX_DV_D2 <= RX_DV_D;
		
		if(RX_SPEED(1) = '0') and (RX_DV_D = '1') and (RX_DV_D2 = '0') then
			-- 10/100 Mbps. Start of new packet. Reset toggle
			RXD_NIBBLE_TOGGLE <= '1';
		else
			RXD_NIBBLE_TOGGLE <= not RXD_NIBBLE_TOGGLE;
		end if;
	end if;
end process;

MAX_RX_OUT_001: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		MAC_CRS <= CRS;
		MAC_COL <= COL;
		
		if(RX_SPEED = "10") then
			-- 1000 Mbps
			MAC_RXD <= RXD_D;
			MAC_RX_DV <= RX_DV_D; 
			MAC_RX_ER_LOCAL <= RX_ER_D; 
			MAC_RX_SAMPLE_CLK <= '1';
			LINK_STATUS <= '1';
		elsif(RX_SPEED(1) = '0') and (RX_DV_D = '1') and (RX_DV_D2 = '0') then
			-- start of new packet. Reset toggle
			MAC_RXD(3 downto 0) <= RXD_D(3 downto 0);
			MAC_RX_DV <= RX_DV_D; 
			MAC_RX_ER_LOCAL <= RX_ER_D; 
			MAC_RX_SAMPLE_CLK <= '0';  -- waiting for the other half
			LINK_STATUS <= '1';
		elsif(RX_SPEED(1) = '0') and (RXD_NIBBLE_TOGGLE = '0') then
			-- 1st nibble (1/2)
			MAC_RXD(3 downto 0) <= RXD_D(3 downto 0);
			MAC_RX_DV <= RX_DV_D; 
			MAC_RX_ER_LOCAL <= RX_ER_D; 
			MAC_RX_SAMPLE_CLK <= '0';  -- waiting for the other half
			LINK_STATUS <= '1';
		elsif(RX_SPEED(1) = '0') and (RXD_NIBBLE_TOGGLE = '1') then
			-- 2nd nibble (2/2)
			MAC_RXD(7 downto 4) <= RXD_D(3 downto 0);
			MAC_RX_SAMPLE_CLK <= '1';  -- got a complete byte
			MAC_RX_ER_LOCAL <= MAC_RX_ER_LOCAL or RX_ER_D;  -- RX_ER can be as short as one RX_CLKG.
			LINK_STATUS <= '1';
		else
			MAC_RX_SAMPLE_CLK <= '0'; 
    		LINK_STATUS <= '0';
		end if;
	end if;
end process;

-- outputs to MAC
MAC_RX_CLK <= RX_CLKG;
MAC_RX_ER <= MAC_RX_ER_LOCAL;

--// RX_SPEED AUTODETECT ------------------------------------------
-- Automatically detect rx speed based on the RX_CLK.
-- Algorithm: two counters, one based the variable frequency clock (RX_CLKG), the other
-- based on the 125 MHz master clock.

-- Modulo-8 counter.
RX_CLK_COUNTER1_GEN: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		RX_CLK_COUNTER1 <= RX_CLK_COUNTER1 + 1;
	end if;
end process;
		
RX_CLK_COUNTER2_GEN: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		RX_CLK_COUNTER1_MSB_D <= RX_CLK_COUNTER1(2);  -- reclock to make RX_CLK_COUNTER1 MSb synchronous with CLK
		RX_CLK_COUNTER1_MSB_D2 <= RX_CLK_COUNTER1_MSB_D;
		
		if(RX_CLK_COUNTER1_MSB_D2 = '0') and (RX_CLK_COUNTER1_MSB_D = '1') then
			-- reset RX_CLK_COUNTER2 every 8 RX_CLK_COUNTER1. 
			RX_CLK_COUNTER2 <= (others => '0');
			if(RX_CLK_COUNTER2(9 downto 4) = 0) then  -- <16
				RX_SPEED <= "10";  -- 1000 Mbps
			elsif(RX_CLK_COUNTER2(9 downto 6) = 0) then  -- < 64
				RX_SPEED <= "01";  -- 100 Mbps
			else
				RX_SPEED <= "00";  -- 10 Mbps
			end if;
		else
			RX_CLK_COUNTER2 <= RX_CLK_COUNTER2 + 1;
		end if;
		
	end if;
end process;

-- report rx speed to MAC
SPEED_STATUS <= RX_SPEED;

---------------------------------------------
-- TRANSMIT SECTION
---------------------------------------------
-- Reclock TX signals so that they are stable during the entire period (we don't
-- want any transition within a TXC clock period)
RECLOCK_005: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if(SYNC_RESET = '1') then
			MAC_TXD_D <= (others => '0');
			MAC_TX_EN_D <= '0';
			MAC_TX_ER_D <= '0';
			TXD_NIBBLE_TOGGLE <= '0';
		elsif (MAC_TX_SAMPLE_CLK = '1') then
			MAC_TXD_D <= MAC_TXD;
			MAC_TX_EN_D <= MAC_TX_EN;
			MAC_TX_ER_D <= MAC_TX_ER;
			TXD_NIBBLE_TOGGLE <= '0';  -- point to lower nibble (3:0) first
		elsif(MAC_TX_SPEED(1) = '0') and (TXC0 = '1')then  -- 10/100 Mbps
			-- read another nibble. toggle upper/lower nibble pointer
			TXD_NIBBLE_TOGGLE <= not TXD_NIBBLE_TOGGLE;
		end if;
	end if;
end process;

-- two cases: @1000 Mbps, the GTX_CLK is an output. At other speeds, the TX_CLK in an input.

-- Case 10/100 Mbps. Convert the TX_CLK input clock from the PHY into CLK-synchronous 8ns pulses.
-- Poor-man's DLL to ensure that the clocks are spaced exactly 5 or 50 CLKs apart.
TX_CLK_GEN_001: process(RX_CLKG, TX_CLK)
begin
	if rising_edge(RX_CLKG) then
		TX_CLK_D <= TX_CLK;
		TX_CLK_D2 <= TX_CLK_D;
		
		-- TXC_COUNTER represents the phase of the clock replica.
		if(SYNC_RESET = '1') or (MAC_TX_SPEED(1) = '1') then
			TXC_COUNTER <= (others => '0');
		elsif(MAC_TX_SPEED = "00") and (TXC_COUNTER = 0) then
			-- 10 Mbps: modulo-50 periodic counter
			TXC_COUNTER <= "110001";  -- 49
		elsif(MAC_TX_SPEED = "01") and (TXC_COUNTER = 0) then
			-- 100 Mbps: modulo-5 periodic counter
			TXC_COUNTER <= "000100";  -- 4
		elsif (TXC_COUNTER > 2) and (TX_CLK_D2 = '0') and (TX_CLK_D = '1') then
			-- re-adjust phase of clock replica (once at start-up) when phase error is too large
			-- 3 CLK margin. 
			TXC_COUNTER <= "000001";  
		elsif(TXC_COUNTER > 0) then
			TXC_COUNTER <= TXC_COUNTER - 1;
		end if;
		
		if(TXC_COUNTER = 2) then
			TXC0 <= '1';
		else
			TXC0 <= '0';
		end if;
		
	end if;
end process;


TXD_OUTPUT_001: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if(SYNC_RESET = '1') then
			-- disable all outputs while the component is being reset.
			TXD <= (others => '0');
			TX_EN <= '0';
			TX_ER <= '0';
		elsif(MAC_TX_SPEED(1) = '0') and (TXC0 = '1')then  -- 10/100 Mbps
			if(TXD_NIBBLE_TOGGLE = '0') then
				-- lower nibble (3:0)
				TXD <= MAC_TXD_D(3 downto 0) & MAC_TXD_D(3 downto 0);  -- data
			else
				TXD <= MAC_TXD_D(7 downto 4) & MAC_TXD_D(7 downto 4);  -- data
			end if;
			TX_EN <= MAC_TX_EN_D;
			TX_ER <= MAC_TX_ER_D;
		elsif(MAC_TX_SPEED = "10") then  -- 1000 Mbps
			TXD <= MAC_TXD_D;  -- data
			TX_EN <= MAC_TX_EN_D;
			TX_ER <= MAC_TX_ER_D;
		end if;
	end if;
end process;


-- delay the TX clock by 2ns so that the clock is always slightly AFTER the signal transition.
   -- Xilinx Virtex-5 IODELAY: Input and Output Fixed or Variable Delay Element
--    IODELAY_001 : IODELAYE2
--    generic map (
--			 CINVCTRL_SEL	=>	FALSE,
--       DELAY_SRC => "O", -- Specify which input port to be used
----                        "I"=IDATAIN, "O"=ODATAIN, "DATAIN"=DATAIN, "IO"=Bi-directional
--       HIGH_PERFORMANCE_MODE => TRUE, -- TRUE specifies lower jitter
----                                     at expense of more power
--       IDELAY_TYPE => "FIXED",  -- "FIXED" or "VARIABLE" 
--       IDELAY_VALUE => 0,   -- 0 to 63 tap values
--			 ODELAY_TYPE	=>	"FIXED",
--       ODELAY_VALUE => TXC_DELAY,   -- 0 to 63 tap values
--       REFCLK_FREQUENCY => 200.0,   -- Frequency used for IDELAYCTRL
----                                    175.0 to 225.0
--       SIGNAL_PATTERN => "CLOCK")    -- Input signal type, "CLOCK" or "DATA" 
--    port map (
--			 CNTVALUEOUT	=>	OPEN,
--       DATAOUT => GTX_CLK,  -- 1-bit delayed data output
--       C => '0',     -- 1-bit clock input
--       CE => '0',   -- 1-bit clock enable input
--			 CINVCTRL	=>	'0',
--			 CLKIN	=>	'Z',
--			 CNTVALUEIN	=>	(OTHERS	=>	'0'),
--       DATAIN => '0', -- 1-bit internal data input
--       IDATAIN => '0',  -- 1-bit input data input (connect to port)
--       INC => '0', -- 1-bit increment/decrement input
--       ODATAIN => CLK,  -- 1-bit output data input
--       RST => '0',  -- 1-bit active high, synch reset input
--       T => '0'  -- 1-bit 3-state control input
--    );
GTX_CLK <= RX_CLKG;
end Behavioral;

