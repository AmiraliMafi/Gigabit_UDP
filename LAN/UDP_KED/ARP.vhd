--****************************************************************************************
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;

library work;
use work.signal_Package.all;

entity ARP is
generic (
			g_TIME_OUT_LOOKUP_TABLE_ARP			: std_logic_vector(31 downto 0):= x"9502F900"; --20S												
			g_TIME_OUT_WAIT_FOR_ARP_REPLY			: std_logic_vector(31 downto 0):= x"07735940";  --1S												
			g_RE_SEND_ARP_REQUEST			      : std_logic_vector(3 downto 0):= x"A"  --10												
			);
port(
    -- system signals
    i_rx_clk               : in   std_logic;  
    i_tx_clk               : in   std_logic;  
    i_reset                : in   std_logic;
	 
	 --for ARP Data
	 i_our_ip_addr          : in   std_logic_vector (31 downto 0);
	 i_our_mac_addr         : in   std_logic_vector (47 downto 0);
	 
	 -- to/from IP Layer
	 i_fpga_req             : in   std_logic;
	 i_lookup_ip            : in   std_logic_vector (31 downto 0);
	 o_lookup_mac_addr      : out  std_logic_vector (47 downto 0);
	 o_lookup_mac_got       : out  std_logic;
	 o_lookup_mac_err       : out  std_logic;
	 
	 
	 --ARP_RX Input
    i_mac_data_in        : in  std_logic_vector (7 downto 0);  
    i_mac_data_in_valid  : in  std_logic;  
    i_mac_data_in_last   : in  std_logic;
	 
	 
	 --ARP_TX Input/Output
	 o_mac_tx_req         : out std_logic;  
    i_mac_tx_granted     : in  std_logic;    
    i_mac_tready         : in  std_logic;  
    o_mac_tvalid         : out std_logic;  
    o_mac_tlast          : out std_logic;  
    o_mac_tdata          : out std_logic_vector (7 downto 0);
	 
	 -- Error Out
	 o_arp_rx_err_out     : out std_logic_vector (3 downto 0)
	 

);
end ARP;

architecture Behavioral of ARP is






--=========================== ARP_RX ====================================================
component ARP_RX is
generic (
			g_TIME_OUT_LOOKUP_TABLE_ARP			: std_logic_vector(31 downto 0):= x"9502F900" --20S												
			);
  port (
    
    -- system signals
    i_rx_clk             : in  std_logic;  
    i_tx_clk             : in  std_logic;  
    i_reset              : in  std_logic;
    i_our_ip_addr        : in  std_logic_vector (31 downto 0);
	
	-- MAC layer RX inputs
    i_mac_data_in        : in  std_logic_vector (7 downto 0);  
    i_mac_data_in_valid  : in  std_logic;  
    i_mac_data_in_last   : in  std_logic;
	
	-- Outputs to ARP 
	o_ip_addr0            : out std_logic_vector(31 downto 0);
	o_mac_addr0           : out std_logic_vector(47 downto 0);
	o_addr_valid0         : out std_logic;	
	o_pc_reply            : out std_logic;
	o_pc_req              : out std_logic;
	
	-- Error Out
	o_arp_rx_err_out      : out std_logic_vector (3 downto 0)
    );                   
end component;
--========================================================================================












--================================= ARP_TX ================================================
component ARP_TX is
  port (
    i_tx_clk              : in  std_logic;  
    i_reset               : in  std_logic;
	
   --for ARP Data
	i_our_ip_addr          : in  std_logic_vector (31 downto 0);
	i_our_mac_addr         : in  std_logic_vector (47 downto 0);
	i_dst_ip_addr_pc       : in  std_logic_vector (31 downto 0);
	i_dst_mac_addr_pc      : in  std_logic_vector (47 downto 0);
	i_dst_ip_addr_lookup   : in  std_logic_vector (31 downto 0);
	
    --ARP Request's
   i_fpga_req             : in  std_logic;
   i_pc_req               : in  std_logic;


    -- for transfer data to mac layer
    o_mac_tx_req         : out std_logic;  
    i_mac_tx_granted     : in  std_logic;    
    i_mac_tready         : in  std_logic;  
    o_mac_tvalid         : out std_logic;  
    o_mac_tlast          : out std_logic;  
    o_mac_tdata          : out std_logic_vector (7 downto 0)
	
    );
end component;
--========================================================================================





--================================= Constant ===========================================================
--Generate Block Conditional Constants
constant c_GENERATE_PING_MODULE             : boolean  := true;                                  --if Ping Block is not Used,Value is False
constant c_GENERATE_ARP_MODULE              : boolean  := true;                                  --if ARP  Block is not Used,Value is False
constant c_DEFAULT_DST_MAC_ADDR             : std_logic_vector (47 downto 0) := x"F46D04962225"; --if ARP Block is not Used,Copy PC MAC Address to This Value 	


--Application Layer Data Length
constant c_PACKET_LENGTH                    : std_logic_vector (15 downto 0):= x"05c0";          --1472 (Maximum Application Layer Packet Length)
constant c_udp_tx_src_ip                    : std_logic_vector (31 downto 0):= x"C0A86403";      --192.168.100.3(FPGA IP Adress)
constant c_udp_tx_dst_ip                    : std_logic_vector (31 downto 0):= x"C0A86402";      --192.168.100.2(PC IP Address)
constant c_udp_tx_protocol                  : std_logic_vector (7 downto 0) := x"11";            --UDP Protocol
constant c_udp_tx_src_mac                   : std_logic_vector (47 downto 0):= x"112233445566";  --FPGA MAC Address
constant c_udp_tx_checksum                  : std_logic_vector (15 downto 0):= x"0000";          --UDP Checksum(Value For This Constant is not Importanat)
constant c_udp_tx_src_port                  : std_logic_vector (15 downto 0):= x"0401";          --UDP Src Port(Value For This Constant is not Importanat)
constant c_udp_tx_dst_port                  : std_logic_vector (15 downto 0):= x"0FF5";          --UDP Dst Port(Value For This Constant is not Importanat)


--ARP Constants
constant c_TIME_OUT_LOOKUP_TABLE_ARP        : std_logic_vector (31 downto 0) := x"9502F900";     --20S(Value/125MHz = 20 )	
constant c_TIME_OUT_WAIT_FOR_ARP_REPLY      : std_logic_vector (31 downto 0) := x"07735940";     --1S	(Value/125MHz = 1 )	
constant c_RE_SEND_ARP_REQUEST              : std_logic_vector (3 downto 0)  := x"A";            --10	
       	

--IP Constants
constant c_IP_TTL                           : std_logic_vector (7 downto 0)  := x"80";           -- IP Packet Time to live
constant c_IP_BC_ADDR                       : std_logic_vector (31 downto 0) := x"ffffffff";     -- Broadcast IP  Address
constant c_MAC_BC_ADDR                      : std_logic_vector (47 downto 0) := x"ffffffffffff"; -- Broadcast MAC Address
--======================================================================================================




--============================= Top Signals ============================================================

--signal   s_udp_tx_data_len      : std_logic_vector (15 downto 0):= c_PACKET_LENGTH;  --1472 (Maximum Application Layer Packet Length)
--signal 	s_udp_tx_start         : std_logic:='0';
--signal 	s_udp_tx_ready         : std_logic;
--signal   s_udp_tx_din	         : std_logic_vector (7 downto 0);
--
--signal 	s_udp_rx_dout          : std_logic_vector(7 downto 0);
--signal 	s_udp_rx_dout_rdy      : std_logic;
--signal 	s_udp_rx_dout_last     : std_logic;
--	
--signal 	s_udp_rx_src_ip        : std_logic_vector(31 downto 0);
--signal   s_udp_rx_src_port      : std_logic_vector(15 downto 0);
--signal   s_udp_rx_dst_port      : std_logic_vector(15 downto 0);
--signal   s_udp_rx_data_len      : std_logic_vector(15 downto 0);	
--signal 	s_udp_rx_err_out_top	      : std_logic_vector(3 downto 0);
--signal 	s_udp_tx_err_out_top       : std_logic_vector(3 downto 0);
--signal 	s_arp_rx_err_out_top   : std_logic_vector(3 downto 0);
--signal   s_ip_rx_dst_ip_top         : std_logic_vector(31 downto 0);
--signal   s_ip_rx_err_out_top        : std_logic_vector (3 downto 0);
--signal   s_ip_tx_err_out_top        : std_logic_vector (3 downto 0);
--
--
--signal   s_rx_clk_out           : std_logic;
--signal   s_buff_rx_clk_out      : std_logic;
--signal   s_tx_clk_out           : std_logic;
--signal   s_buff_tx_clk_out      : std_logic;
--signal   s_clk_125              : std_logic;
--signal   s_clk_100              : std_logic;
--signal   s_clk_m                : std_logic;
--
----chip scope
--signal   s_control              : std_logic_vector (35 downto 0);
--signal   s_data_log             : std_logic_vector (15 downto 0);
--
--
----for transmit data
--signal   s_data_test_val        : std_logic:='0';
--signal   s_data_test_last       : std_logic:='0';
--signal   s_data_test            : std_logic_vector (7 downto 0):=(others=>'0');
--signal   s_cnt2                 : std_logic_vector (15 downto 0):=(others=>'0');
--signal   s_global_reset         : std_logic:='1';
--
--
--
--signal   s_gmii_txd           : std_logic_vector(7 downto 0);
--signal   s_gmii_tx_en         : std_logic;
--signal   s_gmii_tx_er         : std_logic;
--======================================================================================================






--===================== Reset_gen Signals ==============================================================
signal   s_cnt_rst     : std_logic_vector(15 downto 0):=(others=>'0');
--======================================================================================================






--================================ Ethernet 1g Signals =================================================
signal   s_gtx_clk                :  std_logic;
signal   s_tx_clk                 :  std_logic;
signal   s_rx_clk                 :  std_logic;
signal   s_rstn                   :  std_logic;
signal   s_rx_reset             :  std_logic;
signal   s_tx_reset             :  std_logic;


--mac to gmii_if signals
signal   s_mac_gmii_rxd           :  std_logic_vector(7 downto 0);
signal   s_mac_gmii_rx_dv         :  std_logic;
signal   s_mac_gmii_rx_er         :  std_logic;
                
signal   s_mac_gmii_txd           :  std_logic_vector(7 downto 0);
signal   s_mac_gmii_tx_en         :  std_logic;
signal   s_mac_gmii_tx_er         :  std_logic;



--ip to mac signals
signal   s_mac_tx_tready        :  std_logic;
signal	s_mac_tx_tdata         :  std_logic_vector(7 downto 0);  
signal   s_mac_tx_tvalid        :  std_logic;    
signal   s_mac_tx_tlast         :  std_logic; 
            
signal   s_mac_rx_tdata         :  std_logic_vector(7 downto 0);  
signal   s_mac_rx_tvalid        :  std_logic;  
signal   s_mac_rx_tlast         :  std_logic;
--======================================================================================================










--================================ UDP Signals =========================================================
    -------- for transfer Rx data from IP to UDP layer----------------
	signal s_ip_rx_dout           :  std_logic_vector(7 downto 0);
	signal s_ip_rx_dout_rdy       :  std_logic;
	signal s_ip_rx_dout_last      :  std_logic;	
	
	-------- for transfer Rx status data from IP to UDP layer---------
	signal s_ip_rx_src_ip         :  std_logic_vector(31 downto 0);
    signal s_ip_rx_dst_ip         :  std_logic_vector(31 downto 0);
    signal s_ip_rx_data_len       :  std_logic_vector(15 downto 0); 
    signal s_ip_rx_protocol       :  std_logic_vector(7 downto 0); 
    signal s_ip_rx_broadcast      :  std_logic;
    signal s_ip_rx_err_out_udp        :  std_logic_vector (3 downto 0);
    signal s_ip_tx_err_out_udp        :  std_logic_vector (3 downto 0);
    signal s_arp_rx_err_out_udp       :  std_logic_vector (3 downto 0);
	
	-------- for transfer Tx data from UDP to IP layer---------------
	signal s_ip_tx_start          :  std_logic; 
	signal s_ip_tx_rdy            :  std_logic; 
	signal s_ip_tx_din	          :  std_logic_vector(7 downto 0); 
	
	-------- for transfer Tx header data from UDP to IP layer--------
	signal s_ip_tx_src_ip         :  std_logic_vector(31 downto 0);
	signal s_ip_tx_dst_ip         :  std_logic_vector(31 downto 0);
	signal s_ip_tx_src_mac        :  std_logic_vector(47 downto 0);
	signal s_ip_tx_data_len       :  std_logic_vector(15 downto 0);
	signal s_ip_tx_protocol       :  std_logic_vector(7 downto 0);
	-----------------------------------------------------------------
--======================================================================================================
	
	
	
	




	
	
--============================= IP Signals =============================================================
  signal s_ip_mac_tx_tvalid    : std_logic;
  signal s_ip_mac_tx_tlast     : std_logic;
  signal s_ip_mac_tx_tdata     : std_logic_vector(7 downto 0);
  signal s_ip_mac_tx_req       : std_logic;
  signal s_ip_mac_tx_granted   : std_logic;
  
  signal s_arp_mac_tx_tvalid   : std_logic;
  signal s_arp_mac_tx_tlast    : std_logic;
  signal s_arp_mac_tx_tdata    : std_logic_vector(7 downto 0);
  signal s_arp_mac_tx_req      : std_logic;
  signal s_arp_mac_tx_granted  : std_logic;
  
  signal s_ping_mac_tx_tvalid   : std_logic;
  signal s_ping_mac_tx_tlast    : std_logic;
  signal s_ping_mac_tx_tdata    : std_logic_vector(7 downto 0);
  signal s_ping_mac_tx_req      : std_logic;
  signal s_ping_mac_tx_granted  : std_logic;
  
  signal s_lookup_req          : std_logic;
  signal s_lookup_ip           : std_logic_vector(31 downto 0);
  signal s_lookup_mac_addr     : std_logic_vector(47 downto 0);
  signal s_lookup_mac_got      : std_logic;
  signal s_lookup_mac_err      : std_logic;
  
  
 
  signal s_no_ping_packet      : std_logic;
  signal s_ip_rx_err_out	    : std_logic_vector(3 downto 0);
  --======================================================================================================
  
  
  
  
  
  
  
  
  
  
  
  
  --============================= IP4_TX Signals ==========================================================
  type t_tx_ip_state_type   is (IDLE,WAIT_MAC_ADDR,WAIT_CHN,SEND_DATA);
  type t_crc_state_type  is (IDLE, TOT_LEN, ID, FLAGS, TTL, CKS, SAH, SAL, DAH, DAL, ADDOVF, FINAL, WAIT_END);
  signal st_crc_state     : t_crc_state_type:=IDLE;
  signal s_tx_hdr_cks    : std_logic_vector (23 downto 0):=(others=>'0');
  signal s_cal_cheksum   : std_logic:='0';
  
  
  signal st_tx_ip_state      : t_tx_ip_state_type:=IDLE;
  signal s_cnt_ip_tx      : std_logic_vector (15 downto 0):=(others=>'0');
  signal s_dst_mac_addr  : std_logic_vector (47 downto 0); -- arp block updats this signal
  signal s_total_length  : std_logic_vector (15 downto 0); -- s_total_length is i_data_length+20(ip header) 
  
  signal s_ip_header     : std_logic_vector (7 downto 0):=(others=>'0');
  --========================================================================================================
  
  
  
  
  
  
  
  
  
  
  --============================ IP4_RX  Signals============================================================
  type t_rx_ip_state_type is (IDLE,ETH_H,IP_H,USER_DATA,WAIT_END);
  signal st_RX_IP_STATE         : t_rx_ip_state_type:=IDLE;
  signal s_cnt_ip_rx         : std_logic_vector (15 downto 0):=x"0001";  
 
  signal s_src_ip_ip_rx         : std_logic_vector (31 downto 0):=(others=>'0');
  signal s_dst_ip_ip_rx         : std_logic_vector (31 downto 0):=(others=>'0');   
  signal s_data_len_ip_rx       : std_logic_vector (15 downto 0):=(others=>'0');  
  signal s_protocol_ip_rx       : std_logic_vector (7 downto 0) :=(others=>'0'); 
  signal s_broadcast_ip_rx      : std_logic;
  --========================================================================================================
  
  
  
  
  
  
  
  
  
  
  
--==================================== ARP Signals ==========================================================
type         t_arp_state_type is     (IDLE,LOOK_UP,WAIT_PC_REPLY);
signal       st_ARP_STATE             : t_arp_state_type:=IDLE;
signal       s_timeout_wait_reply_cnt           : std_logic_vector(31 downto 0):=(others=>'0');
signal       s_error_cnt             : std_logic_vector(3 downto 0):=(others=>'0');

--ARP_TX Signals
signal       s_dst_ip_addr_pc      : std_logic_vector(31 downto 0):=(others=>'0');
signal       s_dst_mac_addr_pc     : std_logic_vector(47 downto 0):=(others=>'0');
signal       s_dst_ip_addr_lookup  : std_logic_vector(31 downto 0):=(others=>'0');
signal       s_fpga_req_tx         : std_logic:='0';
signal       s_pc_req_tx           : std_logic:='0';


--ARP_RX Signals
signal       s_ip_addr0            : std_logic_vector(31 downto 0);  
signal       s_mac_addr0           : std_logic_vector(47 downto 0);  
signal       s_addr_valid0         : std_logic;
signal       s_pc_reply_rx         : std_logic;
signal       s_pc_req_rx           : std_logic;
--===========================================================================================================











--=============================== ARP RX Signals ============================================================
type t_rx_arp_state_type is       (IDLE,ETH_H,ARP_DATA,WAIT_END);
signal st_RX_ARP_STATE             : t_rx_arp_state_type:=IDLE;
signal s_cnt_arp_rx             : std_logic_vector (15 downto 0):=x"0001"; 


signal s_dst_ip            : std_logic_vector (31 downto 0):=(others=>'0');
signal s_operation         : std_logic_vector (15 downto 0):=(others=>'0');
signal s_addr_valid        : std_logic:='0';
signal s_pc_req            : std_logic:='0';
signal s_pc_reply          : std_logic:='0';

 
signal s_src_mac_arp_rx            : std_logic_vector (47 downto 0):=(others=>'0');  
signal s_src_ip_arp_rx             : std_logic_vector (31 downto 0):=(others=>'0');  
signal s_addr_valid_pulse   : std_logic:='0';  
signal s_pc_req_pulse       : std_logic:='0';  
signal s_pc_reply_pulse     : std_logic:='0';  
signal s_trans_data_pulse   : std_logic:='0';  
--===========================================================================================================












--=================================== ARP LOOKUP_TABLE Signals ==============================================
signal   s_timeout_lookup_table_cnt        : std_logic_vector(31 downto 0):=(others=>'0');

signal   s_din              : std_logic_vector(82 downto 0):=(others=>'0');
signal   s_wr_en            : std_logic;
signal   s_dout             : std_logic_vector(82 downto 0):=(others=>'0');
signal   s_valid            : std_logic;
signal   s_empty              : std_logic;
signal   s_notempty           : std_logic;


signal   s_mac_addr_out     : std_logic_vector(47 downto 0):=(others=>'0');
signal   s_ip_addr_out      : std_logic_vector(31 downto 0):=(others=>'0');
signal   s_addr_valid_out   : std_logic:='0';
signal   s_request_out      : std_logic:='0';
signal   s_reply_out        : std_logic:='0';
--============================================================================================================











--============================ ARP TX Signals ================================================================
type t_arp_tx_state_type   is (IDLE,WAIT_CHN,SEND_DATA);
signal st_tx_arp_state          : t_arp_tx_state_type:=IDLE;
signal s_cnt_arp_tx          : std_logic_vector (7 downto 0):=(others=>'0');
signal s_arp_type          : std_logic_vector (15 downto 0):=(others=>'0');
signal s_dst_ip_addr     : std_logic_vector (31 downto 0):=(others=>'0');
signal s_dst_mac_addr1   : std_logic_vector (47 downto 0):=(others=>'0');
signal s_dst_mac_addr2   : std_logic_vector (47 downto 0):=(others=>'0');
--============================================================================================================












--============================== PING Signals =================================================================
--for Delayed Inputs
signal   s_mac_data_in_r        : std_logic_vector (7 downto 0);  
signal   s_mac_data_in_valid_r  : std_logic;  
signal   s_mac_data_in_last_r   : std_logic;


--Sync_fifo_ping Signals
signal   s_ip_rx_in          : std_logic_vector(14 downto 0);
signal   s_ip_rx_out         : std_logic_vector(14 downto 0):=(others=>'0');
signal   s_mac_data_in     	: std_logic_vector(7 downto 0);
signal   s_mac_data_in_valid  : std_logic;
signal   s_mac_data_in_last   : std_logic;
signal   s_mac_data_in_last_d : std_logic;
signal   s_ip_rx_err_in       : std_logic_vector(3 downto 0);
signal   s_no_ping_data     : std_logic;
signal   s_empty_sync_fifo    : std_logic:='0';
signal   s_not_empty_sync_fifo: std_logic;


--Data_fifo_ping Signals
signal   s_rst_fifo_ping     : std_logic:='1';
signal   s_wr_en_fifo_ping   : std_logic:='0';
signal   s_din_fifo_ping     : std_logic_vector(7 downto 0):=(others=>'0');
signal   s_rd_en_fifo_ping   : std_logic;
signal   s_dout_fifo_ping    : std_logic_vector(7 downto 0);


--Checksum Signals
signal   s_checksum_data_out   : std_logic_vector(15 downto 0);
signal   s_checksum_data_in    : std_logic_vector(7 downto 0);
signal   s_checksum_start_calc : std_logic:='0';
signal   s_checksum_stop_calc  : std_logic:='0';


--st_PING_STATE Machine Process Signals 
type     t_ping_state            is (IDLE,ACQUIRE_DATA,WAIT_END,WAIT_CHN,SEND_DATA);
signal   st_PING_STATE               : t_ping_state:=IDLE;
signal   s_wr_cnt              : std_logic_vector(7 downto 0):=(others=>'0');
signal   s_rd_cnt              : std_logic_vector(7 downto 0):=(others=>'0');
signal   s_start_send          : std_logic;

 
signal   s_src_mac_ping           : std_logic_vector(47 downto 0):=(others=>'0');
signal   s_dst_mac_ping           : std_logic_vector(47 downto 0):=(others=>'0');
signal   s_src_ip_ping            : std_logic_vector(31 downto 0):=(others=>'0');
signal   s_dst_ip_ping            : std_logic_vector(31 downto 0):=(others=>'0');
--=================================================================================================================












--================================= Ping Checksum Calc Signals ====================================================
type        t_checksum_state   is   (IDLE,CALC);
signal      st_checksum_state      : t_checksum_state:=IDLE;

signal      s_flag       : std_logic:='0';
signal      s_din_r      : std_logic_vector(7 downto 0);
signal      s_sum        : std_logic_vector(31 downto 0):=(others=>'0');
--=================================================================================================================











--============================ TX_Arbitior Signals =====================================================================
type   t_state_type is       (IDLE,DATA_REQ,ARP_REQ,PING_REQ);
signal st_STATE               : t_state_type:=IDLE;
--======================================================================================================================












--============================ UDP RX Signals ===========================================================================
  type t_rx_udp_state_type is  (IDLE, UDP_HDR, USER_DATA, WAIT_END); 
  signal st_RX_UDP_STATE         : t_rx_udp_state_type:=IDLE;
  signal s_cnt_udp_rx         : std_logic_vector (15 downto 0):=x"0001";  
 
  signal s_src_ip_udp_rx  : std_logic_vector (31 downto 0):=(others=>'0');
  signal s_src_port       : std_logic_vector (15 downto 0):=(others=>'0');   
  signal s_dst_port       : std_logic_vector (15 downto 0):=(others=>'0'); 
  signal s_data_len_udp_rx       : std_logic_vector (15 downto 0):=(others=>'0'); 
  signal s_err_out        : std_logic_vector (3 downto 0) :=(others=>'0');
 --======================================================================================================================= 
  
  
  
  
  
  

  
  
  
  
 --============================ UDP TX Signals =============================================================================
  type t_tx_udp_state_type     is (IDLE,SEND_DATA);
  signal st_tx_udp_state        : t_tx_udp_state_type:=IDLE;
  
  signal s_cnt_udp_tx        : std_logic_vector (15 downto 0):=(others=>'0');
  signal s_ip_data_len   : std_logic_vector (15 downto 0);  
  signal s_udp_header      : std_logic_vector (7 downto 0):=(others=>'0');
--==========================================================================================================================











--============================ PHY_Interface Signals =======================================================================
signal s_gmii_col_reg         : std_logic;
signal s_gmii_col_reg_reg     : std_logic;
signal s_gmii_rx_clk          : std_logic;
--==========================================================================================================================











--=========================== Ping_Pong Fifo Signals =======================================================================
signal s_empty1              : std_logic;
signal s_empty2              : std_logic;
signal s_notempty1           : std_logic;
signal s_notempty2           : std_logic;


signal s_data_m              : std_logic_vector(7 downto 0);
signal s_valid_m             : std_logic;
signal s_last_m              : std_logic;


signal s_wr_en_a             : std_logic:='0';
signal s_din_a               : std_logic_vector(7 downto 0):=(others=>'0');
signal s_rd_en_a             : std_logic;
signal s_dout_a              : std_logic_vector(7 downto 0);
signal s_valid_a             : std_logic;
signal s_empty_a             : std_logic;

signal s_wr_en_b             : std_logic:='0';
signal s_din_b               : std_logic_vector(7 downto 0):=(others=>'0');
signal s_rd_en_b             : std_logic;
signal s_dout_b              : std_logic_vector(7 downto 0);
signal s_valid_b             : std_logic;
signal s_empty_b             : std_logic;


signal s_cnt_a               : std_logic_vector(15 downto 0):=(others=>'0');
signal s_cnt_b               : std_logic_vector(15 downto 0):=(others=>'0');
signal s_rd_cnt_a            : std_logic_vector(15 downto 0):=(others=>'0');
signal s_rd_cnt_b            : std_logic_vector(15 downto 0):=(others=>'0');

signal s_busy_a              : std_logic:='0';
signal s_busy_b              : std_logic:='0';

signal s_last_a              : std_logic:='0';
signal s_last_b              : std_logic:='0';

signal s_dout_len          : std_logic_vector(15 downto 0);

type        t_pingpong_state     is (wait_data,rd_fifo_a,rd_fifo_b);
signal      st_ping_pong_state          : t_pingpong_state:=wait_data; 
--========================================================================================================================= 


begin




--=============== Wait for ARP Requests and so Reply them =====================================
p_arp_control:process(i_tx_clk) 
begin
if rising_edge(i_tx_clk) then
	s_pc_req_tx       <= '0';
	s_fpga_req_tx     <= '0';
	o_lookup_mac_got    <= '0';
	o_lookup_mac_err    <= '0';
	
if (i_reset= '1') then
	 s_fpga_req_tx          <= '0';
	 s_pc_req_tx            <= '0';
	 s_dst_ip_addr_pc       <= (others=>'0');
	 s_dst_mac_addr_pc      <= (others=>'0');
	 s_dst_ip_addr_lookup   <= (others=>'0');
	 s_timeout_wait_reply_cnt            <= (others=>'0');
	 s_error_cnt              <= (others=>'0');
	 st_ARP_STATE              <= IDLE;
else

CASE st_ARP_STATE IS



WHEN IDLE =>
     s_timeout_wait_reply_cnt           <= (others=>'0');
     s_error_cnt             <= (others=>'0');   
     
	  if (s_pc_req_rx='1') then
	      s_pc_req_tx       <= '1';
			s_dst_ip_addr_pc  <= s_ip_addr0;
			s_dst_mac_addr_pc <= s_mac_addr0;
	  end if;		
	  if(i_fpga_req='1') then
        s_pc_req_tx        <='0';
        st_ARP_STATE          <= LOOK_UP;
	  end if;
	
	

WHEN LOOK_UP  => 
     s_fpga_req_tx        <= '1';
	  s_dst_ip_addr_lookup <= i_lookup_ip;
	  st_ARP_STATE            <= WAIT_PC_REPLY;  
	  s_error_cnt            <= s_error_cnt+1;
	  if ((s_addr_valid0='1') and (s_ip_addr0=i_lookup_ip)) then
	      o_lookup_mac_addr  <= s_mac_addr0;    
	      o_lookup_mac_got   <= '1';
			s_fpga_req_tx    <= '0';
			s_error_cnt        <= (others=>'0');
			st_ARP_STATE        <= IDLE;
     end if;
	  if (s_error_cnt = g_RE_SEND_ARP_REQUEST) then
	      s_fpga_req_tx    <= '0';
			s_error_cnt        <= (others=>'0');
			o_lookup_mac_err   <= '1';   
			st_ARP_STATE        <= IDLE;
	  end if;		
	       

	  

WHEN WAIT_PC_REPLY =>
     s_timeout_wait_reply_cnt         <= s_timeout_wait_reply_cnt+1;
	  if (s_pc_reply_rx='1') then
	      s_timeout_wait_reply_cnt     <= (others=>'0');
			st_ARP_STATE       <= LOOK_UP;
	  end if;
     if (s_timeout_wait_reply_cnt=g_TIME_OUT_WAIT_FOR_ARP_REPLY) then -- 1 second	time_out   
	      s_timeout_wait_reply_cnt     <= (others=>'0');
			st_ARP_STATE       <= LOOK_UP;
	  end if;


END CASE;
end if;
end if;

end process p_arp_control;
--================================================================================================

  
	  












--============================= ARP_RX ===========================================================
inst_ARP_RX:  ARP_RX 
generic map (
			g_TIME_OUT_LOOKUP_TABLE_ARP	=>	g_TIME_OUT_LOOKUP_TABLE_ARP									
			)
  port map (
    
    -- system signals
    i_rx_clk                   => i_rx_clk,              
    i_tx_clk                   => i_tx_clk,         
    i_reset                    => i_reset,          
    i_our_ip_addr              => i_our_ip_addr, 
	
	-- MAC layer RX inputs
    i_mac_data_in              => i_mac_data_in,        
    i_mac_data_in_valid        => i_mac_data_in_valid, 
    i_mac_data_in_last         => i_mac_data_in_last,   
	
	-- Outputs to ARP 
	o_ip_addr0                  => s_ip_addr0,      
	o_mac_addr0                 => s_mac_addr0,    
	o_addr_valid0               => s_addr_valid0,   
	o_pc_reply                  => s_pc_reply_rx,      
	o_pc_req                    => s_pc_req_rx,        
	
	-- Error Out
	o_arp_rx_err_out            => o_arp_rx_err_out
    ); 
--================================================================================================	 















--================================== ARP_TX ======================================================
inst_ARP_TX: ARP_TX
  port map (
    i_tx_clk                  => i_tx_clk,       
    i_reset                   => i_reset, 
	
   --for ARP Data
	i_our_ip_addr              => i_our_ip_addr,  
	i_our_mac_addr             => i_our_mac_addr, 
	i_dst_ip_addr_pc           => s_dst_ip_addr_pc,  
	i_dst_mac_addr_pc          => s_dst_mac_addr_pc,    
	i_dst_ip_addr_lookup       => s_dst_ip_addr_lookup,  
	
    --ARP Request's
   i_fpga_req                 => s_fpga_req_tx,  
   i_pc_req                   => s_pc_req_tx,    


    -- for transfer data to mac layer
    o_mac_tx_req              => o_mac_tx_req,      
    i_mac_tx_granted          => i_mac_tx_granted,  
    i_mac_tready              => i_mac_tready,      
    o_mac_tvalid              => o_mac_tvalid,      
    o_mac_tlast               => o_mac_tlast,       
    o_mac_tdata               => o_mac_tdata       
	
    );
--================================================================================================






end Behavioral;

