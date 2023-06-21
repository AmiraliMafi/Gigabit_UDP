-------------------------------------------------------------
--	Filename:  MAC_Controller.VHD
--	Version: 5
--	Date last modified: 9/16/11
-- Inheritance: COM5401.VHD, rev5, 9/16/11
--
-- description:  10/100/1000 MAC
-- Features include
-- (a) Automatic appending of 32-bit CRC to tx packets. Users don't have to.
-- (b) discarding of rx packets with bad CRC.
-- 
-- Usage: the following KSZ9021RN strapping options MUST be set in the .ucf file
-- pin35 RX_CLK/PHYAD2 pull-down  LEFT_CONNECTOR_A(1),A(19),B(1),B(21)
-- pins32,31,28,27 RXDx/MODEx  pull-up, advertise all modes
-- 	LEFT_CONNECTOR_A(2,4,5,6,21,22,23,24),B(3,4,6,7,23,24,25,26)
-- pin33 RX_DV(RX_CTL)/CLK125_EN	
-- 	pull-down on all ICs. No need for an external 125 MHz clock (not very clean).
-- 	LEFT_CONNECTOR_A(2) pullup, LEFT_CONNECTOR_A(20),B(2),B(22) pull-down
-- pin41 CLK125_NDO/LED_MODE pulldown dual leds, tri-color.
-- 	LEFT_CONNECTOR_A(13,31),_B(14,34)
-- 
-- The transmit elastic buffer is large enough for 2 maximum size frame. The tx Clear To Send (MAC_TX_CTS)
-- signal is raised when the the MAC is ready to accept one complete frame without interruption.
-- In this case, MAC_TX_CTS may go low while the frame transfer has started, but there is guaranteed
-- space for the entire frame.  
--
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity MAC_Controller is
	generic (
		PHY_ADDR: std_logic_vector(4 downto 0) := "00001";	
			-- PHY_AD0/1 pulled-down by 1KOhm, PHY_AD2 pulled-up in .ucf file.
		CLK_FREQUENCY: integer := 125
			-- CLK frequency in MHz. Needed to compute actual delays.
	);
    Port ( 
		--// CLK, RESET
		CLK: in std_logic;
			-- USER-side GLOBAL CLOCK
		IDELAYREFCLK200MHZ: in std_logic;
			-- 190-210 MHz clock required for implementing IO delay(s).
		ASYNC_RESET: in std_logic;
			-- reset pulse must be > slowest clock period  (>400ns)
			-- minimum width 50ns for Virtex 5 (IDELAYCTRL contraint)
			-- MANDATORY at power up.

		--// MAC CONFIGURATION
		-- configuration signals are synchonous with the user-side CLK
		MAC_TX_CONFIG: in std_logic_vector(15 downto 0);
			-- bit 0: (1) Automatic padding of short frames. Requires that auto-CRC insertion be enabled too. 
			--			 (0) Skip padding. User is responsible for adding padding to meet the minimum 60 byte frame size
			-- bit 1: (1) Automatic appending of 32-bit CRC at the end of the frame
			--			 (0) Skip CRC32 insertion. User is responsible for including the frame check sequence
			-- Note: use 0x03 when interfacing with COM-5402 IP/UDP/TCP stack.
		MAC_RX_CONFIG: in std_logic_vector(15 downto 0);
			-- bit 0: (1) promiscuous mode enabled (0) disabled, i.e. destination address is verified for each incoming packet 
			-- bit 1: (1) accept broadcast rx packets (0) reject
			-- bit 2: (1) accept multi-cast rx packets (0) reject
			-- bit 3: (1) filter out the 4-byte CRC field (0) pass along the CRC field.
			-- Note2: use 0x0F when interfacing with COM-5402 IP/UDP/TCP stack.
		MAC_ADDR: in std_logic_vector(47 downto 0);
			-- This network node 48-bit MAC address. The receiver checks incoming packets for a match between 
			-- the destination address field and this MAC address.
			-- The user is responsible for selecting a unique ‘hardware’ address for each instantiation.
			-- Natural bit order: enter x0123456789ab for the MAC address 01:23:45:67:89:ab

		--// PHY CONFIGURATION
		-- configuration signals are synchonous with the user-side CLK.
		PHY_CONFIG_CHANGE: in std_logic;
			-- optional pulse to activate any configuration change below.
			-- Not needed if the default values are acceptable.
			-- Ignored if sent during the initial PHY reset (10ms after power up)
		PHY_RESET: in std_logic; 
			-- 1 = PHY software reset (default), 0 = no reset
		SPEED: in std_logic_vector(1 downto 0);
			-- 00 = force 10 Mbps
			-- 01 = force 100 Mbps
			-- 10 = force 1000 Mbps
			-- 11 = auto-negotiation (default)
		DUPLEX: in std_logic;
			-- 1 = full-duplex (default), 0 = half-duplex
		TEST_MODE: in std_logic_vector(1 downto 0);
			-- 00 = normal mode (default)
			-- 01 = loopback mode (at the phy)
			-- 10 = remote loopback
			-- 11 = led test mode
		POWER_DOWN: in std_logic;
			-- software power down mode. 1 = enabled, 0 = disabled (default).

		--// USER -> Transmit MAC Interface
		-- 32-bit CRC is automatically appended. User should not supply it.
		-- Synchonous with the user-side CLK
		MAC_TX_DATA: in std_logic_vector(7 downto 0);
			-- MAC reads the data at the rising edge of CLK when MAC_TX_DATA_VALID = '1'
		MAC_TX_DATA_VALID: in std_logic;
			-- data valid
		MAC_TX_EOF: in std_logic;
			-- '1' when sending the last byte in a packet to be transmitted. 
			-- Aligned with MAC_TX_DATA_VALID
		MAC_TX_CTS: out std_logic;
			-- MAC-generated Clear To Send flow control signal, indicating room in the 
			-- tx elastic buffer for a complete maximum size frame 1518B. 
			-- The user should check that this signal is high before deciding to send
			-- sending the next frame. 
			-- Note: MAC_TX_CTS may go low while the frame is transfered in. Ignore it.
		
		--// Receive MAC -> USER Interface
		-- Valid rx packets only: packets with bad CRC or invalid address are discarded.
		-- Synchonous with the user-side CLK
		-- The short-frame padding is included .
		MAC_RX_DATA: out std_logic_vector(7 downto 0);
			-- USER reads the data at the rising edge of CLK when MAC_RX_DATA_VALID = '1'
		MAC_RX_DATA_VALID: out std_logic;
			-- data valid
		MAC_RX_SOF: out std_logic;
			-- '1' when sending the first byte in a received packet. 
			-- Aligned with MAC_RX_DATA_VALID
		MAC_RX_EOF: out std_logic;
			-- '1' when sending the last byte in a received packet. 
			-- Aligned with MAC_RX_DATA_VALID
		MAC_RX_CTS: in std_logic;
			-- User-generated Clear To Send flow control signal. The receive MAC checks that this 
			-- signal is high before sending the next MAC_RX_DATA byte. 
		
		
		
		--// RGMII PHY Interface (when RGMII is enabled. See MII_SEL generic flag above)
		RESET_N: out std_logic;
			-- PHY reset
		MCLK: out std_logic;
		MDIO: inout std_logic:='0';  -- (tri-state)
			-- serial interface
		
		--// GMII/MII PHY Interface (when GMII/MII is enabled.  See MII_SEL generic flag above)
		MII_TX_CLK: in std_logic:='0';
			-- MII tx clock from PHY. Continuous clock. (10/100 Mbps only) 
			-- 25 MHz (100 Mbps), or 2.5 MHz (10 Mbps) depending on speed
			-- accuracy: +/- 100ppm (MII)
			-- duty cycle between 35% and 65% inclusive (MII).
		GMII_TX_CLK: out std_logic;
			-- GMII tx clock to PHY. Continuous clock. 125MHz (1000 Mbps only)
			-- 2ns delay inside (user adjustable).
		GMII_MII_TXD: out std_logic_vector(7 downto 0);  -- tx data
			-- tx data (when TX_EN = '1' and TX_ER = '0') or special codes otherwise (carrier extend, 
			-- carrier extend error, transmit error propagation). See 802.3 table 35-1 for definitions.
		GMII_MII_TX_EN: out std_logic;
		GMII_MII_TX_ER: out std_logic;
			-- to deliberately corrupt the contents of the frame (so as to be detected as such by the receiver)
		GMII_MII_CRS: in std_logic:='0';
		GMII_MII_COL: in std_logic:='0';
		
		GMII_MII_RX_CLK: in std_logic;  
			-- continuous receive reference clock recovered by the PHY from the received signal
			-- 125/25/2.5 MHz +/- 50 ppm. 
			-- Duty cycle better than 35%/65% (MII)
			-- 125 MHz must be delayed by 1.5 to 2.1 ns to prevent glitches (TBC. true for RGMII, but for GMII TOO???)
			
		GMII_MII_RXD: in std_logic_vector(7 downto 0);  
			-- rx data. 8-bit when 1000 Mbps. 4-bit nibble (3:0) when 10/100 Mbps.
		GMII_MII_RX_DV: in std_logic;  
		GMII_MII_RX_ER: in std_logic;  
		
	   
		--// PHY status
		-- The link, speed and duplex status are read from the RXD when RX_CTL is inactive
		-- synchronous with RXCG global clock
		LINK_STATUS: out std_logic;
			-- 0 = link down, 1 = link up
		SPEED_STATUS: out std_logic_vector(1 downto 0);
			-- RXC clock speed, 00 = 2.5 MHz, 01 = 25 MHz, 10 = 125 MHz, 11 = reserved
		DUPLEX_STATUS: out std_logic;
			-- 0 = half duplex, 1 = full duplex
		PHY_ID: out std_logic_vector(15 downto 0)
		
 );
end entity;

architecture Behavioral of MAC_Controller is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
	COMPONENT RESET_TIMER
	GENERIC (
		CLK_FREQUENCY: in integer
	);	
	PORT(
		CLK : IN std_logic;
		RESET_START : IN std_logic;          
		RESET_COMPLETE : OUT std_logic;
		INITIAL_CONFIG_PULSE : OUT std_logic;
		RESET_N : OUT std_logic
		);
	END COMPONENT;

	COMPONENT PHY_CONFIG
	GENERIC (
		PHY_ADDR: std_logic_vector(4 downto 0)
	);	
	PORT(
		SYNC_RESET : IN std_logic;
		CLK : IN std_logic;
		CONFIG_CHANGE : IN std_logic;
		PHY_RESET : IN std_logic;
		SPEED : IN std_logic_vector(1 downto 0);
		DUPLEX : IN std_logic;
		TEST_MODE : IN std_logic_vector(1 downto 0);
		POWER_DOWN : IN std_logic;
		CLK_SKEW: in std_logic_vector(15 downto 0);
		SREG_READ_START : IN std_logic;
		SREG_REGAD : IN std_logic_vector(8 downto 0);    
		LINK_STATUS: out std_logic;  
		MDI: in std_logic;  -- MDIO input
		MDO: out std_logic;  -- MDIO output
		MDT: out std_logic;  -- MDIO tri-state
		SREG_DATA : OUT std_logic_vector(15 downto 0);
		SREG_SAMPLE_CLK : OUT std_logic;
		MCLK : OUT std_logic
		);
	END COMPONENT;

	COMPONENT RGMII_WRAPPER_V6
	GENERIC (
		CLK_FREQUENCY: in integer
	);	
	PORT(
		SYNC_RESET : IN std_logic;
		CLK : IN std_logic;
		IDELAYREFCLK200MHZ: in std_logic;
		RXC : IN std_logic;
		RXD : IN std_logic_vector(3 downto 0);
		RX_CTL : IN std_logic;
		MAC_TXD : IN std_logic_vector(7 downto 0);
		MAC_TX_EN : IN std_logic;
		MAC_TX_ER : IN std_logic;
		MAC_TX_SAMPLE_CLK : IN std_logic;
		TX_SPEED : IN std_logic_vector(1 downto 0);          
		TXC : OUT std_logic;
		TXD : OUT std_logic_vector(3 downto 0);
		TX_CTL : OUT std_logic;
		MAC_RXD : OUT std_logic_vector(7 downto 0);
		MAC_RX_SAMPLE_CLK: OUT std_logic;
		MAC_RX_DV : OUT std_logic;
		MAC_RX_ER : OUT std_logic;
		RXCG_OUT : OUT std_logic;
		CRS : OUT std_logic;
		COL : OUT std_logic;
		LINK_STATUS : OUT std_logic;
		SPEED_STATUS : OUT std_logic_vector(1 downto 0);
		DUPLEX_STATUS : OUT std_logic;
		TP: out std_logic_vector(10 downto 1)
		);
	END COMPONENT;
	
	COMPONENT GMII_MII_WRAPPER_V6
	PORT(
		SYNC_RESET : IN std_logic;
		CLK : IN std_logic;
		IDELAYREFCLK200MHZ: in std_logic;
		TX_CLK : IN std_logic;
		RX_CLK : IN std_logic;
		RXD : IN std_logic_vector(7 downto 0);
		RX_DV : IN std_logic;
		RX_ER : IN std_logic;
		CRS : IN std_logic;
		COL : IN std_logic;
		MAC_TXD : IN std_logic_vector(7 downto 0);
		MAC_TX_EN : IN std_logic;
		MAC_TX_ER : IN std_logic;
		MAC_TX_SAMPLE_CLK : IN std_logic;
		MAC_TX_SPEED : IN std_logic_vector(1 downto 0);          
		GTX_CLK : OUT std_logic;
		TXD : OUT std_logic_vector(7 downto 0);
		TX_EN : OUT std_logic;
		TX_ER : OUT std_logic;
		MAC_RX_CLK : OUT std_logic;
		MAC_RXD : OUT std_logic_vector(7 downto 0);
		MAC_RX_DV : OUT std_logic;
		MAC_RX_ER : OUT std_logic;
		MAC_RX_SAMPLE_CLK : OUT std_logic;
		MAC_CRS : OUT std_logic;
		MAC_COL : OUT std_logic;
		LINK_STATUS : OUT std_logic;
		SPEED_STATUS : OUT std_logic_vector(1 downto 0);
		DUPLEX_STATUS : OUT std_logic
		);
	END COMPONENT;
	
	COMPONENT CRC32_8B
	PORT(
		SYNC_RESET : IN std_logic;
		CLK : IN std_logic;
		CRC32_IN : IN std_logic_vector(31 downto 0);
		DATA_IN : IN std_logic_vector(7 downto 0);
		SAMPLE_CLK_IN : IN std_logic;          
		CRC32_OUT : OUT std_logic_vector(31 downto 0);
		CRC32_VALID : OUT std_logic
		);
	END COMPONENT;

	COMPONENT LFSR11C
	PORT(
		ASYNC_RESET : IN std_logic;
		CLK : IN std_logic;
		BIT_CLK_REQ : IN std_logic;
		SYNC_RESET : IN std_logic;
		SEED : IN std_logic_vector(10 downto 0);          
		LFSR_BIT : OUT std_logic;
		BIT_CLK_OUT : OUT std_logic;
		SOF_OUT : OUT std_logic;
		LFSR_REG_OUT: OUT std_logic_vector(10 downto 0)
		);
	END COMPONENT;
	
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
-- NOTATIONS: 
-- _E as one-CLK early sample
-- _D as one-CLK delayed sample
-- _D2 as two-CLKs delayed sample

--// CLK & RESETS ---------
signal RESETFLAG_D: std_logic := '0';
signal RESETFLAG_D2: std_logic := '0';
signal SYNC_RESET: std_logic := '0';
signal SYNC_RESETRX: std_logic := '0';
signal RESETRX_FLAG_D: std_logic := '0';
signal RESETRX_FLAG_D2: std_logic := '0';


--// PHY RESET AND CONFIGURATION ----------------------------------------------------------
signal RESET_N_LOCAL: std_logic := '0';
signal INITIAL_CONFIG_PULSE: std_logic := '1';
signal PHY_CONFIG_CHANGE_A: std_logic := '0';
signal PHY_RESET_A: std_logic := '0';
signal SPEED_A: std_logic_vector(1 downto 0);
signal DUPLEX_A: std_logic := '0';
signal TEST_MODE_A: std_logic_vector(1 downto 0);
signal POWER_DOWN_A: std_logic := '0';
signal CLK_SKEW_A: std_logic_vector(15 downto 0);
signal MDI: std_logic := '0';
signal MDO: std_logic := '0';
signal MDT: std_logic := '0';
signal RESET_COMPLETE: std_logic := '0';
signal PHY_IF_WRAPPER_RESET: std_logic := '0';
signal SREG_READ_START: std_logic := '0';
signal SREG_SAMPLE_CLK: std_logic := '0';
signal PHY_ID_LOCAL: std_logic_vector(15 downto 0);
signal LINK_STATUS_local: std_logic := '0';
signal DUPLEX_STATUS_local: std_logic := '0';
signal SPEED_STATUS_LOCAL: std_logic_vector(1 downto 0) := (others => '0');
signal TP_RGMII_WRAPPER: std_logic_vector(10 downto 1) := (others => '0');

--//  PHY INTERFACE: GMII to RGMII CONVERSION ----------------------------------------------------------
signal CRS: std_logic := '0';
signal CRS_D: std_logic := '0';
signal COL: std_logic := '0';
signal MAC_TXD: std_logic_vector(7 downto 0) := (others => '0');
signal MAC_TX_EN: std_logic := '0';
signal MAC_TX_ER: std_logic := '0';
signal MAC_TX_SAMPLE_CLK: std_logic := '0';
signal MAC_RXD0: std_logic_vector(7 downto 0);
signal MAC_RX_DV0: std_logic := '0';
signal MAC_RX_ER0: std_logic := '0';
signal MAC_RX_SAMPLE_CLK0: std_logic := '0'; 
signal MAC_RXD: std_logic_vector(7 downto 0);
signal MAC_RX_DV: std_logic := '0';
signal MAC_RX_ER: std_logic := '0';
signal MAC_RX_SAMPLE_CLK: std_logic := '0';


--//  TX ELASTIC BUFFER ----------------------------------------------------------
signal MAC_TX_DIA: std_logic_vector(31 downto 0) := (others => '0');
signal MAC_TX_DIPA: std_logic_vector(0 downto 0) := (others => '0');
signal MAC_TX_WPTR: std_logic_vector(11 downto 0) := (others => '0');
signal MAC_TX_WPTR_D: std_logic_vector(11 downto 0) := (others => '0');
signal MAC_TX_WPTR_D2: std_logic_vector(11 downto 0) := (others => '0');
signal MAC_TX_WPTR_D3: std_logic_vector(11 downto 0) := (others => '0');
signal MAC_TX_WPTR_STABLE: std_logic := '0';
signal MAC_TX_WPTR_STABLE_D: std_logic := '0';
signal TX_COUNTER8: std_logic_vector(2 downto 0) :=(others => '0');
signal MAC_TX_WEA: std_logic_vector(1 downto 0) := (others => '0');
signal MAC_TX_BUF_SIZE: std_logic_vector(11 downto 0) := (others => '0');
signal MAC_TX_RPTR: std_logic_vector(11 downto 0) := (others => '1');
signal MAC_TX_RPTR_D: std_logic_vector(11 downto 0) := (others => '1');
signal MAC_TX_RPTR_CONFIRMED: std_logic_vector(11 downto 0) := (others => '1');
signal MAC_TX_RPTR_CONFIRMED_D: std_logic_vector(11 downto 0) := (others => '1');
signal MAC_TX_SAMPLE2_CLK_E: std_logic := '0';
signal MAC_TX_SAMPLE2_CLK: std_logic := '0';
type DOBtype is array(integer range 0 to 1) of std_logic_vector(7 downto 0);
signal MAC_TX_DOB: DOBtype;
type DOPBtype is array(integer range 0 to 1) of std_logic_vector(0 downto 0);
signal MAC_TX_DOPB: DOPBtype;
signal MAC_TX_DATA2: std_logic_vector(7 downto 0) := (others => '0');
signal MAC_TX_EOF2: std_logic := '0';
signal MAC_TX_EOF2_D: std_logic := '0';
signal COMPLETE_TX_FRAMES_INBUF: std_logic_vector(7 downto 0) := x"00";  -- can't have more than 147 frames in a 16k buffer
signal ATLEAST1_COMPLETE_TX_FRAME_INBUF: std_logic := '0';
signal MAC_TX_EOF_TOGGLE: std_logic := '0';
signal MAC_TX_EOF_TOGGLE_D: std_logic := '0';
signal MAC_TX_EOF_TOGGLE_D2: std_logic := '0';
signal MAC_TX_CTS_local: std_logic := '0';

--//-- TX FLOW CONTROL --------------------------------
signal TX_SUCCESS_TOGGLE: std_logic := '0';
signal TX_SUCCESS_TOGGLE_D: std_logic := '0';
signal TX_SUCCESS_TOGGLE_D2: std_logic := '0';
signal MAC_TX_BUF_FREE: std_logic_vector(11 downto 0) := (others => '0');


--// MAC TX STATE MACHINE ----------------------------------------------------------
signal TX_SPEED: std_logic_vector(1 downto 0) := (others => '0');
signal TX_CLK: std_logic := '0';
signal TX_BYTE_CLK: std_logic := '0';
signal TX_BYTE_CLK_D: std_logic := '0';
signal TX_HALF_BYTE_FLAG: std_logic := '0';
signal IPG: std_logic := '0';
signal IPG_CNTR: std_logic_vector(7 downto 0) := (others => '0');  -- TODO CHECK CONSISTENCY WITH TIMER VALUES
signal TX_EVENT1: std_logic := '0';
signal TX_EVENT2: std_logic := '0';
signal TX_EVENT3: std_logic := '0';
signal TX_STATE: integer range 0 to 15 := 0;
signal TX_BYTE_COUNTER: std_logic_vector(18 downto 0) := (others => '0');  -- large enough for counting 2000 bytes in max size packet
signal TX_BYTE_COUNTER2: std_logic_vector(2 downto 0) := (others => '0');  -- small auxillary byte counter for small fields
signal TX_PREAMBLE: std_logic_vector(7 downto 0) := (others => '0');
signal MAC_TX_SAMPLE4_CLK: std_logic := '0';
signal MAC_TX_DATA4: std_logic_vector(7 downto 0) := (others => '0');
signal MAC_TX_DATA4_D: std_logic_vector(7 downto 4) := (others => '0');
signal RETX_ATTEMPT_COUNTER: std_logic_vector(4 downto 0) := (others => '0'); -- re-transmission attempts counter
signal RAND: std_logic_vector(10 downto 0) := (others => '0');
signal RETX_RANDOM_BKOFF: std_logic_vector(9 downto 0) := (others => '0');
signal TX_SUCCESS: std_logic := '0';
signal TX_EN: std_logic := '0';
signal TX_ER: std_logic := '0';

--//  TX 32-BIT CRC COMPUTATION -------------------------------------------------------
signal TX_CRC32: std_logic_vector(31 downto 0) := (others => '0');
signal TX_CRC32_FLIPPED_INV: std_logic_vector(31 downto 0) := (others => '0');
signal TX_CRC32_RESET: std_logic := '0';
signal TX_FCS: std_logic_vector(7 downto 0) := (others => '0');
signal MAC_TX_SAMPLE3_CLK: std_logic := '0';
signal MAC_TX_DATA3: std_logic_vector(7 downto 0) := (others => '0');

--// MAC RX STATE MACHINE ----------------------------------------------------------
signal RX_CLKG: std_logic := '0';
signal RX_STATE: integer range 0 to 15 := 0;
signal RX_EVENT1: std_logic := '0';
--signal RX_EVENT2: std_logic := '0';
signal RX_EVENT3: std_logic := '0';
signal RX_EVENT4: std_logic := '0';
signal RX_EVENT5: std_logic := '0';
signal RX_BYTE_COUNTER: std_logic_vector(18 downto 0);  -- large enough for counting 2000 bytes in max size packet
signal RX_BYTE_COUNTER_INC: std_logic_vector(18 downto 0);  -- large enough for counting 2000 bytes in max size packet
signal RX_TOO_SHORT: std_logic := '0';
signal RX_TOO_LONG: std_logic := '0';
signal RX_VALID_ADDR: std_logic := '0';
signal RX_LENGTH_ERR: std_logic := '0';
signal LAST6B: std_logic_vector(47 downto 0) := (others => '0');
signal RX_LENGTH: std_logic_vector(10 downto 0) := (others => '0');
signal RX_LENGTH_TYPEN: std_logic := '0';
signal RX_DIFF: std_logic_vector(11 downto 0) := (others => '0');
signal MAC_RXD_D: std_logic_vector(7 downto 0) := (others => '0');
signal MAC_RX_SAMPLE2_CLK: std_logic := '0';

--//  RX 32-BIT CRC COMPUTATION -------------------------------------------------------
signal RX_CRC32_RESET: std_logic := '0';
signal RX_CRC32: std_logic_vector(31 downto 0) := (others => '0');
signal RX_CRC32_VALID: std_logic := '0';
signal RX_BAD_CRC: std_logic := '0';

--// PARSE RX DATA -------------------------------------------------------------------
signal MAC_RXD3: std_logic_vector(7 downto 0);
signal MAC_RX_SAMPLE3_CLK: std_logic := '0';
--signal MAC_RX_SOF3: std_logic := '0';
signal MAC_RX_EOF3A: std_logic := '0';
signal MAC_RX_EOF3B: std_logic := '0';
signal MAC_RX_EOF3B_D: std_logic := '0';
signal MAC_RX_EOF3: std_logic := '0';
signal RX_FRAME_EN3: std_logic := '0';

--//  RX INPUT ELASTIC BUFFER ----------------------------------------------------------
signal MAC_RX_DIPA: std_logic_vector(0 downto 0);
signal MAC_RX_DOPB: std_logic_vector(0 downto 0);
signal MAC_RX_WPTR: std_logic_vector(10 downto 0);
signal MAC_RX_WPTR_D: std_logic_vector(10 downto 0);
signal MAC_RX_WPTR_D2: std_logic_vector(10 downto 0);
signal MAC_RX_WPTR_D3: std_logic_vector(10 downto 0);
signal MAC_RX_WPTR_CONFIRMED: std_logic_vector(10 downto 0) := (others => '0');
signal MAC_RX_WPTR_STABLE: std_logic := '0';
signal MAC_RX_WPTR_STABLE_D: std_logic := '0';
signal RX_COUNTER8: std_logic_vector(2 downto 0) := "000";
signal MAC_RX_RPTR: std_logic_vector(10 downto 0);
signal MAC_RXD4: std_logic_vector(7 downto 0);
signal MAC_RX_SAMPLE4_CLK: std_logic := '0';
signal MAC_RX_SAMPLE4_CLK_E: std_logic := '0';
signal MAC_RX_EOF4: std_logic := '0';
signal MAC_RX_BUF_SIZE: std_logic_vector(10 downto 0);
signal MAC_RX_EOF4_FLAG: std_logic := '1';

signal PHY_CONFIG_TP: std_logic_vector(10 downto 1);


--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin


-- PHY-supplied RX global clock
RECLOCK_003: process(ASYNC_RESET, RX_CLKG)
begin	
	if rising_edge(RX_CLKG) then
		RESETRX_FLAG_D <= ASYNC_RESET;
		RESETRX_FLAG_D2 <= RESETRX_FLAG_D;
		
		-- 1-CLK clock synchronous reset pulse at the end of the async pulse
		if(RESETRX_FLAG_D = '0') and (RESETRX_FLAG_D2 = '1') then
			-- end of external reset pulse. generate a CLK synchronous reset
			SYNC_RESETRX <= '1';
		else 
			SYNC_RESETRX <= '0';
		end if;
	end if;
end process;


--// PHY RESET AND CONFIGURATION ----------------------------------------------------------
-- First generate a RESET_N pulse 10ms long, then wait 50ms before programming the PHY
-- We cannot assume that the 125 MHz reference clock is present. 

-- convert ASYNC_RESET to a CLK-synchronous RESET pulse
RECLOCK_002: process(ASYNC_RESET, CLK)
begin	
	if rising_edge(CLK) then
		RESETFLAG_D <= ASYNC_RESET;
		RESETFLAG_D2 <= RESETFLAG_D;
		
		-- 1-CLK clock synchronous reset pulse at the end of the async pulse
		if(RESETFLAG_D = '0') and (RESETFLAG_D2 = '1') then
			-- end of external reset pulse. generate a CLK synchronous reset
			SYNC_RESET <= '1';
		else 
			SYNC_RESET <= '0';
		end if;
	end if;
end process;

-- PHY reset at power up or SYNC_RESET
-- Generates a 10ms RESET_N pulse followed by a TBD ms delay and a INITIAL_CONFIG_PULSE.
-- The delay between RESET_N de-assertion and config pulse is 50ms (conservative. It takes time for PHY to configure.
-- even though the specs states 100us is sufficient, we find that 40ms min is needed).
Inst_RESET_TIMER: RESET_TIMER 
GENERIC MAP(
	CLK_FREQUENCY => CLK_FREQUENCY	-- user clock frequency in MHz
)
PORT MAP(
	CLK => CLK,	-- user clock, always present
	RESET_START => SYNC_RESET,
	RESET_COMPLETE => RESET_COMPLETE,
	INITIAL_CONFIG_PULSE => INITIAL_CONFIG_PULSE,  -- config pulse 50ms after RESET_N deassertion
	RESET_N => RESET_N_LOCAL
);

RESET_N <= RESET_N_LOCAL;

--
---- enact the configuration
PHY_CONFIG_CHANGE_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(INITIAL_CONFIG_PULSE = '1') then
			-- A default configuration is loaded automatically after power up. 
			PHY_CONFIG_CHANGE_A <= '1';
			PHY_RESET_A <= '0';	-- no software PHY reset, we just did a hardware reset
			SPEED_A <= "11";		-- auto
			DUPLEX_A <= '1';		
			TEST_MODE_A <= "00";
			POWER_DOWN_A <= '0';
		elsif(PHY_CONFIG_CHANGE = '1') then
			-- PHY_CONFIG_CHANGE indicates a user-triggered configuration change.
			PHY_CONFIG_CHANGE_A <= '1';
			PHY_RESET_A <= PHY_RESET;
			SPEED_A <= SPEED;
			DUPLEX_A <= DUPLEX;
			TEST_MODE_A <= TEST_MODE;
			POWER_DOWN_A <= POWER_DOWN;
		else
			PHY_CONFIG_CHANGE_A <= '0';
		end if;
	end if;
end process;


-- PHY monitoring and control
Inst_PHY_CONFIG: PHY_CONFIG 
GENERIC MAP(
	PHY_ADDR => PHY_ADDR
)
PORT MAP(
	SYNC_RESET => SYNC_RESET,  
	CLK => CLK,
	CONFIG_CHANGE => PHY_CONFIG_CHANGE_A,
	PHY_RESET => PHY_RESET_A,
	SPEED => SPEED_A,
	DUPLEX => DUPLEX_A,
	TEST_MODE => TEST_MODE_A,
	POWER_DOWN => POWER_DOWN_A,
	CLK_SKEW => CLK_SKEW_A,
	SREG_READ_START => SREG_READ_START,
	SREG_REGAD => "000000010",	-- register 2: PHY Identifier 1
	SREG_DATA => PHY_ID_LOCAL,
	SREG_SAMPLE_CLK => SREG_SAMPLE_CLK,
	LINK_STATUS => LINK_STATUS_local,
	MCLK => MCLK,
	MDI => MDI,
	MDO => MDO,
	MDT => MDT
	);
PHY_ID <= PHY_ID_LOCAL;

---- tri-state MDIO port
--IOBUF_inst : IOBUF
--generic map (
--	DRIVE => 12,
--	IOSTANDARD => "DEFAULT",
--	SLEW => "SLOW")
--port map (
--	O => MDI,     -- Buffer output
--	IO => MDIO,   -- Buffer inout port (connect directly to top-level port)
--	I => MDO,     -- Buffer input
--	T => MDT      -- 3-state enable input, high=input, low=output 
--);


-- read PHY identification once at power-up or reset (hardware self-test)
PHY_STATUS_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(PHY_CONFIG_CHANGE_A = '1') then	-- power-up/reset
			SREG_READ_START <= '1';				-- start asking for status register
		elsif(SREG_SAMPLE_CLK = '1') then
			SREG_READ_START <= '0';
		end if;
	end if;
end process;
--//  PHY INTERFACE: RGMII FORMATTING ----------------------------------------------------------

-- Translation RGMII (PHY interface) - GMII (MAC interface)
-- Adjust the TXC and RXC clock 2ns delays within as needed.
PHY_IF_WRAPPER_RESET <= SYNC_RESETRX;	

LINK_STATUS <= LINK_STATUS_local;
DUPLEX_STATUS <= DUPLEX_STATUS_local;
SPEED_STATUS <= SPEED_STATUS_LOCAL;

--//  PHY INTERFACE: GMII/MII FORMATTING ----------------------------------------------------------
-- TODO: make tx clk the same as rx clk (same RGMII_WRAPPER).
	Inst_GMII_MII_WRAPPER: GMII_MII_WRAPPER_V6 PORT MAP(
		SYNC_RESET => PHY_IF_WRAPPER_RESET,
		CLK => CLK,	
		IDELAYREFCLK200MHZ => IDELAYREFCLK200MHZ,
		TX_CLK => MII_TX_CLK,  -- MII tx clock from PHY
		GTX_CLK => GMII_TX_CLK, -- GMII tx clock to PHY
		TXD => GMII_MII_TXD,
		TX_EN => GMII_MII_TX_EN,
		TX_ER => GMII_MII_TX_ER,
		RX_CLK => GMII_MII_RX_CLK,
		RXD => GMII_MII_RXD,
		RX_DV => GMII_MII_RX_DV,
		RX_ER => GMII_MII_RX_ER,
		CRS => GMII_MII_CRS,
		COL => GMII_MII_COL, 
		MAC_RX_CLK => RX_CLKG,
		MAC_RXD => MAC_RXD0,
		MAC_RX_DV => MAC_RX_DV0,
		MAC_RX_ER => MAC_RX_ER0,
		MAC_RX_SAMPLE_CLK => MAC_RX_SAMPLE_CLK0,
		MAC_TXD => MAC_TXD,
		MAC_TX_EN => MAC_TX_EN,
		MAC_TX_ER => MAC_TX_ER,
		MAC_TX_SAMPLE_CLK => MAC_TX_SAMPLE_CLK,
		MAC_TX_SPEED => TX_SPEED,
		MAC_CRS => CRS,
		MAC_COL => COL,
		LINK_STATUS => open,--LINK_STATUS_local,
		SPEED_STATUS => SPEED_STATUS_LOCAL,
		DUPLEX_STATUS => DUPLEX_STATUS_local
	);

	-- Vodoo code (Isim simulator is confused otherwise). Reclock RX signals.
	-- My guess: simulator does not like the BUFG or delay within the GMII_MII_WRAPPER.
	-- Small penalty: just a few Flip Flops. 
	RX_RECLOCK_001: process(RX_CLKG)
	begin
		if rising_edge(RX_CLKG) then
			MAC_RXD <= MAC_RXD0;
			MAC_RX_DV <= MAC_RX_DV0;
			MAC_RX_ER <= MAC_RX_ER0;
			MAC_RX_SAMPLE_CLK <= MAC_RX_SAMPLE_CLK0;
		end if;
	end process;

--//  TX ELASTIC BUFFER ----------------------------------------------------------
-- The purpose of the elastic buffer is two-fold:
-- (a) a transition between the CLK-synchronous user side, and the RX_CLKG synchronous PHY side
-- (b) storage for Ethernet transmit frames, to absorb traffic peaks, minimize the number of 
-- UDP packets lost at high throughput.
-- The tx elastic buffer is 16Kbits, large enough for TWO complete maximum size 
-- (14addr+1500data+4FCS = 1518B) frames.

-- write pointer management
MAC_TX_WPTR_001: process(ASYNC_RESET, CLK)
begin
	if(ASYNC_RESET = '1') then
		MAC_TX_WPTR <= (others => '0');
	elsif rising_edge(CLK) then
		TX_COUNTER8 <= TX_COUNTER8 + 1;

		if (SYNC_RESET = '1') then
			MAC_TX_WPTR <= (others => '0');
		elsif(MAC_TX_DATA_VALID = '1') then
			MAC_TX_WPTR <= MAC_TX_WPTR + 1;
		end if;
		
		-- update WPTR_D once every 8 clocks.
		if(TX_COUNTER8 = 7) then
			MAC_TX_WPTR_D <= MAC_TX_WPTR;
		end if;
		
		-- allow WPTR reclocking with another clock, as long as it is away from the transition area
		if(TX_COUNTER8 < 6) then
			MAC_TX_WPTR_STABLE <= '1';
		else 
			MAC_TX_WPTR_STABLE <= '0';
		end if;
			
		
	end if;
end process;

MAC_TX_DIPA(0) <= MAC_TX_EOF;  -- indicates last byte in the tx packet

-- select which RAMBlock to write to.
MAC_TX_WEA(0) <= MAC_TX_DATA_VALID and (not MAC_TX_WPTR(11));
MAC_TX_WEA(1) <= MAC_TX_DATA_VALID and MAC_TX_WPTR(11);

-- No need for initialization
RAMB16_X: for I in 0 to 1 generate
	RAMB16_001: RAMB16_S9_S9 
	port map(
		DIA => MAC_TX_DATA,
		DIB => x"00",
		DIPA => MAC_TX_DIPA(0 downto 0),
		DIPB => "0",
		DOPA => open,
		DOPB => MAC_TX_DOPB(I)(0 downto 0),	
		ENA => '1',
		ENB => '1',
		WEA => MAC_TX_WEA(I),
		WEB => '0',
		SSRA => '0',
		SSRB => '0',
		CLKA => CLK,   
		CLKB => RX_CLKG,     
		ADDRA => MAC_TX_WPTR(10 downto 0),
		ADDRB => MAC_TX_RPTR(10 downto 0),
		DOA => open,
		DOB => MAC_TX_DOB(I)
	);
end generate;

MAC_TX_DATA2 <= MAC_TX_DOB(conv_integer(MAC_TX_RPTR_D(11)));
MAC_TX_EOF2 <= MAC_TX_DOPB(conv_integer(MAC_TX_RPTR_D(11)))(0); 

-- RX_CLKG zone. Reclock WPTR
MAC_TX_WPTR_002: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		MAC_TX_WPTR_STABLE_D <= MAC_TX_WPTR_STABLE;
		MAC_TX_WPTR_D2 <= MAC_TX_WPTR_D;
		
		if(MAC_TX_WPTR_STABLE_D = '1') then
			-- WPTR is stable. OK to resample with the RX_CLKG clock.
			MAC_TX_WPTR_D3 <= MAC_TX_WPTR_D2;
		end if;
	end if;
end process;

MAC_TX_BUF_SIZE <= MAC_TX_WPTR_D3 + not(MAC_TX_RPTR);
-- occupied tx buffer size for reading purposes (CLKG clock domain)(
-- always lags, could be a bit more, never less.

--//-- TX FLOW CONTROL --------------------------------
-- ask for more input data if there is room for at least 1K more input bytes
-- Never write past the last confirmed read pointer location.

-- read the last confirmed read pointer location and reclock in CLK domain when stable
MAC_TX_CTS_001: process(CLK)
begin
	if rising_edge(CLK) then
		TX_SUCCESS_TOGGLE_D <= TX_SUCCESS_TOGGLE;
		TX_SUCCESS_TOGGLE_D2 <= TX_SUCCESS_TOGGLE_D;
		if(TX_SUCCESS_TOGGLE_D2 /= TX_SUCCESS_TOGGLE_D) then
			-- shortly after successful packet transmission. 
			MAC_TX_RPTR_CONFIRMED_D <= MAC_TX_RPTR_CONFIRMED;
		end if;
	end if;
end process;

-- Compute available room for more tx data
MAC_TX_CTS_002: process(CLK)
begin
	if rising_edge(CLK) then
		MAC_TX_BUF_FREE <= not (MAC_TX_WPTR_D2 + not MAC_TX_RPTR_CONFIRMED_D);
	end if;
end process;
-- Is there enough room for a complete max size frame?
-- Don't cut it too close because user interface can flood the buffer very quickly (CLK @ 125 MHz clock)
-- while we compute the buffer size with the possibly much slower RX_CLG (could be 2.5 MHz for 10Mbps).
MAC_TX_CTS_003: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESETRX = '1') then
			MAC_TX_CTS_local <= '0';	-- reset
		elsif(LINK_STATUS_local = '0') then
			-- don't ask the stack for data if there is no link
			MAC_TX_CTS_local <= '0';	-- reset
		elsif(MAC_TX_BUF_FREE(11) = '0') then
			-- room for less than 2KB. Activate flow control
			MAC_TX_CTS_local <= '0';
		else
			MAC_TX_CTS_local <= '1';
		end if;
	end if;
end process;
MAC_TX_CTS <=  LINK_STATUS_local;--LINK_STATUS_local;--MAC_TX_CTS_local;


-- manage read pointer
MAC_TX_RPTR_001: process(ASYNC_RESET, RX_CLKG)
begin
	if(ASYNC_RESET = '1') then
		MAC_TX_RPTR <= (others => '1');
		MAC_TX_RPTR_D <= (others => '1');
	elsif rising_edge(RX_CLKG) then
		MAC_TX_RPTR_D <= MAC_TX_RPTR;
		
		if(TX_STATE = 2) and (TX_BYTE_CLK = '1') and (MAC_TX_EOF2 = '1') then
			-- special case. Immediately block output sample clk because we have just read past the end of 
			-- packet (nothing we could do about it).
			MAC_TX_SAMPLE2_CLK <= '0';
		else
			-- regular case:  1 clk delay to extract data from ramb.
			-- aligned with MAC_TX_DATA2 byte.
			MAC_TX_SAMPLE2_CLK <= MAC_TX_SAMPLE2_CLK_E;  
		end if;
	
		if(SYNC_RESETRX = '1') then
			MAC_TX_RPTR <= (others => '1');
		elsif(TX_STATE = 1) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER2(2 downto 0) <= 1) then
			-- read the first byte(s) in advance (need 2 RX_CLKG to get the data out)
			-- Note: we may temporarily read past the write pointer (by one location) 
			-- but will rewind immediately thereafter
			MAC_TX_SAMPLE2_CLK_E <= '1';
			MAC_TX_RPTR <= MAC_TX_RPTR + 1;
		elsif(TX_STATE = 2) and (TX_EVENT3 = '1') then
			-- we are done reading the packet. rewind the read pointer, as we went past the end of packet.
			MAC_TX_SAMPLE2_CLK_E <= '0';
			MAC_TX_RPTR <= MAC_TX_RPTR - 1;
		elsif(TX_STATE = 2) and (TX_BYTE_CLK = '1') then
			-- read the rest of the packet
			-- forward data from input elastic buffer to RGMII interface
			-- Note: we may temporarily read past the write pointer (by one location) 
			-- but will rewind immediately thereafter
			MAC_TX_SAMPLE2_CLK_E <= '1';
			MAC_TX_RPTR <= MAC_TX_RPTR + 1;
		elsif(TX_STATE = 6) then
			-- collision detected. rewind read pointer to the start of frame.
			MAC_TX_RPTR <= MAC_TX_RPTR_CONFIRMED;
		else
			MAC_TX_SAMPLE2_CLK_E <= '0';
		end if;
	end if;
end process;

-- update confirmed read pointer after successful frame transmission
MAC_TX_RPTR_002: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if(SYNC_RESETRX = '1') then
			MAC_TX_RPTR_CONFIRMED <= (others => '1');
			TX_SUCCESS_TOGGLE <= '0';
		elsif(TX_SUCCESS = '1') then
			MAC_TX_RPTR_CONFIRMED <= MAC_TX_RPTR;
			TX_SUCCESS_TOGGLE <= not TX_SUCCESS_TOGGLE;
		end if;
	end if;
end process;

-- How many COMPLETE tx frames are available for transmission in the input elastic buffer?
-- Transmission is triggered by the availability of a COMPLETE frame in the buffer (not just a few frame bytes)
-- It is therefore important to keep track of the number of complete frames.
-- At the elastic buffer input, a new complete frame is detected upon receiving the EOF pulse.
COMPLETE_TX_FRAMES_001: process(ASYNC_RESET, CLK)
begin
	if (ASYNC_RESET = '1') then
		MAC_TX_EOF_TOGGLE <= '0';
	elsif rising_edge(CLK) then
		if(MAC_TX_DATA_VALID = '1') and (MAC_TX_EOF = '1') then
			MAC_TX_EOF_TOGGLE <= not MAC_TX_EOF_TOGGLE;  -- Need toggle signal to generate copy in RX_CLKG clock domain
		end if;
	end if;
end process;


COMPLETE_TX_FRAMES_002: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		MAC_TX_EOF_TOGGLE_D <= MAC_TX_EOF_TOGGLE;	-- reclock in RX_CLKG clock domain (to prevent glitches)
		MAC_TX_EOF_TOGGLE_D2 <= MAC_TX_EOF_TOGGLE_D;

		if (SYNC_RESETRX = '1') then
			COMPLETE_TX_FRAMES_INBUF <= (others => '0');
		
		elsif(MAC_TX_EOF_TOGGLE_D2 /= MAC_TX_EOF_TOGGLE_D) and (TX_SUCCESS = '0') then
			-- just added another complete frame into the tx buffer (while no successful transmission concurrently)
			COMPLETE_TX_FRAMES_INBUF <= COMPLETE_TX_FRAMES_INBUF + 1;
		elsif(MAC_TX_EOF_TOGGLE_D2 = MAC_TX_EOF_TOGGLE_D) and (TX_SUCCESS = '1') 
				and (ATLEAST1_COMPLETE_TX_FRAME_INBUF = '1') then
			-- a frame was successfully transmitted (and none was added at the very same instant)
			COMPLETE_TX_FRAMES_INBUF <= COMPLETE_TX_FRAMES_INBUF - 1;
		end if;
	end if;
end process;

-- Flag to indicate at least one complete tx frame in buffer.
ATLEAST1_COMPLETE_TX_FRAME_INBUF <= '0' when (COMPLETE_TX_FRAMES_INBUF = 0) else '1';


DELAY_EOF2: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if(TX_BYTE_CLK = '1') then
			-- delay by one byte
			MAC_TX_EOF2_D <= MAC_TX_EOF2;
		end if;
	end if;
end process;


--// MAC TX STATE MACHINE ----------------------------------------------------------
TX_SPEED <= SPEED_STATUS_LOCAL;  -- transmit speed is as auto-negotiated by the rx PHY.
-- test test test simulation at various LAN speeds
--TX_SPEED <= "01";  

-- Tx timers ------------------------
-- Generate transmit clock. Depends on the tx_speed.
-- Clock is always enabled, even when not transmitting (reason: we need to be
-- able to convey to the RGMII wrapper when to stop, etc).
-- Important distinction between TX_CLK and TX_BYTE_CLK because GMII interface is 4-bit wide
-- for 10/100 Mbps and 8-bit wide for 1000 Mbps.
-- Thus, TX_BYTE_CLK is half the frequency of TX_CLK, but pulses are aligned.
TX_CLK_GEN_001: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if (SYNC_RESETRX = '1') then
			TX_BYTE_CLK <= '0';
			TX_HALF_BYTE_FLAG <= '0';
		elsif (TX_SPEED = "10") then
			-- 1000 Mbps
			TX_BYTE_CLK <= '1';
		elsif (TX_SPEED = "01") or (TX_SPEED = "00") then
			-- 10/100 Mbps. 
			-- divide by two to get the byte clock when 10/100 Mbps
			TX_HALF_BYTE_FLAG <= not TX_HALF_BYTE_FLAG;
			if(TX_HALF_BYTE_FLAG = '1') then
				TX_BYTE_CLK <= '1';
			else
				TX_BYTE_CLK <= '0';
			end if;
		else
			TX_BYTE_CLK <= '0';
		end if;	
	end if;
end process;


-- 96-bit InterPacketGap (Interframe Delay) timer
IPG_001: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if (SYNC_RESETRX = '1') then
			IPG_CNTR <= (others => '0');
			CRS_D <= '0';
		else
			CRS_D <= CRS;  -- reclock with RX_CLKG

			if((CRS_D = '1') and (DUPLEX = '0')) or (TX_EN = '1') or (TX_STATE = 5) then
				-- detected passing packet (half-duplex only) or transmission is in progress 
				-- or carrier extension in progress
				-- Arm InterPacketGap timer
				IPG_CNTR <= x"0C"  ; -- 96 bits = 12 bytes  802.3 section 4.4.2
			elsif(IPG_CNTR > 0) and (TX_BYTE_CLK = '1') then
				-- after end of passing packet, decrement counter downto to zero (InterPacketGap).
				IPG_CNTR <= IPG_CNTR - 1;
			end if;
		end if;
	end if;
end process;
IPG <= '1' when (IPG_CNTR = 0) else '0';  -- '1' last passing packet was more than InterPacketGap ago. OK to start tx.

-- Events ------------------------
-- First tx packet trigger
TX_EVENT1 <= '0' when (ATLEAST1_COMPLETE_TX_FRAME_INBUF = '0') else -- no COMPLETE frame in tx input buffer
				 '0' when (MAC_TX_BUF_SIZE = 0) else -- no data in tx input buffer
				 '0' when (IPG = '0') else -- medium is not clear. need to wait after the InterPacketGap. Deferring on.
				 '0' when (TX_SUCCESS = '1') else  -- don't act too quickly. It takes one RX_CLKG to update the complete_tx_frame_inbuf counter.
				 '0' when (PHY_IF_WRAPPER_RESET = '1') else -- PHY/RGMII wrapper are being reset. Do not start tx.
				 TX_BYTE_CLK;  -- go ahead..start transmitting. align event pulse with TX_BYTE_CLK
				 
-- collision detection, half-duplex mode, within the timeSlot
-- Timeslot is 64 bytes for 10/100 Mbps and 512 bytes for 1000 Mbps, starting at the preamble.
TX_EVENT2 <= '1' when ((COL = '1') and (DUPLEX = '0') and (TX_SPEED = "10") and (TX_BYTE_COUNTER(10 downto 0) < 503)) else
				 '1' when ((COL = '1') and (DUPLEX = '0') and (TX_SPEED(1) = '0') and (TX_BYTE_COUNTER(10 downto 0) < 55)) else
				 '0';
				 
-- end of frame detected at tx buffer output. 
-- Timing depends on the TX_SPEED (because of the delay in reading data from tx buffer output)
TX_EVENT3 <= '1' when (TX_BYTE_CLK = '1') and (MAC_TX_EOF2 = '1') and (TX_SPEED = "10") else
			    '1' when (TX_BYTE_CLK = '1') and (MAC_TX_EOF2_D = '1') and (TX_SPEED(1) = '0') else
				 '0';

-- Tx state machine ------------------------
TX_STATE_GEN_001: process(RX_CLKG, MAC_ADDR)
begin
	if rising_edge(RX_CLKG) then
		if (SYNC_RESETRX = '1') or (LINK_STATUS_local = '0') then
			TX_STATE <= 0;	-- idle state
			TX_SUCCESS <= '0'; 
			TX_BYTE_CLK_D <= '0';
			RETX_ATTEMPT_COUNTER <= (Others => '0');  -- re-transmission attempts counter
		else

			TX_BYTE_CLK_D <= TX_BYTE_CLK;  -- output byte ready one RX_CLKG later 
			
			if(TX_STATE = 0) then
				TX_SUCCESS <= '0'; 
				RETX_ATTEMPT_COUNTER <= (Others => '0');  -- reset re-transmission attempts counter
				if (TX_EVENT1 = '1') then
					-- start tx packet: send 1st byte of preamble
					TX_STATE <= 1; 
					TX_BYTE_COUNTER2 <= "111"; -- 8-byte preamble + start of frame sequence
				end if;
			elsif(TX_STATE = 1) and (DUPLEX = '0') and (COL = '1')  then
				-- collision sensing while in half-duplex mode. 
				-- The packet header being transmitted is well within the slot time limit.
				TX_STATE <= 6;  -- send jam
				TX_BYTE_COUNTER2 <= "011"; -- jamSize = 32 bits = 4 Bytes
			elsif(TX_STATE = 1) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER2(2 downto 0) /= 0) then
				-- counting through the preamble + start frame sequence
				TX_BYTE_COUNTER2 <= TX_BYTE_COUNTER2 - 1;
			elsif(TX_STATE = 1) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER2(2 downto 0) = 0) then
				-- end of preamble. start forwarding data from elastic buffer to RGMII wrapper
				TX_STATE <= 2; 
				TX_BYTE_COUNTER <= (others => '0');
			elsif(TX_STATE = 2) and (TX_EVENT2 = '1') then
				-- collision sensing while in half-duplex mode and within the specified slot time (starting at the preamble)
				TX_STATE <= 6;  -- send jam
				TX_BYTE_COUNTER2 <= "011"; -- jamSize = 32 bits = 4 Bytes
			elsif(TX_STATE = 2) and (TX_BYTE_CLK = '1') and (TX_EVENT3 = '0') then
				-- keep track of the payload byte count (to detect the need for padding)
				TX_BYTE_COUNTER <= TX_BYTE_COUNTER + 1;
			elsif(TX_STATE = 2) and (TX_BYTE_CLK = '1') and (TX_EVENT3 = '1')  then
				-- found end of frame
				TX_BYTE_COUNTER <= TX_BYTE_COUNTER + 1;
				if (TX_BYTE_COUNTER(10 downto 0) < 59) then 
					if (MAC_TX_CONFIG(1 downto 0) = "11") then
						-- frame is too short: payload data does not meet minimum 60-byte size.
						-- user enabled automatic padding and automatic CRC32 insertion
						TX_STATE <= 3;
					else
						-- error: frame is too short. abort.
						TX_STATE <= 10;
					end if;
				elsif (MAC_TX_CONFIG(1) = '1') then
					-- user enabled auto-CRC32 insertion. Start inserting CRC
					TX_STATE <= 4;
					TX_BYTE_COUNTER2 <= "011";	-- 4-byte CRC(FCS)
				elsif (TX_BYTE_COUNTER(10 downto 0) >= 63) then
					-- complete packet (including user-supplied CRC)
					-- Carrier Extension?  Applicable to 1000 Mbps half-duplex
					if(TX_SPEED = "10") and (DUPLEX = '0') and (TX_BYTE_COUNTER(10 downto 0) < 511) then
						-- Carrier extension to slotTime (512 bytes) as per 802.3 Section 4.2.3.4
						TX_STATE <= 5;
					else
						-- we are done here
						TX_STATE <= 0;
						TX_SUCCESS <= '1'; -- completed frame transmission
					end if;
				else
					-- error. frame is too short (< 64 bytes including 4-byte CRC). abort.
					TX_STATE <= 10;
				end if;
			elsif(TX_STATE = 3) and (TX_EVENT2 = '1') then
				-- collision sensing while in half-duplex mode and within the specified slot time (starting at the preamble)
				TX_STATE <= 6;  -- send jam
				TX_BYTE_COUNTER2 <= "011"; -- jamSize = 32 bits = 4 Bytes
			elsif(TX_STATE = 3) and (TX_BYTE_CLK = '1') then
				TX_BYTE_COUNTER <= TX_BYTE_COUNTER + 1;
				if(TX_BYTE_COUNTER(10 downto 0) < 59) then
					-- padding payload field to the minimum size.
					-- keep track of the byte count 
				elsif (MAC_TX_CONFIG(1) = '1') then
					-- Completed padding. User enabled CRC32 insertion. Start inserting CRC
					TX_STATE <= 4;
					TX_BYTE_COUNTER2 <= "011";	-- 4-byte CRC(FCS)
				else
					-- error. Illegal user configuration. auto-pad requires auto-CRC. abort.
					TX_STATE <= 10;
				end if;
			elsif(TX_STATE = 4) and (TX_EVENT2 = '1') then
				-- collision sensing while in half-duplex mode and within the specified slot time (starting at the preamble)
				TX_STATE <= 6;  -- send jam
				TX_BYTE_COUNTER2 <= "011"; -- jamSize = 32 bits = 4 Bytes
			elsif(TX_STATE = 4) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER2(1 downto 0) /= 0) then
				-- counting through the CRC/FCS sequence
				TX_BYTE_COUNTER2 <= TX_BYTE_COUNTER2 - 1;
				TX_BYTE_COUNTER <= TX_BYTE_COUNTER + 1;
			elsif(TX_STATE = 4) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER2(1 downto 0) = 0) then
				-- end of CRC/FCS. Packet is now complete. 
				TX_BYTE_COUNTER <= TX_BYTE_COUNTER + 1;
				-- Carrier Extension?  Applicable to 1000 Mbps half-duplex
				if(TX_SPEED = "10") and (DUPLEX = '0') and (TX_BYTE_COUNTER(10 downto 0) < 511) then
					-- Carrier extension to slotTime (512 bytes) as per 802.3 Section 4.2.3.4
					TX_STATE <= 5;
				else
					-- we are done here
					TX_STATE <= 0;
					TX_SUCCESS <= '1'; -- completed frame transmission
				end if;
			elsif(TX_STATE = 5) and (TX_EVENT2 = '1') then
				-- collision sensing while in half-duplex mode and within the specified slot time (starting at the preamble)
				TX_STATE <= 6;  -- send jam
				TX_BYTE_COUNTER2 <= "011"; -- jamSize = 32 bits = 4 Bytes
			elsif(TX_STATE = 5) and (TX_BYTE_CLK = '1') then
				-- Carrier extension
				TX_BYTE_COUNTER <= TX_BYTE_COUNTER + 1;
				if(TX_BYTE_COUNTER(10 downto 0) >= 511) then
					-- met slotTime requirement.
					TX_STATE <= 0;
					TX_SUCCESS <= '1'; -- completed frame transmission
				end if;
			elsif(TX_STATE = 6) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER2(1 downto 0) /= 0) then
				-- Jam . counting through the 4-byte jam
				TX_BYTE_COUNTER2 <= TX_BYTE_COUNTER2 - 1;
			elsif(TX_STATE = 6) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER2(1 downto 0) = 0) then
				-- end of Jam

				-- re-transmit?
				if(RETX_ATTEMPT_COUNTER < 16) then
					-- we have not yet reached the attemptLimit
					TX_STATE <= 7;  -- backoff 
					RETX_ATTEMPT_COUNTER <= RETX_ATTEMPT_COUNTER + 1;
					-- set backoff
					if(TX_SPEED = "10") then
						-- 1000 Mbps. Backoff is an integer multiple of slotTime: 
						-- random * slotTime. slotTime = 512 Bytes
						TX_BYTE_COUNTER(8 downto 0) <= (others => '1');
						TX_BYTE_COUNTER(18 downto 9) <= RETX_RANDOM_BKOFF;  -- uniform random variable. range 0 - 1023
					elsif(TX_SPEED(1) = '0') then
						-- 10/100 Mbps. Backoff is an integer multiple of slotTime:
						-- random * slotTime. slotTime = 64 Bytes
						TX_BYTE_COUNTER(5 downto 0) <= (others => '1');
						TX_BYTE_COUNTER(15  downto 6) <= RETX_RANDOM_BKOFF;  -- uniform random variable. range 0 - 1023;
						TX_BYTE_COUNTER(18 downto 16) <= (others => '0');
					end if;
				else
					TX_STATE <= 10;	-- error. could not transmit packet
				end if;
			elsif(TX_STATE = 7) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER /= 0) then
				-- backoff timer
				TX_BYTE_COUNTER <= TX_BYTE_COUNTER - 1;
			elsif(TX_STATE = 7) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER = 0) then
				-- backoff timer expired. try sending again
				-- start tx packet: send 1st byte of preamble
				TX_STATE <= 1; 
				TX_BYTE_COUNTER2 <= "111"; -- 8-byte preamble + start of frame sequence
			end if;
		end if;
	end if;
end process;

-- Tx packet assembly ------------------------
-- generate 7-byte preamble, 1-byte start frame sequence
-- TX_PREAMBLE is aligned with TX_BYTE_CLK_D
PREAMBLE_GEN_001: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if(TX_STATE = 1) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER2(2 downto 0) = 1) then
			TX_PREAMBLE <= "11010101";  -- start frame delimiter (SFD). 
			-- [note: standard shows LSb D0 to the left, MSb D7 to the right, as per serial transmission sequence.]
		elsif(TX_BYTE_CLK = '1') then
			-- new packet or re-transmission
			TX_PREAMBLE <= "01010101";  -- preamble
			-- [note: standard shows LSb to the left, MSb to the right, as per serial transmission sequence.]
		end if;
	end if;
end process;

-- mux 4-byte frame check sequence
-- TX_FCS is aligned with TX_BYTE_CLK_D
FCS_GEN_001: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		-- send MSB first (802.11 Section 3.2.9).
		-- Don't have time to reclock TX_CRC32_FLIPPED_INV(31 downto 24): will be muxed without reclocking.
		if(TX_STATE = 4) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER2(1 downto 0) = 3) then
			TX_FCS <= TX_CRC32_FLIPPED_INV(23 downto 16);	
		elsif(TX_STATE = 4) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER2(1 downto 0) = 2) then
			TX_FCS <= TX_CRC32_FLIPPED_INV(15 downto 8);	
		elsif(TX_STATE = 4) and (TX_BYTE_CLK = '1') and (TX_BYTE_COUNTER2(1 downto 0) = 1) then
			TX_FCS <= TX_CRC32_FLIPPED_INV(7 downto 0);
		end if;
	end if;
end process;


TX_EN <= '0' when (TX_STATE = 0) else  -- idle
			'1' when (TX_STATE < 5) else  -- normal transmission
			'1' when (TX_STATE = 6) else  -- 32-bit jam after collision detection
			'0';
			
TX_ER <= '1' when (TX_STATE = 5) else  -- carrier extension
			'0';

-- mux preamble, start frame sequence, data, fcs, etc and forward to GMII tx interface
-- MAC_TX_DATA4 is aligned with TX_BYTE_CLK_D
TX_MUX_001: process(TX_STATE, TX_BYTE_COUNTER2, TX_PREAMBLE, MAC_TX_DATA2, TX_CRC32_FLIPPED_INV, TX_FCS)
begin
	if(TX_STATE = 1) then
		-- 7-byte preamble and 1-byte start frame sequence
		MAC_TX_DATA4 <= TX_PREAMBLE;
	elsif(TX_STATE = 2) then
		-- payload data
		MAC_TX_DATA4 <= MAC_TX_DATA2;
	elsif(TX_STATE = 3) then
		-- padding
		MAC_TX_DATA4 <= x"00";  -- padding with zeros.
	elsif(TX_STATE = 4) and (TX_BYTE_COUNTER2(1 downto 0) = 3) then
		-- Frame Check Sequence
		MAC_TX_DATA4 <= TX_CRC32_FLIPPED_INV(31 downto 24);	-- no time to reclock. need it now
	elsif(TX_STATE = 4) and (TX_BYTE_COUNTER2(1 downto 0) < 3) then
		-- Frame Check Sequence
		MAC_TX_DATA4 <= TX_FCS;
	elsif(TX_STATE = 5) then
		-- carrier extend
		MAC_TX_DATA4 <= x"0F";  
	else
	-- TODO tail end
		MAC_TX_DATA4 <= x"00";
	end if;
end process;

MAC_TX_SAMPLE4_CLK <= TX_BYTE_CLK_D when (TX_STATE /= 0) else '0';
		
-- signal conditioning for the TX GMII interface
GMII_TX_GEN: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if (SYNC_RESETRX = '1') then
			MAC_TXD <= (others => '0');
			MAC_TX_EN <= '0';
			MAC_TX_ER <= '0';
			MAC_TX_SAMPLE_CLK <= '0';
			MAC_TX_DATA4_D <= (others => '0');
		elsif(TX_BYTE_CLK_D = '1') then
			MAC_TXD <= MAC_TX_DATA4;
			MAC_TX_EN <= TX_EN;
			MAC_TX_ER <= TX_ER;
			MAC_TX_SAMPLE_CLK <= '1';
		else
			MAC_TX_SAMPLE_CLK <= '0';
		end if;
	end if;
end process;

	
-- Tx random backoff ------------------------
-- Use LFSR11 as generator of a uniform random distribution of numbers between 0 and 2047
Inst_LFSR11C: LFSR11C PORT MAP(
	ASYNC_RESET => '0',
	CLK => RX_CLKG,
	BIT_CLK_REQ => TX_BYTE_CLK,	-- keep generating new random number
	SYNC_RESET => SYNC_RESETRX,   
	SEED => "00000000001",
	LFSR_BIT => open,
	BIT_CLK_OUT => open,
	SOF_OUT => open,
	LFSR_REG_OUT => RAND
);



-- limit the random number range depending on the number of transmission attempts
-- see 802.3 standard section 4.2.3.2.5 for details.
RETX_RAND_BKOFF_GEN: process(RAND, RETX_ATTEMPT_COUNTER)
begin
	case RETX_ATTEMPT_COUNTER is
		when "00000" => RETX_RANDOM_BKOFF <= RAND(9 downto 0) and "0000000001";  -- first attempt: r = 0,1	
		when "00001" => RETX_RANDOM_BKOFF <= RAND(9 downto 0) and "0000000011";  -- second attempt: r = 0-3
		when "00010" => RETX_RANDOM_BKOFF <= RAND(9 downto 0) and "0000000111";  -- third attempt: r = 0-7	
		when "00011" => RETX_RANDOM_BKOFF <= RAND(9 downto 0) and "0000001111";  -- etc	
		when "00100" => RETX_RANDOM_BKOFF <= RAND(9 downto 0) and "0000011111";  	
		when "00101" => RETX_RANDOM_BKOFF <= RAND(9 downto 0) and "0000111111";  	
		when "00110" => RETX_RANDOM_BKOFF <= RAND(9 downto 0) and "0001111111";  
		when "00111" => RETX_RANDOM_BKOFF <= RAND(9 downto 0) and "0011111111";  	
		when "01000" => RETX_RANDOM_BKOFF <= RAND(9 downto 0) and "0111111111";  	
		when others => RETX_RANDOM_BKOFF <= RAND(9 downto 0);   -- cap range to r = 0-1023  	
	end case;
end process;
		

--//  TX 32-BIT CRC COMPUTATION -------------------------------------------------------
-- 802.3 section 3.2.9: 
-- protected fields: payload data + padding (excludes preamble and start of frame sequence)
MAC_TX_DATA3 <= MAC_TX_DATA2 when (TX_STATE = 2) else x"00";  -- padding with zeros
MAC_TX_SAMPLE3_CLK <= TX_BYTE_CLK_D when ((TX_STATE = 2) or (TX_STATE = 3)) else '0'; 

TX_CRC32_RESET <= '1' when (TX_STATE = 1) else '0';  -- reset CRC2 during the packet preamble (covers the re-transmission case)

-- latency 1 RX_CLKG
TX_CRC32_8B: CRC32_8B PORT MAP(
	SYNC_RESET => TX_CRC32_RESET,
	CLK => RX_CLKG,
	CRC32_IN => TX_CRC32,  -- feedback previous iteration
	DATA_IN => MAC_TX_DATA3,	
	SAMPLE_CLK_IN => MAC_TX_SAMPLE3_CLK,
	CRC32_OUT => TX_CRC32,
	CRC32_VALID => open
);

-- flip LSb<->MSb and invert
TX_CRC32_002: process(TX_CRC32)
begin
	for I in 0 to 7 loop
		TX_CRC32_FLIPPED_INV(I) <= not TX_CRC32(7 - I);
		TX_CRC32_FLIPPED_INV(I + 8) <= not TX_CRC32(15 - I);
		TX_CRC32_FLIPPED_INV(I + 16) <= not TX_CRC32(23 - I);
		TX_CRC32_FLIPPED_INV(I + 24) <= not TX_CRC32(31 - I);
	end loop;
end process;

--// MAC RX STATE MACHINE ----------------------------------------------------------
-- remember the last rx byte
RX_DELAY_001: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if (MAC_RX_SAMPLE_CLK = '1') then
			MAC_RXD_D <= MAC_RXD;
		end if;
	end if;
end process;


-- Rx events ------------------------
-- new packet. RX_DV is asserted and detected start of frame delimiter (SFD)
RX_EVENT1 <= '1' when (MAC_RX_SAMPLE_CLK = '1') and (MAC_RX_DV = '1') and (MAC_RX_ER = '0') 
							and (MAC_RXD_D = x"D5")  else '0';	
-- false carrier indication  (TODO: what for???)  xE for 10/1000, x0E for 1000 Mbps
--RX_EVENT2 <= '1' when (MAC_RX_SAMPLE_CLK = '1') and (MAC_RX_DV = '0') and (MAC_RX_ER = '1') 
--							and (MAC_RXD(3 downto 0) = x"E")  else '0';	

-- end of frame delimiter
RX_EVENT3 <= '1' when (MAC_RX_SAMPLE_CLK = '1') and (MAC_RX_DV = '0') else
				 '0';
				 
-- valid frame byte (data, padding, crc)
RX_EVENT4 <= '1' when (MAC_RX_SAMPLE_CLK = '1') and (MAC_RX_DV = '1') and (MAC_RX_ER = '0') else
				 '0';
				
-- frame complete, all checks complete
RX_EVENT5 <= MAC_RX_EOF3B_D;



-- Rx state machine ------------------------
RX_BYTE_COUNTER_INC <= RX_BYTE_COUNTER + 1;

RX_STATE_GEN_001: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if (SYNC_RESETRX = '1') then
			RX_STATE <= 0;
		elsif(RX_STATE = 0) and (RX_EVENT1 = '1') then
			-- RX_DV is asserted and detected start of frame delimiter (SFD)
			-- Note: the preamble could be full, partial or entirely missing.
			RX_STATE <= 1;
			RX_BYTE_COUNTER <= (others => '0');
		elsif(RX_STATE = 1) and (RX_EVENT3 = '1') then
			-- end of frame delimiter
			RX_STATE <= 2;
		elsif(RX_STATE = 1) and (RX_EVENT4 = '1') then
			-- count bytes within frame
			RX_BYTE_COUNTER <= RX_BYTE_COUNTER_INC;
			-- shift-in the last 6 bytes (efficient when decoding address field or length/type field)
			-- MSB (47 downto 40) is received first.
			LAST6B(47 downto 8) <= LAST6B(39 downto 0);
			LAST6B(7 downto 0) <= MAC_RXD_D;
		elsif(RX_STATE = 2) and (RX_EVENT5 = '1') then
			-- frame complete, all checks complete
			RX_STATE <= 0;
		end if;
	end if;
end process;

-- Assess whether rx frame is too short (collision) or too long?
-- ready at RX_STATE 2
RX_TOO_SHORT_GEN: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if(RX_STATE = 1) and (RX_EVENT3 = '1') then
			-- end of frame delimiter
			if(RX_BYTE_COUNTER_INC(18 downto 6) = 0) then  -- < 64 bytes
				-- too short 6+6+2+46+4 = 64
				RX_TOO_SHORT <= '1';
				RX_TOO_LONG <= '0';
			elsif(RX_BYTE_COUNTER_INC(18 downto 11) /= 0) or 
				(RX_BYTE_COUNTER_INC(10 downto 0)> 1518) then  -- > 1518 bytes
				-- too long. 6+6+2+1500+4 = 1418
				RX_TOO_SHORT <= '0';
				RX_TOO_LONG <= '1';
			else
				RX_TOO_SHORT <= '0';
				RX_TOO_LONG <= '0';
			end if;
		end if;
	end if;
end process;

-- Destination address check
ADDR_CHECK_GEN: process(RX_CLKG, MAC_RX_CONFIG, MAC_ADDR)
begin
	if rising_edge(RX_CLKG) then
		if(MAC_RX_CONFIG(0) = '1') then
			-- promiscuous mode. No destination address check
			RX_VALID_ADDR <= '1';
		elsif(RX_STATE = 1) and (RX_EVENT4 = '1') and (RX_BYTE_COUNTER = 6) then
			-- end of destination address field. Check address
			if(LAST6B = MAC_ADDR) then
				-- destination address matches
				RX_VALID_ADDR <= '1';
			elsif (LAST6B = x"FFFFFFFFFFFF") and (MAC_RX_CONFIG(1) = '1') then
				-- accepts broadcast packets with the broadcast destination address FF:FF:FF:FF:FF:FF. 
				RX_VALID_ADDR <= '1';
			elsif (LAST6B(42) = '1') and (MAC_RX_CONFIG(2) = '1') then
				-- accept multicast packets with the multicast bit set in the destination address. 
				-- '1' in the LSb of the first address byte.
				RX_VALID_ADDR <= '1';
		   else
				RX_VALID_ADDR <= '0';
			end if;
		end if;
	end if;
end process;

-- Length/type field check
LENGTH_CHECK_GEN: process(RX_CLKG, MAC_RX_CONFIG, MAC_ADDR)
begin
	if rising_edge(RX_CLKG) then
		if(RX_EVENT1 = '1') then
			-- assume type field by default at the start of frame
			RX_LENGTH_TYPEN <= '0';  -- length/type field represents a type. ignore the length value.
		elsif(RX_STATE = 1) and (RX_EVENT4 = '1') and (RX_BYTE_COUNTER = 14) then
			-- end of length/type field
			if(LAST6B(15 downto 11) = 0) and (LAST6B(10 downto 0) <= 1500) then
				-- this field is interpreted as "Length" = client data field size
				-- MSB first (802.3 section 3.2.6)
				RX_LENGTH <= LAST6B(10 downto 0);  
				RX_LENGTH_TYPEN <= '1';  -- length/type field represents a length
			else
				RX_LENGTH_TYPEN <= '0';  -- length/type field represents a type. ignore the length value.
			end if;
		end if;
	end if;
end process;

-- compute the difference between RX_BYTE_COUNTER and RX_LENGTH (meaningless, but help minimize gates)
RX_DIFF <= RX_BYTE_COUNTER(11 downto 0) - ('0' & RX_LENGTH);

-- Length field consistency with actual rx frame length. Check if the length/type field is 'length'
RX_LENGTH_ERR_GEN: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if(RX_LENGTH_TYPEN = '0') then
			-- type field. No explicit length info. Can't validate actual length.
			RX_LENGTH_ERR <= '0'; 
		elsif(MAC_RX_EOF3B = '1') then
			if(RX_LENGTH <= 46) then
				-- short rx frame is padded to the minimum size of 60 bytes + 4 CRC
				if(RX_BYTE_COUNTER = 63) then
					-- correct answer.
					RX_LENGTH_ERR <= '0'; 
				else
					-- inconsistency
					RX_LENGTH_ERR <= '1'; 
				end if;
			else
				-- normal size frame. no pad.
				if(RX_DIFF = 17) then
					-- correct answer.
					RX_LENGTH_ERR <= '0'; 
				else
					-- inconsistency
					RX_LENGTH_ERR <= '1'; 
				end if;
			end if;
		end if;
	end if;
end process;



--//  RX 32-BIT CRC COMPUTATION -------------------------------------------------------
-- 802.3 section 3.2.9: 
-- protected fields: payload data + optional pad + CRC (excludes preamble and start of frame sequence)
MAC_RX_SAMPLE2_CLK <= '1' when (RX_STATE = 1) and (MAC_RX_SAMPLE_CLK = '1')  else '0'; 

RX_CRC32_RESET <= '1' when (RX_STATE = 0) else '0';  -- reset CRC2 during the packet preamble 

-- latency 1 RX_CLKG
RX_CRC32_8B: CRC32_8B PORT MAP(
	SYNC_RESET => RX_CRC32_RESET,
	CLK => RX_CLKG,
	CRC32_IN => RX_CRC32,  -- feedback previous iteration
	DATA_IN => MAC_RXD_D,	
	SAMPLE_CLK_IN => MAC_RX_SAMPLE2_CLK,
	CRC32_OUT => RX_CRC32,
	CRC32_VALID => RX_CRC32_VALID
);

-- assess whether the frame check sequence is valid
-- ready one RX_CLKG after the start of RX_STATE 2
RX_BAD_CRC_GEN: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if(RX_STATE = 2) then
			-- end of frame delimiter
			RX_BAD_CRC <= not RX_CRC32_VALID;
		end if;
	end if;
end process;

--// PARSE RX DATA -------------------------------------------------------------------
-- Delay data by 1 byte (otherwise we will only know about EOF AFTER the last byte is received)
MAC_RXD3 <= MAC_RXD_D;

-- SOF
--MAC_RX_SOF3 <= MAC_RX_SAMPLE_CLK when (RX_STATE = 1) and (RX_BYTE_COUNTER = 0) else '0';

-- EOF based on the length field (does not include pad nor CRC). Meaningless when the type/length field 
-- is used as type. 
MAC_RX_EOF3A <= '1' when (RX_STATE = 1) and (RX_EVENT4 = '1') and (RX_DIFF = 13) else '0';

-- EOF based on the RX_DV deassertion.
MAC_RX_EOF3B <= '1' when (RX_STATE = 1) and (RX_EVENT3 = '1') else '0';

MAC_RX_EOF3 <=  MAC_RX_EOF3B when (RX_LENGTH_TYPEN = '0') else MAC_RX_EOF3A;
MAC_RX_SAMPLE3_CLK <= MAC_RX_SAMPLE_CLK and RX_FRAME_EN3;

RX_FILTEROUT_001: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		if (SYNC_RESETRX = '1') then
			RX_FRAME_EN3 <= '0';
		elsif(RX_STATE = 0) and (RX_EVENT1 = '1') then
			RX_FRAME_EN3 <= '1';
		elsif(MAC_RX_EOF3 = '1') then
			RX_FRAME_EN3 <= '0';
		end if;
	end if;
end process;
		
--//  VALID RX FRAME? ----------------------------------------------------------
-- Is the rx frame valid? If so, confirm the wptr location.

MAC_RX_VALID_001: process(RX_CLKG)
begin
	if rising_edge(RX_CLKG) then
		-- wait one more CLK period until all validity checks are complete
		MAC_RX_EOF3B_D <= MAC_RX_EOF3B;

		if(SYNC_RESETRX = '1') then
			MAC_RX_WPTR_CONFIRMED <= (others => '0');
		else 
			if(RX_EVENT5 = '1') then
				-- frame complete, all checks complete
				if(RX_CRC32_VALID = '0') then
					-- BAD_CRC
					-- TODO error counter
				elsif(RX_TOO_SHORT = '1') then
					-- frame is too short (<64B)
					-- TODO error counter
				elsif(RX_TOO_LONG = '1') then
					-- frame is too long (>1518B)
					-- TODO error counter
				elsif(RX_VALID_ADDR = '0') then
					-- address does not match (and promiscuous mode is off)
					-- TODO counter
				elsif(RX_LENGTH_ERR = '1') then
					-- length field is inconsistent with actual rx frame length
					-- TODO counter
				else
					-- passed all checks
					-- update confirmed value for MAC_RX_WPTR
					if(MAC_RX_CONFIG(3) = '1') then
						-- filter out 4-byte CRC-32
						MAC_RX_WPTR_CONFIRMED <= MAC_RX_WPTR - 4;
					else
						-- include 4-byte CRC-32
						MAC_RX_WPTR_CONFIRMED <= MAC_RX_WPTR;
					end if;
				end if;
				
			end if;
		end if;
	end if;
end process;



--//  RX INPUT ELASTIC BUFFER ----------------------------------------------------------
-- The purpose of the elastic buffer is two-fold:
-- (a) a transition between the RX_CLKG synchronous PHY side and the CLK-synchronous user side.
-- (b) storage for receive packets, to absorb traffic peaks, minimize the number of 
-- UDP packets lost at high throughput.
-- The rx elastic buffer is 16Kbits, large enough for a complete maximum size (14addr+1500data+4FCS = 1518B) frame.

-- write pointer management
MAC_RX_WPTR_001: process(ASYNC_RESET, RX_CLKG)
begin
	if(ASYNC_RESET = '1') then
		MAC_RX_WPTR <= (others => '0');
		MAC_RX_WPTR_D <= (others => '0');
	elsif rising_edge(RX_CLKG) then
		RX_COUNTER8 <= RX_COUNTER8 + 1;

		if(SYNC_RESETRX = '1') then
			MAC_RX_WPTR <= (others => '0');
		elsif(RX_STATE = 0) then
			-- re-position the write pointer (same or rewind if previous frame was invalid
			MAC_RX_WPTR <= MAC_RX_WPTR_CONFIRMED;
		elsif(MAC_RX_SAMPLE3_CLK = '1') then
			MAC_RX_WPTR <= MAC_RX_WPTR + 1;
		end if;
		
		-- update WPTR_D once every 8 clocks.
		if(SYNC_RESETRX = '1') then
			MAC_RX_WPTR_D <= (others => '0');
		elsif(RX_COUNTER8 = 7) then
			MAC_RX_WPTR_D <= MAC_RX_WPTR_CONFIRMED;
		end if;
		
		-- allow WPTR reclocking with another clock, as long as it is away from the transition area
		if(RX_COUNTER8 < 6) then
			MAC_RX_WPTR_STABLE <= '1';
		else 
			MAC_RX_WPTR_STABLE <= '0';
		end if;
			
		
	end if;
end process;



MAC_RX_DIPA(0) <= MAC_RX_EOF3;  -- indicates last byte in the rx packet

-- No need for initialization
RAMB16_002: RAMB16_S9_S9 
port map(
	DIA => MAC_RXD3,
	DIB => x"00",
	DIPA => MAC_RX_DIPA(0 downto 0),
	DIPB => "0",
	DOPA => open,
	DOPB => MAC_RX_DOPB(0 downto 0),	
	ENA => '1',
	ENB => '1',
	WEA => MAC_RX_SAMPLE3_CLK,
	WEB => '0',
	SSRA => '0',
	SSRB => '0',
	CLKA => RX_CLKG,
	CLKB => CLK,
	ADDRA => MAC_RX_WPTR,
	ADDRB => MAC_RX_RPTR,
	DOA => open,
	DOB => MAC_RXD4
);


-- CLK zone. Reclock WPTR
MAC_RX_WPTR_002: process(ASYNC_RESET, CLK)
begin
	if(ASYNC_RESET = '1') then
		MAC_RX_WPTR_D2 <= (others => '0');
		MAC_RX_WPTR_D3 <= (others => '0');
		MAC_RX_WPTR_STABLE_D <= '0';
	elsif rising_edge(CLK) then
		MAC_RX_WPTR_STABLE_D <= MAC_RX_WPTR_STABLE;
		MAC_RX_WPTR_D2 <= MAC_RX_WPTR_D;
		
		if(MAC_RX_WPTR_STABLE_D = '1') then
			-- WPTR is stable. OK to resample with the RX_CLKG clock.
			MAC_RX_WPTR_D3 <= MAC_RX_WPTR_D2;
		end if;
	end if;
end process;

MAC_RX_BUF_SIZE <= MAC_RX_WPTR_D3 + not(MAC_RX_RPTR);
-- occupied tx buffer size

-- manage read pointer
MAC_RX_RPTR_001: process(ASYNC_RESET, CLK)
begin
	if(ASYNC_RESET = '1') then
		MAC_RX_RPTR <= (others => '1');
	elsif rising_edge(CLK) then
		MAC_RX_SAMPLE4_CLK <= MAC_RX_SAMPLE4_CLK_E;  -- it takes one CLK to read data from the RAMB
	
		if(SYNC_RESET = '1') then
			MAC_RX_RPTR <= (others => '1');
			MAC_RX_SAMPLE4_CLK_E <= '0';
			MAC_RX_SAMPLE4_CLK <= '0';
		elsif(MAC_RX_CTS = '1') and (MAC_RX_BUF_SIZE /= 0) then
			-- user requests data and the buffer is not empty
			MAC_RX_RPTR <= MAC_RX_RPTR + 1;
			MAC_RX_SAMPLE4_CLK_E <= '1';
		else
			MAC_RX_SAMPLE4_CLK_E <= '0';
		end if;
	end if;
end process;

-- reconstruct an EOF aligned with the last output byte
EOF_GEN_001: process(ASYNC_RESET, CLK)
begin
	if(ASYNC_RESET = '1') then
		MAC_RX_EOF4 <= '0';
	elsif rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			MAC_RX_EOF4 <= '0';
		elsif(MAC_RX_SAMPLE4_CLK_E = '1') and  (MAC_RX_BUF_SIZE = 0)then
			MAC_RX_EOF4 <= '1';
		else
			MAC_RX_EOF4 <= '0';
		end if;
	end if;
end process;
-- alternate code (does not work when CRC32 is stripped)
-- MAC_RX_EOF4 <= MAC_RX_DOPB(0) and MAC_RX_SAMPLE4_CLK; -- reconstruct EOF pulse (1 CLK wide)

-- reconstruct a SOF
SOF_GEN_001: process(ASYNC_RESET, CLK)
begin
	if(ASYNC_RESET = '1') then
		MAC_RX_EOF4_FLAG <= '1';
	elsif rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			MAC_RX_EOF4_FLAG <= '1';
		elsif(MAC_RX_EOF4 = '1') then
			MAC_RX_EOF4_FLAG <= '1';
		elsif(MAC_RX_SAMPLE4_CLK = '1') then
			MAC_RX_EOF4_FLAG <= '0';
		end if;
	end if;
end process;

-- output to user
MAC_RX_DATA <= MAC_RXD4;
MAC_RX_DATA_VALID <= MAC_RX_SAMPLE4_CLK;
MAC_RX_EOF <= MAC_RX_EOF4;
MAC_RX_SOF <= MAC_RX_EOF4_FLAG and MAC_RX_SAMPLE4_CLK;

end Behavioral;

