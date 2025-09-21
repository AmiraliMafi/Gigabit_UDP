--****************************************************************************************
-- Engineer:				       Amir Ali Mafi
-- Module Name:   		           Reset_Gen
-- Project Name:                   Ethernet_1G
-- Version:       		           v0.0
-- Difference with Old Version:
-- Target Devices:		           XC6VLX240t-1FF1156
-- Code Status:   		           Final 
-- Operation Clock:		           Input:100MHz,Output:100MHz
-- In/Out Rate:                    --
-- Block RAM Usage:
-- Slice Usage: 
-- Block Technical Info:
-- Additional Comments: 

--****************************************************************************************
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;

--library work;
--use work.signal_Package.all;

entity reset_gen is
port
(
    i_clk              : in std_logic;
    i_reset            : in std_logic;
    o_global_reset     : out std_logic:='1';
    o_vector_reset     : out std_logic:='1';
    o_phy_rstn         : out std_logic:='1'
);
end reset_gen;

architecture Behavioral of reset_gen is

signal   s_cnt_rst     : std_logic_vector(31 downto 0):=(others=>'0');
signal   s_reset       :  std_logic:='1';

begin


--================ Generate Reset's =======================
p_reset_generator: process(i_clk)
	begin
	if rising_edge(i_clk) then
	   if(s_reset='1') then
		    s_cnt_rst <= (others=>'0');
			o_global_reset    <= '1';
		    o_phy_rstn        <= '1';
		    s_reset           <=  '0';
		else	
		   s_cnt_rst          <= s_cnt_rst+1;
		   o_global_reset     <= '1';
		   o_phy_rstn         <= '1';
		   if (s_cnt_rst>=8000000) then   --8ms
		       s_cnt_rst        <= x"007A1200"; --8000000
		       --s_cnt_rst        <= x"00000320"; 
			   o_global_reset   <= '0';	
           elsif (s_cnt_rst>7000000) then --40ms
			    o_phy_rstn       <= '1';				 
		   elsif (s_cnt_rst>2000000) then --16ms
			    o_phy_rstn       <= '0';
			     o_vector_reset  <= '0';  
		   end if;	 

       end if;
	  end if;	 
	end process p_reset_generator;
--==========================================================

end Behavioral;

