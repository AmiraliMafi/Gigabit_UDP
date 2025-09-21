--****************************************************************************************
-- Company:					      
-- Engineer:				       AmirAli Mafi
-- Create Date:			           1393/01/18
-- Module Name:   		           Ethernet_1G
-- Project Name:                   Ethernet_1G
-- Version:       		           v0.0
-- Difference with Old Version:
-- Target Devices:		           XC6VLX240t-1FF1156
-- Code Status:   		           Final 
-- Operation Clock:		           Input:125MHz,Output:125MHz
-- In/Out Rate:                    1Gbps/1Gbps
-- Block RAM Usage:
-- Slice Usage: 
-- Block Technical Info:
-- Additional Comments: 

--****************************************************************************************

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;

library unisim;
use unisim.vcomponents.all;



entity Ethernet_1g is
generic (
			LAN_Lable                           : string:="LAN_0";
			IDELAY_GRP_Str                      : string:="Grp_KED";
			IDELAY_GRP_Str_s               		: string:="<Grp_KED_tx>";
			g_TIME_OUT_LOOKUP_TABLE_ARP			: std_logic_vector(31 downto 0):= x"9502F900"; --20S												
			g_TIME_OUT_WAIT_FOR_ARP_REPLY		: std_logic_vector(31 downto 0):= x"07735940";  --1S												
			g_RE_SEND_ARP_REQUEST			    : std_logic_vector(3 downto 0):= x"A";  --10	
      	    g_GENERATE_PING_MODULE              : boolean := true;
            g_GENERATE_ARP_MODULE               : boolean := true;
            g_DEFAULT_DST_MAC_ADDR              : std_logic_vector (47 downto 0) := x"AABBCCDDEEFF"
            			
			);
port
(
	
    i_clk_125              : in  STD_LOGIC ;
    
    rx_mac_aclk            : out  STD_LOGIC ;
    gmii_rx_clk            : in  STD_LOGIC ;
    gmii_tx_clk            : out  STD_LOGIC ;
        
	i_global_reset         : in STD_LOGIC ;
	i_vector_reset         : in STD_LOGIC ;
	refclk                 : in  std_logic;
	i_Reset_tx             : in STD_LOGIC ;
	i_Reset_rx             : in STD_LOGIC ;
	o_tx_clk_out           : out STD_LOGIC ;
	o_rx_clk_out           : out STD_LOGIC ;

	------------------------- UDP ----------------------------
	-- UDP & IP Tx header construction
	i_udp_tx_src_ip        : in  std_logic_vector (31 downto 0);
	i_udp_tx_dst_ip        : in  std_logic_vector (31 downto 0);
	i_udp_tx_data_len      : in  std_logic_vector (15 downto 0);
	i_udp_tx_protocol      : in  std_logic_vector (7 downto 0);
    i_udp_tx_src_mac       : in  std_logic_vector (47 downto 0);
	i_udp_tx_checksum      : in  std_logic_vector (15 downto 0);
	i_udp_tx_src_port      : in  std_logic_vector (15 downto 0);
	i_udp_tx_dst_port      : in  std_logic_vector (15 downto 0);
	i_ip_tx_fragmantation  : in  std_logic_vector(15 downto 0):=x"4000"; 
	i_fragment_len         : in    std_logic_vector(16 - 1 downto 0):=x"4000";
	-- UDP TX Inpus
	i_udp_tx_start         : in  std_logic;
	o_udp_tx_ready         : out std_logic;
	o_mac_tx_tready        : out std_logic;
    i_udp_tx_din	       : in  std_logic_vector (7 downto 0);

	-- UDP RX Outputs
	o_udp_rx_dout          : buffer std_logic_vector(7 downto 0);
	o_udp_rx_dout_rdy      : buffer std_logic;
	o_udp_rx_dout_last     : buffer std_logic;
	
	-- UDP RX Status Outputs
	o_udp_rx_src_ip        : out std_logic_vector(31 downto 0);
    o_udp_rx_src_port      : out std_logic_vector(15 downto 0);
    o_udp_rx_dst_port      : out std_logic_vector(15 downto 0);
    o_udp_rx_data_len      : out std_logic_vector(15 downto 0);	
	o_udp_rx_err_out       : out std_logic_vector(3 downto 0);
	o_udp_tx_err_out       : out std_logic_vector(3 downto 0);
	o_arp_rx_err_out       : out std_logic_vector(3 downto 0);
	o_ip_rx_fragmantation  : out std_logic_vector(15 downto 0); 
	
	o_arp_addr_valid       : out  std_logic;
   -- IP Status
    o_ip_rx_dst_ip         : out std_logic_vector(31 downto 0);
    o_ip_rx_err_out        : out std_logic_vector (3 downto 0);
    o_ip_tx_err_out        : out std_logic_vector (3 downto 0);
	

	--------------------- PHY --------------------------------
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


	i_gmii_crs             : in  std_logic;
    i_gmii_col             : in  std_logic

	
);
end Ethernet_1g;

architecture Behavioral of Ethernet_1g is


COMPONENT tri_mode_ethernet_mac_0
  PORT (
    gtx_clk : IN STD_LOGIC;
    glbl_rstn : IN STD_LOGIC;
    rx_axi_rstn : IN STD_LOGIC;
    tx_axi_rstn : IN STD_LOGIC;
    rx_statistics_vector : OUT STD_LOGIC_VECTOR(27 DOWNTO 0);
    rx_statistics_valid : OUT STD_LOGIC;
    rx_mac_aclk : OUT STD_LOGIC;
    rx_reset : OUT STD_LOGIC;
    rx_axis_mac_tdata : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    rx_axis_mac_tvalid : OUT STD_LOGIC;
    rx_axis_mac_tlast : OUT STD_LOGIC;
    rx_axis_mac_tuser : OUT STD_LOGIC;
    tx_ifg_delay : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    tx_statistics_vector : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    tx_statistics_valid : OUT STD_LOGIC;
    tx_mac_aclk : OUT STD_LOGIC;
    tx_reset : OUT STD_LOGIC;
    tx_axis_mac_tdata : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    tx_axis_mac_tvalid : IN STD_LOGIC;
    tx_axis_mac_tlast : IN STD_LOGIC;
    tx_axis_mac_tuser : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    tx_axis_mac_tready : OUT STD_LOGIC;
    pause_req : IN STD_LOGIC;
    pause_val : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    speedis100 : OUT STD_LOGIC;
    speedis10100 : OUT STD_LOGIC;
    gmii_txd : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    gmii_tx_en : OUT STD_LOGIC;
    gmii_tx_er : OUT STD_LOGIC;
    gmii_tx_clk : OUT STD_LOGIC;
    gmii_rxd : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    gmii_rx_dv : IN STD_LOGIC;
    gmii_rx_er : IN STD_LOGIC;
    gmii_rx_clk : IN STD_LOGIC;
    rx_configuration_vector : IN STD_LOGIC_VECTOR(79 DOWNTO 0);
    tx_configuration_vector : IN STD_LOGIC_VECTOR(79 DOWNTO 0)
  );
END COMPONENT;

--=========================================================================================
signal s_reset_txn                : std_logic;
signal s_reset_rxn                : std_logic;


--================================ Ethernet 1g Signals =================================================
signal   s_tx_clk                 :  std_logic;
signal   s_rx_clk                 :  std_logic;
signal   s_rstn                   :  std_logic;
signal   s_vecrstn                :  std_logic;



--mac to gmii_if signals
signal   s_mac_gmii_rxd           :  std_logic_vector(7 downto 0);
signal   s_mac_gmii_rx_dv         :  std_logic;
signal   s_mac_gmii_rx_er         :  std_logic;
                
signal   s_mac_gmii_txd           :  std_logic_vector(7 downto 0);
signal   s_mac_gmii_tx_en         :  std_logic;
signal   s_mac_gmii_tx_er         :  std_logic;



--ip to mac signals
signal   s_mac_tx_tready        :  std_logic;
signal	 s_mac_tx_tdata         :  std_logic_vector(7 downto 0);  
signal   s_mac_tx_tvalid        :  std_logic;    
signal   s_mac_tx_tlast         :  std_logic; 
            
signal   s_mac_rx_tdata         :  std_logic_vector(7 downto 0);  
signal   s_mac_rx_tvalid        :  std_logic;  
signal   s_mac_rx_tlast         :  std_logic;
signal   s_mac_gtx_clkout       :  std_logic;

signal   s_Rx_vector            :  std_logic_vector(80-1 downto 0);
signal   s_Tx_vector            :  std_logic_vector(80-1 downto 0);

signal   i_global_reset_r       :  std_logic;

signal  s_udp_rx_err_out       :  std_logic_vector (3 downto 0);
signal  s_udp_tx_err_out       :  std_logic_vector (3 downto 0);
signal  s_arp_rx_err_out       :  std_logic_vector (3 downto 0);
--======================================================================================================
 
    
constant  tx_ifg_delay   : STD_LOGIC_VECTOR(7 DOWNTO 0):=x"00"; 
signal    tx_reset   : STD_LOGIC:='0'; 
signal    rx_reset   : STD_LOGIC:='0'; 
signal    Reset_txn   : STD_LOGIC:='0'; 

signal  rx_configuration_vector :  std_logic_vector(79 downto 0):=(others => '0');
signal  tx_configuration_vector :  std_logic_vector(79 downto 0):=(others => '0');

signal  pause_req :  std_logic;
signal  pause_val :  std_logic_vector(15 downto 0);

begin

o_mac_tx_tready <=  s_mac_tx_tready;

o_udp_rx_err_out    <=  s_udp_rx_err_out;
o_udp_tx_err_out    <=  s_udp_tx_err_out;
o_arp_rx_err_out    <=  s_arp_rx_err_out;

--========================= Clk & Reset ===================================================
s_rstn             <= not(i_global_reset);
s_reset_txn        <= not(i_reset_tx);
s_reset_rxn        <= not(i_reset_rx);

o_tx_clk_out       <= s_tx_clk;
o_rx_clk_out       <= s_rx_clk;
--=========================================================================================

process(i_clk_125)

begin
    if(rising_edge(i_clk_125)) then
        i_global_reset_r    <=  i_global_reset;
        
        pause_req           <=  '0';
        pause_val           <=  (others => '0');
    end if;
end process;
             

--=============================== UDP ====================================================
--inst_UDP:UDP_NGC
inst_UDP:entity work.UDP_KED


generic map(
			g_TIME_OUT_LOOKUP_TABLE_ARP	    => g_TIME_OUT_LOOKUP_TABLE_ARP,											
			g_TIME_OUT_WAIT_FOR_ARP_REPLY	=> g_TIME_OUT_WAIT_FOR_ARP_REPLY,				
			g_RE_SEND_ARP_REQUEST			=> g_RE_SEND_ARP_REQUEST,
            g_GENERATE_PING_MODULE          => g_GENERATE_PING_MODULE,
            g_GENERATE_ARP_MODULE           => g_GENERATE_ARP_MODULE,
            g_DEFAULT_DST_MAC_ADDR          => g_DEFAULT_DST_MAC_ADDR    			
			)
port map
(
	i_ip_tx_fragmantation       => i_ip_tx_fragmantation,  
	i_fragment_len              => i_fragment_len,
	o_ip_rx_fragmantation       => o_ip_rx_fragmantation,

	i_rx_clk                     => s_rx_clk,
    i_tx_clk                     => i_clk_125,         --125MHz
    i_reset_tx                   => tx_reset,--  i_Reset_tx,--
    i_reset_rx                   => rx_reset,--  i_Reset_rx,--
    
	--******************************* IP ***************************************
	-- IP to MAC TX Outputs
   i_mac_tx_tready              => s_mac_tx_tready, 
	o_mac_tx_tdata               => s_mac_tx_tdata,  
   o_mac_tx_tvalid              => s_mac_tx_tvalid, 
   o_mac_tx_tlast               => s_mac_tx_tlast,  
                               
	-- MAC to IP RX Inputs     
   i_mac_rx_tdata               => s_mac_rx_tdata,  
   i_mac_rx_tvalid              => s_mac_rx_tvalid, 
   i_mac_rx_tlast               => s_mac_rx_tlast,  
                               
                              
   --IP Status
   o_ip_rx_dst_ip               => o_ip_rx_dst_ip,  
   o_ip_rx_err_out              => o_ip_rx_err_out, 
   o_ip_tx_err_out              => o_ip_tx_err_out, 
   o_arp_rx_err_out             => s_arp_rx_err_out, 
	                           
	--************************** UDP*********************************************
	-- UDP & IP Tx header construction
	i_udp_tx_src_ip              => i_udp_tx_src_ip,   
	i_udp_tx_dst_ip              => i_udp_tx_dst_ip,   
	i_udp_tx_data_len            => i_udp_tx_data_len, 
	i_udp_tx_protocol            => i_udp_tx_protocol ,
    i_udp_tx_src_mac             => i_udp_tx_src_mac,  
	i_udp_tx_checksum            => i_udp_tx_checksum, 
	i_udp_tx_src_port            => i_udp_tx_src_port, 
	i_udp_tx_dst_port            => i_udp_tx_dst_port,                          
	-- UDP TX Inpus            
	i_udp_tx_start               => i_udp_tx_start, 
	o_udp_tx_ready               => o_udp_tx_ready, 
   i_udp_tx_din	              => i_udp_tx_din,	 
                              
	-- UDP RX Outputs          
	o_udp_rx_dout                => o_udp_rx_dout,      
	o_udp_rx_dout_rdy            => o_udp_rx_dout_rdy,  
	o_udp_rx_dout_last           => o_udp_rx_dout_last, 
	                           
	-- UDP RX Status Outputs  
	o_udp_rx_src_ip              => o_udp_rx_src_ip,    
    o_udp_rx_src_port            => o_udp_rx_src_port,  
    o_udp_rx_dst_port            => o_udp_rx_dst_port,  
    o_udp_rx_data_len            => o_udp_rx_data_len , 
    	
	o_arp_addr_valid             => o_arp_addr_valid,
   
    o_udp_rx_err_out	         => s_udp_rx_err_out,	  
	o_udp_tx_err_out             => s_udp_tx_err_out   
       		 
);
--=========================================================================================

--LAN0_MAC: Entity Work.MAC_Controller 
--GENERIC MAP(
--	PHY_ADDR => "00100",	-- PHY_AD0/1 pulled-down by 1KOhm, PHY_AD2 pulled-up in .ucf file.
--	CLK_FREQUENCY => 125
--)
--PORT MAP(
--	CLK 					=> i_clk_125,
--	IDELAYREFCLK200MHZ 	    => refclk,
--	ASYNC_RESET 			=> i_Reset_tx,
--	MAC_ADDR 				=> x"0123456789ab",
--	MAC_TX_CONFIG 			=> X"0003",	-- MAC must must provide pad + crc32
--	MAC_RX_CONFIG 			=> x"000F",	-- promiscuous mode, strip crc32, accept broadcast/multicast
--	PHY_CONFIG_CHANGE 	    => '1',--CONFIG_CHANGE_PULSE,	
--	PHY_RESET 				=> '0',
--	SPEED 					=> "10",	-- supersedes defaults within if PHY_CONFIG_CHANGE = '1'
--	DUPLEX 					=> '1',	-- supersedes defaults within if PHY_CONFIG_CHANGE = '1'
--	TEST_MODE 				=> "00",	-- supersedes defaults within if PHY_CONFIG_CHANGE = '1'
--	POWER_DOWN 				=> '0', -- supersedes defaults within if PHY_CONFIG_CHANGE = '1'
--	MAC_TX_DATA 			=> s_mac_tx_tdata,
--	MAC_TX_DATA_VALID 	    => s_mac_tx_tvalid,
--	MAC_TX_EOF 				=> s_mac_tx_tlast,
--	MAC_TX_CTS 				=> s_mac_tx_tready,
--	MAC_RX_DATA 			=> s_mac_rx_tdata,	
--	MAC_RX_DATA_VALID 	    => s_mac_rx_tvalid,
--	MAC_RX_SOF 				=> open,--s_mac_rx_SOF,
--	MAC_RX_EOF 				=> s_mac_rx_tlast,
--	MAC_RX_CTS 				=> '1',  -- follow-on processing is expected to always accept data even at max speed.
--	RESET_N 				=> OPEN,--o_LAN1G_RESETn1,
--	GMII_MII_TXD 			=> o_gmii_txd,
--	GMII_MII_TX_EN			=> o_gmii_tx_en,
--	GMII_MII_TX_ER 		    => o_gmii_tx_er,
--	GMII_MII_RX_CLK 		=> i_clk_125,
--	GMII_MII_RXD 			=> i_gmii_rxd,
--	GMII_MII_RX_DV			=> i_gmii_rx_dv,
--	GMII_MII_RX_ER 		    => i_gmii_rx_er,  -- end of MII interface ------
		
--	PHY_ID 					=> open
--);	 
Reset_txn <=  not i_Reset_tx;

LAN0_MAC : tri_mode_ethernet_mac_0
  PORT MAP (
    gtx_clk                 => i_clk_125,
    glbl_rstn               => Reset_txn,
    rx_axi_rstn             => '1',
    tx_axi_rstn             => '1',
    rx_statistics_vector    => open,
    rx_statistics_valid     => open,
    rx_mac_aclk             => rx_mac_aclk,--??
    rx_reset                => rx_reset,
    rx_axis_mac_tdata       => s_mac_rx_tdata,
    rx_axis_mac_tvalid      => s_mac_rx_tvalid,
    rx_axis_mac_tlast       => s_mac_rx_tlast,
    rx_axis_mac_tuser       => open,
    tx_ifg_delay            => tx_ifg_delay,
    tx_statistics_vector    => open,
    tx_statistics_valid     => open,
    tx_mac_aclk             => open,--??
    tx_reset                => tx_reset,
    tx_axis_mac_tdata       => s_mac_tx_tdata,
    tx_axis_mac_tvalid      => s_mac_tx_tvalid,
    tx_axis_mac_tlast       => s_mac_tx_tlast,
    tx_axis_mac_tuser       => "0",
    tx_axis_mac_tready      => s_mac_tx_tready,
    pause_req               => pause_req,
    pause_val               => pause_val,
    speedis100              => open,
    speedis10100            => open,
    gmii_txd                => o_gmii_txd,
    gmii_tx_en              => o_gmii_tx_en,
    gmii_tx_er              => o_gmii_tx_er,
    gmii_tx_clk             => gmii_tx_clk,--??
    gmii_rxd                => i_gmii_rxd,
    gmii_rx_dv              => i_gmii_rx_dv,
    gmii_rx_er              => i_gmii_rx_er,
    gmii_rx_clk             => gmii_rx_clk,
    rx_configuration_vector => rx_configuration_vector,
    tx_configuration_vector => tx_configuration_vector
  );


rx_configuration_vector(13 downto 12)  <=  "10";--1G
rx_configuration_vector(1)  <=  '1';--Enable

tx_configuration_vector(13 downto 12)  <=  "10";--1G
tx_configuration_vector(1)  <=  '1';--Enable
    -- -- ////////////////////////////
    
   -- inst_MAC_RGMII: entity work.tri_mode_ethernet_mac_1_example_design
  -- generic map( IDELAY_GRP_Str                 => IDELAY_GRP_Str )
    -- port map (
      -- -- asynchronous reset
      -- ----------------------------
      -- glbl_rst             => '0',--i_global_reset_r,

      -- -- 200MHz clock input from board
      -- refclk_bufg          => refclk,
      -- -- 125 MHz clock 
      -- gtx_clk_bufg         => i_clk_125,

      -- phy_resetn           => open,


      -- -- RGMII Interface
      -- ----------------------------
      -- rgmii_txd            => o_Rgmii_txd,
      -- rgmii_tx_ctl         => o_Rgmii_tx_ctrl,
      -- rgmii_txc            => o_Rgmii_txc,
      -- rgmii_rxd            => i_Rgmii_rxd,
      -- rgmii_rx_ctl         => i_Rgmii_rx_ctrl,
      -- rgmii_rxc            => i_Rgmii_rxc,

    
      -- --------------------------------------
      -- rx_axis_tdata     =>	s_mac_rx_tdata    ,    
      -- rx_axis_tvalid    =>  s_mac_rx_tvalid   ,    
      -- rx_axis_tlast     =>  s_mac_rx_tlast   ,    
      -- rx_axis_tready    =>  '1',--s_mac_rx_tready  ,    
                                                  
      -- tx_axis_tdata     =>   s_mac_tx_tdata   ,    
      -- tx_axis_tvalid    =>   s_mac_tx_tvalid  ,    
      -- tx_axis_tlast     =>   s_mac_tx_tlast  ,    
      -- tx_axis_tready    =>   s_mac_tx_tready , 
      -- --------------------------------------

      -- -- Serialised statistics vectors
      -- ----------------------------
      -- tx_statistics_s      => open,
      -- rx_statistics_s      => open,

      -- -- Serialised Pause interface controls
      -- ----------------------------------
      -- pause_req_s          => '0',

      -- -- Main example design controls
      -- ---------------------------
      -- mac_speed            => "10",
      -- update_speed         => '0',
      -- config_board         => '0',
      -- serial_response      => open,
      -- gen_tx_data          => '0',
      -- chk_tx_data          => '0',
      -- reset_error          => '0',
      -- frame_error          => open,
      -- frame_errorn         => open,
      -- activity_flash       => open,
      -- activity_flashn      => open
    -- );
    -- -- ////////////////////////////
    
    
s_tx_clk    <=  i_clk_125;
s_rx_clk    <=  i_clk_125;



-- my_ila_Phy : entity work.ila_0
-- PORT MAP (
--     clk                   => i_clk_125,

--     probe0(3 downto 0)     => "0000",--i_gmii_rxd,    
--     probe0(4)              => i_gmii_rx_dv,--i_gmii_rx_ctrl,
--     probe0(5)              => i_gmii_rx_er,--i_gmii_rxc,    
--     probe0(13 downto 6)    => s_mac_rx_tdata    ,  
--     probe0(14)             => s_mac_rx_tvalid   , 
--     probe0(15)             => s_mac_rx_tlast   ,  
--     probe0(23 downto 16)   => s_mac_tx_tdata   ,
--     probe0(24)             => s_mac_tx_tvalid  ,
--     probe0(25)             => s_mac_tx_tlast  , 
--     probe0(26)             => s_mac_tx_tready , 
--     probe0(30 downto 27)   => s_udp_rx_err_out   ,
--     probe0(34 downto 31)   => s_udp_tx_err_out   ,
--     probe0(38 downto 35)   => s_arp_rx_err_out   ,
--     probe0(39)             => i_global_reset   ,
--     probe0(40)             => tx_reset   ,
--     probe0(41)             => rx_reset   ,
     
--     probe0(49 downto 42)   => i_gmii_rxd,
--    probe0(57 downto 50)    => o_udp_rx_dout,
--    probe0(58)              => o_udp_rx_dout_rdy,
--    probe0(59)              => o_udp_rx_dout_last,
    
--     probe0(255 downto 60) => (others => '0')
-- );



----////////////////////////



end Behavioral;

