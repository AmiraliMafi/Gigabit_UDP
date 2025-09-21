
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;
use IEEE.STD_LOGIC_ARITH.ALL;
library unisim;
use unisim.vcomponents.all;




entity GIGABYTE_LAN_Interface is
generic (
			LAN_Lable                          : string:="LAN_0"; 
			IDELAY_GRP_Str                     : string:="Grp_KED";
			IDELAY_GRP_Str_s               		: string:="<Grp_KED_tx>"; 
			c_udp_tx_src_ip                    : std_logic_vector (31 downto 0):= x"AC1E0101"--x"C0A86403";      --172.30.01.01(FPGA IP Adress)
            -- c_udp_tx_src_port                  : std_logic_vector (15 downto 0):= x"0401";          --UDP Src Port(Value For This Constant is not Importanat)										
            -- c_udp_tx_dst_port                  : std_logic_vector (15 downto 0):= x"0FF5"          --UDP Src Port(Value For This Constant is not Importanat);
                       										
			);
port(
		clk_125                 : in std_logic;
		clk_200                 : in std_logic;
		
		---------------------------------------------------------------
		o_phy_rstn             : out STD_LOGIC;--Reset to PHY
		rx_mac_aclk            : out  STD_LOGIC ;
        i_reset                : in  STD_LOGIC:='0' ;
        gmii_rx_clk            : in  STD_LOGIC ;
        gmii_tx_clk            : out  STD_LOGIC ;
	-- o_Rgmii_txc             : out std_logic;
    -- o_Rgmii_tx_ctrl         : out std_logic;
	-- o_Rgmii_txd             : out std_logic_vector(4 downto 0);

    -- i_Rgmii_rxc             : in  std_logic;
    -- i_Rgmii_rx_ctrl         : in  std_logic;
    -- i_Rgmii_rxd             : in  std_logic_vector(4 downto 0);
	
		o_gmii_tx_en            : out std_logic;
		o_gmii_tx_er         	: out std_logic;
		o_gmii_txd             	: out std_logic_vector(7 downto 0);

		i_gmii_rx_dv            : in  std_logic;
		i_gmii_rx_er         	: in  std_logic;
		i_gmii_rxd             : in  std_logic_vector(7 downto 0);
		
		o_mac_tx_tready        : out std_logic;
		
		i_udp_rx_src_ip        : in std_logic_vector(31 downto 0);
		o_udp_rx_src_ip        : out std_logic_vector(31 downto 0);
		

		o_mdc                  : out std_logic;
		io_mdio                : inout std_logic;
        ---------------------------------------------------------
        --------------- user ------------------------------------
        o_udp_rx_err_out	      : out std_logic_vector(3 downto 0);
        i_fragment_len            : in    std_logic_vector(16 - 1 downto 0):=x"4000";
        LAN_clk                   : out    std_logic;
        LAN_dout_rdy              : out    std_logic;
        LAN_dout_last             : out    std_logic;
        LAN_dout                  : out    std_logic_vector(8 - 1 downto 0);
        LAN_din_rdy               : in    std_logic;
        LAN_din_last              : in    std_logic;
        LAN_din                   : in    std_logic_vector(8 - 1 downto 0)


);
end GIGABYTE_LAN_Interface;

architecture Behavioral of GIGABYTE_LAN_Interface is



--=========================== Reset Generator ==========================================
component reset_gen 
port
(
    i_clk              : in std_logic;
    i_reset            : in std_logic;
    o_global_reset     : out std_logic;
    o_vector_reset     : out std_logic;
    o_phy_rstn         : out std_logic
	 
);
end component;
--======================================================================================



--======================================================================================
component sync_fifo2 
port
(
    rst         : IN STD_LOGIC;
    wr_clk      : IN STD_LOGIC; --Maximum 125MHz
    wr_en       : IN STD_LOGIC;   
    din         : IN STD_LOGIC_VECTOR(10-1 DOWNTO 0); --(last & data)
    
	rd_clk      : IN STD_LOGIC; --Tx_Clk(125MHz)
    rd_en       : IN STD_LOGIC;
    dout        : OUT STD_LOGIC_VECTOR(10-1 DOWNTO 0);
	valid       : OUT STD_LOGIC;
    full        : OUT STD_LOGIC;
    empty       : OUT STD_LOGIC
    
);  
end component;
--======================================================================================


--================================= Constant ===========================================
--Generate Block Conditional Constants
constant c_GENERATE_PING_MODULE             : boolean  := true;                                  --if Ping Block is not Used,Value is False
constant c_GENERATE_ARP_MODULE              : boolean  := true;                                  --if ARP  Block is not Used,Value is False
constant c_DEFAULT_DST_MAC_ADDR             : std_logic_vector (47 downto 0) := x"F46D04962225"; --if ARP Block is not Used,Copy PC MAC Address to This Value 	


--Application Layer Data Length
constant c_PACKET_LENGTH                    : std_logic_vector (15 downto 0):= x"05c0";          --1472 (Maximum Application Layer Packet Length)
--constant c_udp_tx_src_ip                    : std_logic_vector (31 downto 0):= x"AC1E0101";--x"C0A86403";      --172.30.01.01(FPGA IP Adress)
--constant c_udp_tx_src_port                  : std_logic_vector (15 downto 0):= x"0401";          --UDP Src Port(Value For This Constant is not Importanat)
constant c_udp_tx_dst_ip                    : std_logic_vector (31 downto 0):= x"AC1E0103";--x"C0A86402";      --172.30.01.03(PC IP Address)
constant c_udp_tx_protocol                  : std_logic_vector (7 downto 0) := x"11";            --UDP Protocol
constant c_udp_tx_src_mac                   : std_logic_vector (47 downto 0):= x"112233445566";  --FPGA MAC Address
constant c_udp_tx_checksum                  : std_logic_vector (15 downto 0):= x"0000";          --UDP Checksum(Value For This Constant is not Importanat)
--constant c_udp_tx_dst_port                  : std_logic_vector (15 downto 0):= x"0FF5";          --UDP Dst Port(Value For This Constant is not Importanat)

--ARP Constants
constant c_TIME_OUT_LOOKUP_TABLE_ARP        : std_logic_vector (31 downto 0) := x"9502F900";     --20S(Value/125MHz = 20 )	
constant c_TIME_OUT_WAIT_FOR_ARP_REPLY      : std_logic_vector (31 downto 0) := x"07735940";     --1S	(Value/125MHz = 1 )	
constant c_RE_SEND_ARP_REQUEST              : std_logic_vector (3 downto 0)  := x"A";            --10	
       	

--IP Constants
constant c_IP_TTL                           : std_logic_vector (7 downto 0)  := x"80";           -- IP Packet Time to live
constant c_IP_BC_ADDR                       : std_logic_vector (31 downto 0) := x"ffffffff";     -- Broadcast IP  Address
constant c_MAC_BC_ADDR                      : std_logic_vector (47 downto 0) := x"ffffffffffff"; -- Broadcast
--========================================================================================



--============================== Signals =================================================
signal  s_Reset_tx_for_eth 	     : std_logic:='0';
signal  s_Reset_rx_for_eth 	     : std_logic:='0';
signal  s_Reset_tx         	     : std_logic:='0';
signal  s_Reset_rx         	     : std_logic:='0';
signal  reset_reg         	     : std_logic_vector(9 downto 0):=(others=>'0');


signal  s_dout                   : std_logic_vector(7 downto 0):=(others=>'0');
signal  s_dout_valid             : std_logic:='0';
signal  s_dout_last              : std_logic:='0';

signal  s_dout1                  : std_logic_vector(7 downto 0):=(others=>'0');
signal  s_dout_valid1            : std_logic:='0';
signal  s_dout_last1             : std_logic:='0';


signal  s_udp_rx_sigs            : std_logic_vector(10-1 downto 0);
signal  s_udp_sigs               : std_logic_vector(10-1 downto 0);
signal  s_udp_sigs_valid         : std_logic:='0';

signal  s_sync_fifo_empty        : std_logic:='1';
signal  s_not_sync_fifo_empty    : std_logic:='0';

signal  s_udp_data_in            : std_logic_vector(8-1 downto 0):=(others=>'0');
signal  s_udp_valid_in           : std_logic:='0';
signal  s_udp_last_in            : std_logic:='0';
signal  s_udp_last_in_r          : std_logic:='0';

signal  s_udp_rx_dout_last_reset : STD_LOGIC:='0';
signal  s_udp_rx_dout_rdy_r  	 : std_logic:='0';
signal  internal_rst			 : std_logic;
signal  vector_rst			     : std_logic;

signal  s_udp_tx_data_len        : std_logic_vector (15 downto 0):= c_PACKET_LENGTH;  --1472 (Maximum Application Layer Packet Length)
signal 	s_udp_tx_start           : std_logic:='0';
signal 	s_udp_tx_ready           : std_logic;
signal  s_udp_tx_din	         : std_logic_vector(7 downto 0);

signal 	s_udp_rx_dout            : std_logic_vector(7 downto 0);
signal 	s_udp_rx_dout_rdy        : std_logic;
signal 	s_udp_rx_dout_last       : std_logic;
	
signal 	s_udp_rx_src_ip          : std_logic_vector(31 downto 0);
signal  s_udp_rx_src_port        : std_logic_vector(15 downto 0);
signal  s_udp_rx_dst_port        : std_logic_vector(15 downto 0);
signal  s_udp_rx_data_len        : std_logic_vector(15 downto 0);	
signal 	s_udp_rx_err_out_top     : std_logic_vector(3 downto 0);
signal 	s_udp_tx_err_out_top     : std_logic_vector(3 downto 0);
signal 	s_arp_rx_err_out_top     : std_logic_vector(3 downto 0);
signal  s_ip_rx_dst_ip_top       : std_logic_vector(31 downto 0);
signal  s_ip_rx_err_out_top      : std_logic_vector (3 downto 0);
signal  s_ip_tx_err_out_top      : std_logic_vector (3 downto 0);
signal  s_arp_addr_valid         : std_logic:='0';


signal  s_rx_clk_out             : std_logic;
signal  s_tx_clk_out             : std_logic;

signal  s_tx_fragmantation      : std_logic_vector (15 downto 0):=x"4000";




 
--========================================================================================

begin

o_mdc         <= '0';              
io_mdio       <= '0';   


o_udp_rx_err_out    <=s_udp_rx_err_out_top;




inst_reset_gen: reset_gen 
port map
(
    i_clk                     => clk_125,
    i_reset                   => i_reset,    
    o_global_reset            => internal_rst,
    o_vector_reset            => vector_rst,
    o_phy_rstn                => o_phy_rstn 
);

--==========================================================================
s_Reset_tx_for_eth <= internal_rst or s_Reset_tx;
s_Reset_rx_for_eth <= internal_rst or s_Reset_rx;




--============================ Ethernet_1g =================================
inst_Ethernet_1g: entity work.Ethernet_1g
generic map(
		 LAN_Lable                      => LAN_Lable,
		 IDELAY_GRP_Str                 => IDELAY_GRP_Str,
		 IDELAY_GRP_Str_s               => IDELAY_GRP_Str_s,
		 g_TIME_OUT_LOOKUP_TABLE_ARP    => c_TIME_OUT_LOOKUP_TABLE_ARP,											
		 g_TIME_OUT_WAIT_FOR_ARP_REPLY	=> c_TIME_OUT_WAIT_FOR_ARP_REPLY,				
		 g_RE_SEND_ARP_REQUEST			=> c_RE_SEND_ARP_REQUEST,
         g_GENERATE_PING_MODULE         => c_GENERATE_PING_MODULE,
         g_GENERATE_ARP_MODULE          => c_GENERATE_ARP_MODULE,
         g_DEFAULT_DST_MAC_ADDR         => c_DEFAULT_DST_MAC_ADDR
           		
			)
port map
(
	
	i_clk_125              => clk_125,      --125MHz
	refclk                 => clk_200,   --200MHz
	rx_mac_aclk            =>  rx_mac_aclk ,  
    gmii_rx_clk            =>  gmii_rx_clk ,
    gmii_tx_clk            =>  gmii_tx_clk ,
	
	i_global_reset         => internal_rst, --Active High
	i_vector_reset         => vector_rst, --Active High
	i_Reset_tx             => s_Reset_tx_for_eth,
	i_Reset_rx             => s_Reset_rx_for_eth,
	o_tx_clk_out           => open,   --125MHz
	o_rx_clk_out           => s_rx_clk_out,   --125MHz

	--================= UDP ============================
	-- UDP & IP Tx header
	i_udp_tx_src_ip         => c_udp_tx_src_ip,  
	i_udp_tx_dst_ip         => i_udp_rx_src_ip,--c_udp_tx_dst_ip,  
	i_udp_tx_data_len       => s_udp_tx_data_len,
	i_udp_tx_protocol       => c_udp_tx_protocol,
	i_udp_tx_src_mac        => c_udp_tx_src_mac,
	i_udp_tx_checksum       => c_udp_tx_checksum,
	i_udp_tx_src_port       => s_udp_rx_dst_port,--c_udp_tx_src_port,
	i_udp_tx_dst_port       => s_udp_rx_src_port,--c_udp_tx_dst_port,--
	i_ip_tx_fragmantation   => s_tx_fragmantation,    
    i_fragment_len          => i_fragment_len,                    
	-- UDP TX Inpus         
	i_udp_tx_start          => s_udp_tx_start,
	o_udp_tx_ready          => s_udp_tx_ready,
	o_mac_tx_tready          => open,--o_mac_tx_tready,--
	i_udp_tx_din	        => s_udp_tx_din,	

	-- UDP RX Outputs
	o_udp_rx_dout           => s_udp_rx_dout,     
	o_udp_rx_dout_rdy       => s_udp_rx_dout_rdy, 
	o_udp_rx_dout_last      => s_udp_rx_dout_last,
	                        
	-- UDP RX Status Outp   
	o_udp_rx_src_ip         => o_udp_rx_src_ip,  
	o_udp_rx_src_port       => s_udp_rx_src_port,
	o_udp_rx_dst_port       => s_udp_rx_dst_port,
	o_udp_rx_data_len       => s_udp_rx_data_len,
	o_udp_rx_err_out	    => s_udp_rx_err_out_top,
	o_udp_tx_err_out        => s_udp_tx_err_out_top,
	o_arp_rx_err_out        => s_arp_rx_err_out_top,
--	o_ip_rx_fragmantation   => open,--o_ip_rx_fragmantation,
	o_arp_addr_valid        => s_arp_addr_valid,
    -- IP Status
    o_ip_rx_dst_ip          => s_ip_rx_dst_ip_top, 
    o_ip_rx_err_out         => s_ip_rx_err_out_top,
    o_ip_tx_err_out         => s_ip_tx_err_out_top,
	

	--=============== PHY ==========================
	-- o_Rgmii_txc             => o_Rgmii_txc,
    -- o_Rgmii_tx_ctrl         => o_Rgmii_tx_ctrl,
    -- o_Rgmii_txd             => o_Rgmii_txd,

    -- i_Rgmii_rxc             => i_Rgmii_rxc,
    -- i_Rgmii_rx_ctrl         => i_Rgmii_rx_ctrl,
    -- i_Rgmii_rxd             => i_Rgmii_rxd, 
	
	o_gmii_tx_en  			=>	o_gmii_tx_en  ,  
	o_gmii_tx_er            =>	o_gmii_tx_er  , 
	o_gmii_txd              =>	o_gmii_txd    , 
	
	i_gmii_rx_dv            =>	i_gmii_rx_dv  , 
	i_gmii_rx_er            =>	i_gmii_rx_er  , 
	i_gmii_rxd              =>	i_gmii_rxd    , 
	       
	 i_gmii_crs             => '0',    
    i_gmii_col              => '0'
); 


--=================================================




----================================================================================
----process(s_rx_clk_out)
----begin
----if rising_edge(s_rx_clk_out) then
----    s_udp_rx_dout_last_reset <= s_udp_rx_dout_last;
----	if (s_udp_rx_dout_last_reset = '1') then
----	    reset_reg <= (others=>'1');
----	else
----       reset_reg <= reset_reg(8 downto 0) & '0';
----    end if;
----end if;
----end process;	

----s_Reset_rx <= reset_reg(9);	
----================================================================================




----========================== Recieved UDP Data =================================== 
process(s_rx_clk_out)
begin
if rising_edge(s_rx_clk_out) then  
   s_udp_rx_dout_rdy_r <= s_udp_rx_dout_rdy;
   s_udp_rx_sigs       <= s_udp_rx_dout_last & s_udp_rx_dout_rdy & s_udp_rx_dout;
end if;
end process;	
	

  
inst_sync_fifo:  sync_fifo2 
port map
(
    rst         => '0',
    wr_clk      => s_rx_clk_out,
    wr_en       => s_udp_rx_dout_rdy_r,
    din         => s_udp_rx_sigs,
    
	rd_clk      => clk_125,
    rd_en       => s_not_sync_fifo_empty,
    empty       => s_sync_fifo_empty,
    dout        => s_udp_sigs,
    valid       => s_udp_sigs_valid,
    full        => open
    
    
);

process(clk_125)
begin
if rising_edge(clk_125) then
   s_not_sync_fifo_empty <= not(s_sync_fifo_empty);
	
	if (s_udp_sigs_valid = '1') then
	    s_udp_data_in    <= s_udp_sigs(7 downto 0);
        s_udp_valid_in   <= s_udp_sigs(8);
        s_udp_last_in    <= s_udp_sigs(9);
	else	 
	     s_udp_data_in    <= (others=>'0');
         s_udp_valid_in   <= '0';
         s_udp_last_in    <= '0';
	end if;	 
	    
end if;
end process;

----==================================================================================


	--======================= ping_pong fifo ==========================
	inst_ping_pong_fifo2: entity work.ping_pong_fifo2_KED
		generic map(
			g_PACKET_LENGTH			=> c_PACKET_LENGTH)
		port map (
			i_clk           		=> clk_125,
			i_rst           		=> internal_rst,


		 -- i_din         			=> s_udp_data_in,
		 -- i_din_valid   			=> s_udp_valid_in,
		 -- i_din_last    			=> s_udp_last_in,

			i_din         			=> LAN_din,
			i_din_valid   			=> LAN_din_rdy,
			i_din_last    			=> LAN_din_last,


			--to UDP
			i_rd_en       			=> s_udp_tx_ready,
			o_dout        			=> s_udp_tx_din,
			o_start_out   			=> s_udp_tx_start,
			o_dout_len   			=> s_udp_tx_data_len,
			o_fragment              => s_tx_fragmantation,

			fifo_ready         		=> o_mac_tx_tready,--open,--
			full         			=> open,
			o_wr_cnta    			=> open,
			o_wr_cntb    			=> open);


	LAN_clk        <= clk_125;
	LAN_dout_rdy   <= s_udp_valid_in;
	LAN_dout_last  <= s_udp_last_in;
	LAN_dout       <= s_udp_data_in;

--======================= LAN TX Send Data ==========================


end Behavioral;

