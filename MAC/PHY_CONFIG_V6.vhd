-------------------------------------------------------------
--	Filename:  PHY_CONFIG_V5.VHD
--	Version: 2
--	Date last modified: 2-4-11
-- Inheritance: 	PHY_CONFIG.VHD, rev2 2-4-11
--
-- description:  Configures a PHY through a MDIO interface.
----------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

---- Uncomment the following library declaration if instantiating
---- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity PHY_CONFIG is
	generic (
		PHY_ADDR: std_logic_vector(4 downto 0)	-- PHY Address
	);
    Port ( 
		--// CLK, RESET
		SYNC_RESET: in std_logic;
		CLK: in std_logic;
		
		--// CONTROLS
		CONFIG_CHANGE: in std_logic;
			-- 1 CLK-wide pulse to activate any configuration change below.
			-- Not needed if the default values are acceptable.
		PHY_RESET: in std_logic; 
			-- 1 = PHY software reset, 0 = no reset
		SPEED: in std_logic_vector(1 downto 0);
			-- 00 = force 10 Mbps
			-- 01 = force 100 Mbps
			-- 10 = force 1000 Mbps
			-- 11 = auto-negotiation (default)
		DUPLEX: in std_logic;
			-- 1 = full-duplex (default), 0 = half-duplex
		TEST_MODE: in std_logic_vector(1 downto 0);
			-- 00 = normal mode (default)
			-- 01 = loopback mode
			-- 10 = remote loopback
			-- 11 = led test mode
		POWER_DOWN: in std_logic;
			-- software power down mode. 1 = enabled, 0 = disabled (default).
		CLK_SKEW: in std_logic_vector(15 downto 0);
			-- Register 260 RGMII clock and control pad skew

		--// MONITORING
		SREG_READ_START: in std_logic;
			-- 1 CLK wide pulse to start read transaction
			-- will be ignored if the previous transaction is yet to be completed.
		SREG_REGAD: in std_logic_vector(8 downto 0);	
			-- 32 register address space for the PHY 
			--  0 - 15 are standard PHY registers as per IEEE specification.
			-- 16 - 31 are vendor-specific registers
			-- 256+ are extended registers
		SREG_DATA : OUT std_logic_vector(15 downto 0);
			-- 16-bit status register. Read when SREG_SAMPLE_CLK = '1'
		SREG_SAMPLE_CLK: out std_logic;
			
		--// BASIC STATUS REPORT (status register 1)
		LINK_STATUS: out std_logic;  
			-- 0 = link down, 1 = link up
		--// serial interface. connect to PHY 
		MCLK: out std_logic;
		MDI: in std_logic;  -- MDIO input
		MDO: out std_logic;  -- MDIO output
		MDT: out std_logic  -- MDIO tri-state
		
);
end entity;

architecture Behavioral of PHY_CONFIG is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
	COMPONENT MII_MI_V6
	GENERIC (
		PHY_ADDR: std_logic_vector(4 downto 0)
	);	
	PORT(
		SYNC_RESET : IN std_logic;
		CLK : IN std_logic;
		MI_REGAD : IN std_logic_vector(4 downto 0);
		MI_TX_DATA : IN std_logic_vector(15 downto 0);
		MI_READ_START : IN std_logic;
		MI_WRITE_START : IN std_logic;    
		MDI: in std_logic;  -- MDIO input
		MDO: out std_logic;  -- MDIO output
		MDT: out std_logic;  -- MDIO tri-state
		MI_RX_DATA : OUT std_logic_vector(15 downto 0);
		MI_TRANSACTION_COMPLETE : OUT std_logic;
		MCLK : OUT std_logic
		);
	END COMPONENT;
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
signal STATE: std_logic_vector(3 downto 0) := "0000";
signal MI_WRITE_START: std_logic := '0';
signal MI_REGAD: std_logic_vector(4 downto 0) := "00000";
signal MI_TX_DATA: std_logic_vector(15 downto 0);
signal MI_READ_START: std_logic := '0';
signal MI_RX_DATA: std_logic_vector(15 downto 0);
signal MI_TRANSACTION_COMPLETE: std_logic;
signal PHY_RESET_D: std_logic;
signal SPEED_D: std_logic_vector(1 downto 0);
signal LOOPBACK_MODE: std_logic;
signal AUTONEG: std_logic;
signal POWER_DOWN_D: std_logic;
signal DUPLEX_D: std_logic;
signal REMOTE_LOOPBACK: std_logic;
signal LED_TEST_MODE: std_logic;

constant RGMII_INBAND_STATUS_EN: std_logic := '1'; -- enable in-band status reporting in RGMII
signal SREG_SAMPLE_CLK_local: std_logic := '0';
--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

---- save the configuration so that it does not change while the configuration is in progress
RECLOCK_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(STATE = 0) and (CONFIG_CHANGE = '1') then
			PHY_RESET_D <= PHY_RESET;
			SPEED_D <= SPEED;
			DUPLEX_D <= DUPLEX;
			POWER_DOWN_D <= POWER_DOWN;
			
			if(SPEED = "11") then
				AUTONEG <= '1';
			else
				AUTONEG <= '0';
			end if;
			
			case TEST_MODE is
				when "00" => 
					LOOPBACK_MODE <= '0';
					REMOTE_LOOPBACK <= '0';
					LED_TEST_MODE <= '0';
				when "01" => 
					LOOPBACK_MODE <= '1';
					REMOTE_LOOPBACK <= '0';
					LED_TEST_MODE <= '0';
				when "10" => 
					LOOPBACK_MODE <= '0';
					REMOTE_LOOPBACK <= '1';
					LED_TEST_MODE <= '0';
				when others => 
					LOOPBACK_MODE <= '0';
					REMOTE_LOOPBACK <= '0';
					LED_TEST_MODE <= '1';
			end case;
			
		end if;
	end if;
end process;
-- state machine
STATE_GEN: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			STATE <= (others => '0');
			MI_WRITE_START <= '0';
			MI_READ_START <= '0';

		-- WRITE ALL CONFIGURATION REGISTERS
		elsif(STATE = 0) and (CONFIG_CHANGE = '1') then
			-- triggers a PHY reconfiguration. await PHY MDIO availability
			STATE <= STATE + 1;

		elsif(STATE = 1) and (MI_TRANSACTION_COMPLETE = '1') then
			-- PHY is ready for next transaction.
			-- Register 0: basic control (applicable to all: GMII, MII, RGMII)
			STATE <= STATE + 1;
			MI_REGAD <= "00000";
			MI_TX_DATA(15 downto 8) <= PHY_RESET_D & LOOPBACK_MODE & SPEED_D(0) & AUTONEG & POWER_DOWN_D & "00" & DUPLEX_D;
			MI_TX_DATA(7 downto 0) <= "0" & SPEED_D(1) & "000000";
			MI_WRITE_START <= '1';
			
-- tested for Micrel KSZ90212RN -------
-- adjust as needed depending on the PHY 	(the extended registers vary depending on the manufacturer/model).		
		elsif(STATE = 2) and (MI_TRANSACTION_COMPLETE = '1') then 
			STATE <= (others => '0');
		-- READ ONE STATUS REGISTER	
		elsif(STATE = 0) and (SREG_READ_START = '1') and (SREG_REGAD(8) = '0') then
			-- triggers a PHY status read. await PHY MDIO availability
			STATE <= "1000";
		elsif(STATE = 8) and (MI_TRANSACTION_COMPLETE = '1') and (SREG_REGAD(8) = '0') then
			-- PHY is ready for next transaction.
			STATE <= STATE + 1;
			MI_REGAD <= SREG_REGAD(4 downto 0);  
			MI_READ_START <= '1';
		elsif(STATE = 9) and (MI_TRANSACTION_COMPLETE = '1') then
			-- we are done reading a status register! Going back to idle.
			STATE <= (others => '0');
			SREG_SAMPLE_CLK_local <= '1';


		-- READ ONE EXTENDED REGISTER	
		elsif(STATE = 0) and (SREG_READ_START = '1') and (SREG_REGAD(8) = '1') then
			-- Extended register (1/2)
			STATE <= "1000";
			MI_REGAD <= "01011";  
			MI_TX_DATA <= "0000000" & SREG_REGAD;  -- read extended register
			MI_WRITE_START <= '1';
		elsif(STATE = 8) and (MI_TRANSACTION_COMPLETE = '1') and (SREG_REGAD(8) = '1') then
			-- triggers a PHY status read. await PHY MDIO availability
			STATE <= STATE + 1;
			MI_REGAD <= "01101";  
			MI_READ_START <= '1';
		elsif(STATE = 9) and (MI_TRANSACTION_COMPLETE = '1') then
			-- we are done reading a status register! Going back to idle.
			STATE <= (others => '0');
			SREG_SAMPLE_CLK_local <= '1';
			
		-- PERIODIC READ BASIC STATUS: LINK
		elsif(STATE = 0) and (MI_TRANSACTION_COMPLETE = '1') then
			-- Register 1: basic status (applicable to all: GMII, MII, RGMII)
			STATE <= "1010";
			MI_REGAD <= "10001";  
			MI_READ_START <= '1';
		elsif(STATE = 10) and (MI_TRANSACTION_COMPLETE = '1') then
			-- we are done reading a status register! Going back to idle.
			STATE <= (others => '0');
--			LINK_STATUS <= MI_RX_DATA(2); commented by KED
		
		else
			MI_WRITE_START <= '0';
			MI_READ_START <= '0';
			SREG_SAMPLE_CLK_local <= '0';
		
		end if;
	end if;
end process;

LINK_STATUS <= '1';--; Added by KED

-- latch status register
SREGOUT_001:  process(CLK)
begin
	if rising_edge(CLK) then
		SREG_SAMPLE_CLK <= SREG_SAMPLE_CLK_local;
		
		if(SREG_SAMPLE_CLK_local = '1') then
			SREG_DATA <= MI_RX_DATA;
		end if;
	end if;
end process;

Inst_MII_MI: MII_MI_V6
GENERIC MAP(
	PHY_ADDR => PHY_ADDR
)
PORT MAP(
	SYNC_RESET => SYNC_RESET,
	CLK => CLK,
	MI_REGAD => MI_REGAD,
	MI_TX_DATA => MI_TX_DATA,
	MI_RX_DATA => MI_RX_DATA,
	MI_READ_START => MI_READ_START,
	MI_WRITE_START => MI_WRITE_START,
	MI_TRANSACTION_COMPLETE => MI_TRANSACTION_COMPLETE,
	MCLK => MCLK,
	MDI => MDI,
	MDO => MDO,
	MDT => MDT
);

end Behavioral;

