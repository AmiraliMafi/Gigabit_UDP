-------------------------------------------------------------
--	Filename:  CRC32_8b.VHD
--	Version: 1
--	Date last modified: 2-20-04
-- Inheritance: 	CRC16.VHD, 2-20-04
--
-- description:  CRC32 verification for incoming data packets. 
-- + CRC32 generation for outgoing data packets.  
-- Data is entered one byte at a time.
-- The CRC is computed iteratively. The Initial CRC32 value for the first message
-- byte is all 1's. The final CRC32 value when the message is error-free is the residue below.
-- Generator polynomial: x^32 + x^26 + x^23+ x^22+ x^16+ x^12+ x^11+ x^10+ x^8+ x^7+ x^5+ x^4+ x^2+ x + 1
-- as per 802.3 standard. 
-- The residue = 0xC704DD7B
--
-- Validated by comparison with outputlogic.com
---------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity CRC32_8B is
    port ( 
	 	--// Clocks Resets
		SYNC_RESET: in std_logic;
		CLK: in std_logic;	-- reference clock

		--// Inputs
		CRC32_IN: in std_logic_vector(31 downto 0);
			-- Initialize to all 1's for the first byte in the data packet 
			-- (or use the SYNC_RESET PRIOR to the first input byte).
			-- For subsequent bytes use the previous CRC32_OUT value, as the 
			-- CRC32 computation is iterative, byte by byte.
		DATA_IN: in std_logic_vector(7 downto 0);
			-- message from which the CRC32 is computed and/or checked. 
			-- Entered byte by byte. 
		SAMPLE_CLK_IN: in std_logic;
			-- 1 CLK wide pulse to indicate that DATA_IN and CRC32_IN are ready to be
 		   -- processed.

		--// Outputs
		CRC32_OUT: out std_logic_vector(31 downto 0);
			-- Computed CRC32. 
			-- Latency: 1 CLK after SAMPLE_CLK_IN.
			-- If all bits are received without error, the 32-bit residual at
			-- the receiver will be 0.
	  	CRC32_VALID: out std_logic
			-- '1' when computed CRC32 = 0. 
		   -- valid only once the entire data packet is read.
			-- Latency: 1 CLK after SAMPLE_CLK_IN.
			-- Stays until start (first byte) of next message.
			);
end entity;

architecture behavioral of CRC32_8B is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
signal CRC32_OUT_LOCAL: std_logic_vector(31 downto 0);
signal DATA0: std_logic_vector(7 downto 0);
-------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

-- IMPORTANT: the CRC computation below is designed for DATA_IN(0) transmitted first.
-- When re-using the code, please verify which bit is sent first into the CRC. Flip bit/byte order otherwise.

-- Flip input byte
--DATA0(7) <= DATA_IN(0);
--DATA0(6) <= DATA_IN(1);
--DATA0(5) <= DATA_IN(2);
--DATA0(4) <= DATA_IN(3);
--DATA0(3) <= DATA_IN(4);
--DATA0(2) <= DATA_IN(5);
--DATA0(1) <= DATA_IN(6);
--DATA0(0) <= DATA_IN(7);
DATA0 <= DATA_IN;


CRC_COMPUTE_001: process(CLK, DATA0, SAMPLE_CLK_IN) 
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			CRC32_OUT_LOCAL <= (others => '1');
		elsif(SAMPLE_CLK_IN = '1') then
			-- new incoming byte
			CRC32_OUT_LOCAL(0) <= 	DATA0(1) xor DATA0(7) xor 		
										CRC32_IN(24) xor CRC32_IN(30);

			CRC32_OUT_LOCAL(1) <= 	DATA0(0) xor DATA0(1) xor DATA0(6) xor DATA0(7) xor 
										CRC32_IN(24) xor CRC32_IN(25) xor CRC32_IN(30) xor CRC32_IN(31);

			CRC32_OUT_LOCAL(2) <= 	DATA0(0) xor DATA0(1) xor DATA0(5) xor DATA0(6) xor 
										DATA0(7) xor 			
										CRC32_IN(24) xor CRC32_IN(25) xor CRC32_IN(26) xor CRC32_IN(30) xor
										CRC32_IN(31);

			CRC32_OUT_LOCAL(3) <= 	DATA0(0) xor DATA0(4) xor DATA0(5) xor DATA0(6) xor 
										CRC32_IN(25) xor CRC32_IN(26) xor CRC32_IN(27) xor CRC32_IN(31);
			
			CRC32_OUT_LOCAL(4) <= 	DATA0(1) xor DATA0(3) xor DATA0(4) xor DATA0(5) xor 
										DATA0(7) xor 		
										CRC32_IN(24) xor CRC32_IN(26) xor CRC32_IN(27) xor CRC32_IN(28) xor
										CRC32_IN(30);

			CRC32_OUT_LOCAL(5) <= 	DATA0(0) xor DATA0(1) xor DATA0(2) xor DATA0(3) xor 
										DATA0(4) xor DATA0(6) xor DATA0(7) xor 			
										CRC32_IN(24) xor CRC32_IN(25) xor CRC32_IN(27) xor CRC32_IN(28) xor
										CRC32_IN(29) xor CRC32_IN(30) xor CRC32_IN(31);

			CRC32_OUT_LOCAL(6) <= 	DATA0(0) xor DATA0(1) xor DATA0(2) xor DATA0(3) xor 
										DATA0(5) xor DATA0(6) xor 			
										CRC32_IN(25) xor CRC32_IN(26) xor CRC32_IN(28) xor CRC32_IN(29) xor
										CRC32_IN(30) xor CRC32_IN(31);

			CRC32_OUT_LOCAL(7) <= 	DATA0(0) xor DATA0(2) xor DATA0(4) xor DATA0(5) xor 
										DATA0(7) xor 			
										CRC32_IN(24) xor CRC32_IN(26) xor CRC32_IN(27) xor CRC32_IN(29) xor
										CRC32_IN(31);

			CRC32_OUT_LOCAL(8) <= 	DATA0(3) xor DATA0(4) xor DATA0(6) xor DATA0(7) xor 
										CRC32_IN(0) xor CRC32_IN(24) xor CRC32_IN(25) xor CRC32_IN(27) xor
										CRC32_IN(28);

			CRC32_OUT_LOCAL(9) <= 	DATA0(2) xor DATA0(3) xor DATA0(5) xor DATA0(6) xor 
										CRC32_IN(1) xor CRC32_IN(25) xor CRC32_IN(26) xor CRC32_IN(28) xor
										CRC32_IN(29);

			CRC32_OUT_LOCAL(10) <= 	DATA0(2) xor DATA0(4) xor DATA0(5) xor DATA0(7) xor 
										CRC32_IN(2) xor CRC32_IN(24) xor CRC32_IN(26) xor CRC32_IN(27) xor
										CRC32_IN(29);

			CRC32_OUT_LOCAL(11) <= 	DATA0(3) xor DATA0(4) xor DATA0(6) xor DATA0(7) xor 
										CRC32_IN(3) xor CRC32_IN(24) xor CRC32_IN(25) xor CRC32_IN(27) xor
										CRC32_IN(28);

			CRC32_OUT_LOCAL(12) <= 	DATA0(1) xor DATA0(2) xor DATA0(3) xor DATA0(5) xor 
										DATA0(6) xor DATA0(7) xor 			
										CRC32_IN(4) xor CRC32_IN(24) xor CRC32_IN(25) xor CRC32_IN(26) xor
										CRC32_IN(28) xor CRC32_IN(29) xor CRC32_IN(30);

			CRC32_OUT_LOCAL(13) <= 	DATA0(0) xor DATA0(1) xor DATA0(2) xor DATA0(4) xor 
										DATA0(5) xor DATA0(6) xor 		
										CRC32_IN(5) xor CRC32_IN(25) xor CRC32_IN(26) xor CRC32_IN(27) xor
										CRC32_IN(29) xor CRC32_IN(30) xor CRC32_IN(31);

			CRC32_OUT_LOCAL(14) <= 	DATA0(0) xor DATA0(1) xor DATA0(3) xor DATA0(4) xor 
										DATA0(5) xor 			
										CRC32_IN(6) xor CRC32_IN(26) xor CRC32_IN(27) xor CRC32_IN(28) xor
										CRC32_IN(30) xor CRC32_IN(31);

			CRC32_OUT_LOCAL(15) <= 	DATA0(0) xor DATA0(2) xor DATA0(3) xor DATA0(4) xor 
										CRC32_IN(7) xor CRC32_IN(27) xor CRC32_IN(28) xor CRC32_IN(29) xor
										CRC32_IN(31);

			CRC32_OUT_LOCAL(16) <= 	DATA0(2) xor DATA0(3) xor DATA0(7) xor 
										CRC32_IN(8) xor CRC32_IN(24) xor CRC32_IN(28) xor CRC32_IN(29);

			CRC32_OUT_LOCAL(17) <= 	DATA0(1) xor DATA0(2) xor DATA0(6) xor 		
										CRC32_IN(9) xor CRC32_IN(25) xor CRC32_IN(29) xor CRC32_IN(30);

			CRC32_OUT_LOCAL(18) <= 	DATA0(0) xor DATA0(1) xor DATA0(5) xor 			
										CRC32_IN(10) xor CRC32_IN(26) xor CRC32_IN(30) xor CRC32_IN(31);

			CRC32_OUT_LOCAL(19) <= 	DATA0(0) xor DATA0(4) xor 	
										CRC32_IN(11) xor CRC32_IN(27) xor CRC32_IN(31);

			CRC32_OUT_LOCAL(20) <= 	DATA0(3) xor 		
										CRC32_IN(12) xor CRC32_IN(28);

			CRC32_OUT_LOCAL(21) <= 	DATA0(2) xor 
										CRC32_IN(13) xor CRC32_IN(29);

			CRC32_OUT_LOCAL(22) <= 	DATA0(7) xor 	
										CRC32_IN(14) xor CRC32_IN(24);

			CRC32_OUT_LOCAL(23) <= 	DATA0(1) xor DATA0(6) xor DATA0(7) xor 
										CRC32_IN(15) xor CRC32_IN(24) xor CRC32_IN(25) xor CRC32_IN(30);

			CRC32_OUT_LOCAL(24) <= 	DATA0(0) xor DATA0(5) xor DATA0(6) xor 		
										CRC32_IN(16) xor CRC32_IN(25) xor CRC32_IN(26) xor CRC32_IN(31);

			CRC32_OUT_LOCAL(25) <= 	DATA0(4) xor DATA0(5) xor 
										CRC32_IN(17) xor CRC32_IN(26) xor CRC32_IN(27);

			CRC32_OUT_LOCAL(26) <= 	DATA0(1) xor DATA0(3) xor DATA0(4) xor DATA0(7) xor 
										CRC32_IN(18) xor CRC32_IN(24) xor CRC32_IN(27) xor CRC32_IN(28) xor
										CRC32_IN(30);

			CRC32_OUT_LOCAL(27) <= 	DATA0(0) xor DATA0(2) xor DATA0(3) xor DATA0(6) xor 
										CRC32_IN(19) xor CRC32_IN(25) xor CRC32_IN(28) xor CRC32_IN(29) xor
										CRC32_IN(31);

			CRC32_OUT_LOCAL(28) <= 	DATA0(1) xor DATA0(2) xor DATA0(5) xor 	
										CRC32_IN(20) xor CRC32_IN(26) xor CRC32_IN(29) xor CRC32_IN(30);

			CRC32_OUT_LOCAL(29) <= 	DATA0(0) xor DATA0(1) xor DATA0(4) xor 			
										CRC32_IN(21) xor CRC32_IN(27) xor CRC32_IN(30) xor CRC32_IN(31);

			CRC32_OUT_LOCAL(30) <= 	DATA0(0) xor DATA0(3) xor 		
										CRC32_IN(22) xor CRC32_IN(28) xor CRC32_IN(31);

			CRC32_OUT_LOCAL(31) <= 	DATA0(2) xor 	
										CRC32_IN(23) xor CRC32_IN(29);

		end if;
	end if;
end process;

CRC32_OUT <= CRC32_OUT_LOCAL;

CRC32_VALID <= '1' when (CRC32_OUT_LOCAL = x"C704DD7B") else '0';

end behavioral;