library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.STD_LOGIC_ARITH.ALL;
--use IEEE.STD_LOGIC_UNSIGNED.ALL;

package signal_Package is


type array_8Xi_KED is array (0 to 50) of std_logic_vector (7 downto 0);
type Arr_128X8_KED is array (0 to 7) of std_logic_vector(127 downto 0); 
type RandomArr_type is array (0 to 255) of std_logic_vector(127 downto 0); 
type TagArr_type is array (0 to 1023) of std_logic_vector(1 downto 0); 

end signal_Package;

package body signal_Package is

 
end signal_Package;
