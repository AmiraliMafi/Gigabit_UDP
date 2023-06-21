----------------------------------------------
-- MSS copyright 2001-2005
-- Filename: LFSR11C.VHD
-- Inheritance: LFSR11.VHD rev 4 and  LFSR11B.VHD rev 4
-- Edit date: 9/28/05
-- Revision: 1
-- Description: 
--		pseudo random bit generation. based on 11-bit linear feedback
-- 	shift register. A synchronous reset is provided to reset
--		the PN sequence at frame boundaries.
--		Includes seed initialization.
---------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity LFSR11C is
  port (
	ASYNC_RESET: in std_logic;
		-- asynchronous reset, active high
	CLK: in  std_logic;   
		-- clock synchronous
	BIT_CLK_REQ: in std_logic;
		-- request for output bit, 
		-- read output bit at rising_edge of CLK and BIT_CLK_REQ_D = '1'
	SYNC_RESET: in std_logic;
		-- synchronous reset for linear feedback shift register.
		-- 1 CLK wide pulse aligned with BIT_CLK_REQ.
	SEED: in std_logic_vector(10 downto 0);
		-- linear feedback shift register initialization at reset 
		-- (asynchronous and synchronous).

	LFSR_BIT: out std_logic;
		-- Linear feedback shift register output. Read at rising edge of CLK
		-- when BIT_CLK_OUT = '1'
	BIT_CLK_OUT: out std_logic;
		-- one CLK wide pulse indicating that the LFSR_BIT is ready. 
		-- Latency w.r.t. BIT_CLK_REQ is one CLK. 
	SOF_OUT: out std_logic;
		-- one CLK wide pulse indicating start of frame
		-- (i.e. '1' when LFSR register matches the SEED). 
		-- aligned with BIT_CLK_OUT.
	LFSR_REG_OUT: out std_logic_vector(10 downto 0)
		
    );
end entity;

architecture behavior of LFSR11C is
-----------------------------------------------------------------
-- SIGNALS
-----------------------------------------------------------------
signal LFSR_REG     : std_logic_vector(10 downto 0);

-----------------------------------------------------------------
-- IMPLEMENTATION
-----------------------------------------------------------------
begin

-- linear feedback shift register
LSFR_GEN: process(ASYNC_RESET, CLK, SEED)
begin
if (ASYNC_RESET = '1') then
	LFSR_REG     <= SEED;
   LFSR_BIT <= '0';
	SOF_OUT <= '0';
elsif rising_edge(CLK) then
	BIT_CLK_OUT <= BIT_CLK_REQ;

	if(SYNC_RESET = '1') then
		-- synchronous reset
		LFSR_REG     <= SEED;
	   LFSR_BIT <= '0';
		SOF_OUT <= '0';
	elsif(BIT_CLK_REQ = '1') then
		-- prepare next bit; used Xilinx XAP 052 Table 3 for taps
		LFSR_REG(10 downto 1) <= LFSR_REG(9 downto 0); 
		LFSR_REG(0)  <= not (LFSR_REG(10) xor LFSR_REG(8));
		LFSR_BIT <= LFSR_REG(10);
		if(LFSR_REG = SEED) then
			SOF_OUT <= '1';
	  	else 
			SOF_OUT <= '0';
	 	end if;
	else
		-- sample clocks are one CLK wide pulses.
		SOF_OUT <= '0';
	end if;
end if;
end process;

LFSR_REG_OUT <= LFSR_REG;
    
end behavior;

