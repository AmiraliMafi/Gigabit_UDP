-------------------------------------------------------------
--	Filename:  RESET_TIMER.VHD
--	Version: 1
--	Date last modified: 1-28-11
-- Inheritance: 	n/a
--
-- description:  
-- 1. Generate a long (>10ms) negative RESET_N pulse at power up or after a RESET_START trigger.
-- The timer to define the length of the RESET_N pulse is set at the time of HDL synthesis 
-- (see the constants within)
-- 2. Generate a short INITIAL_CONFIG_PULSE, 50ms after the RESET_N deassertion
-- to start configuring the PHY over the MDIO interface.
-- Beware: as the PHY may turn off its 125 MHz while RESET_N is being asserted, one should
-- not rely on the availability of this 125 MHz clock to generate RESET_N (circular logic).
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity RESET_TIMER is
	generic (
		CLK_FREQUENCY: integer := 120
			-- CLK frequency in MHz. Needed to compute actual delays.
	);
    Port ( 
		--// CLK
	 CLK: in std_logic;
		-- GLOBAL CLOCK, always available, even during PHY reset. Used as time reference.
	 
	 RESET_START: in std_logic;
		-- 1-CLK pulse trigger to reset PHY IC and set the strapping options.
		-- This trigger is optional. This component will automatically generate a RESET_N 
		-- long negative pulse at power up.  Synchronous with CLK. 
	 RESET_COMPLETE: out std_logic;
		-- '1' to indicate the end of this reset transaction. '1' while transaction is in progress.
		-- synchronous with CLK

	 --// OUTPUTS
	 INITIAL_CONFIG_PULSE: out std_logic;
		-- 1-clk pulse to trigger the first-time PHY configuration over the MDIO interface.
		-- synchronous with CLK
	 
	 RESET_N: out std_logic
		-- PHY INTERFACE. long negative pulse at power up or after a RESET_START.
		-- hardware pin configurations are strapped-in at the de-assertion (rising edge)
		-- of RESET_N. > 10ms long.
		-- synchronous with CLK

	 
);
end entity;

architecture Behavioral of RESET_TIMER is
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
signal STATE: integer range 0 to 3 := 0;
signal TIMER1: std_logic_vector(23 downto 0) := x"000000";
constant TIMER1_VAL: integer := (CLK_FREQUENCY * 10000) -1;
	-- the objective is to generate a 10ms min RESET_N pulse. Adjust TIMER1_VAL as needed.
	-- Example: CLK = 125 MHz clock. The resulting TIMER1_VAL is 10E-2 * 125E6  -1
signal TIMER2: std_logic_vector(23 downto 0) := x"000000";
constant TIMER2_VAL: integer := (CLK_FREQUENCY * 50000) -1;
	-- Example: 100uS at 125MHz = 12499

signal RESET_STARTED: std_logic := '0';
signal POWER_UP: std_logic := '0';
	

--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

RESET_N_GEN_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(RESET_START = '1') or (POWER_UP = '0') then
			-- initialize timer upon powerup or RESET_START
			POWER_UP <= '1'; 
			INITIAL_CONFIG_PULSE <= '0';
			TIMER1 <= (others => '0');
			TIMER2 <= (others => '0');
			STATE <= 1;
		elsif(STATE = 1) then
			if (TIMER1 < TIMER1_VAL) then
				-- count until TIMER1_VAL (timer expired)
				TIMER1 <= TIMER1 + 1;
			else
				-- timer1 expired
				STATE <= 2;
			end if;
		elsif(STATE = 2) then
			if (TIMER2 < TIMER2_VAL) then
				-- count until TIMER2_VAL (timer expired)
				TIMER2 <= TIMER2 + 1;  
			else
				-- timer2 expired
				STATE <= 3;
				INITIAL_CONFIG_PULSE <= '1';
			end if;
		elsif(STATE = 3) then
			INITIAL_CONFIG_PULSE <= '0';
		end if;
	end if;
end process;

RESET_COMPLETE <= '1' when (STATE = 3) else '0';

	
--// OUTPUTS ----------------------
RESET_N <= '0' when (STATE = 0) or (STATE = 1) else '1';  -- active low reset

end Behavioral;

