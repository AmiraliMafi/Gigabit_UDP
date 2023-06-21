--****************************************************************************************
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.signal_Package.all;

entity IPv4 is
generic (	
         g_GENERATE_ARP_MODULE              : boolean := true;			
         g_DEFAULT_DST_MAC_ADDR             : std_logic_vector (47 downto 0) := x"AABBCCDDEEFF"			
			);
    Port (
      i_rx_clk			   		: in  STD_LOGIC;
		i_tx_clk			   		: in  STD_LOGIC;
		i_reset 			   		: in  STD_LOGIC;
	  
		--************************************ TX **********************************
		-- Tx header construction
		i_ip_tx_src_ip         	: in  std_logic_vector (31 downto 0);
		i_ip_tx_dst_ip         	: in  std_logic_vector (31 downto 0);
		i_ip_tx_data_len       	: in  std_logic_vector (15 downto 0);  
		i_ip_tcp_tx_id       	: in  std_logic_vector (15 downto 0):=(others => '0');
		i_ip_tx_fragmantation   : in std_logic_vector(15 downto 0);   
		i_ip_tx_protocol       	: in  std_logic_vector (7 downto 0);
      i_ip_tx_src_mac        	: in  std_logic_vector (47 downto 0);
	  	            
      -- TX Inputs
      i_ip_tx_start          	: in  std_logic;
      o_ip_tx_rdy            	: out std_logic; 
      i_ip_tx_din	           	: in  std_logic_vector (7 downto 0);
	  
		-- TX Outputs      
      i_mac_tx_tready        	: in  std_logic;  
      o_mac_tx_tvalid        	: out std_logic;  
      o_mac_tx_tlast         	: out std_logic;  
      o_mac_tx_tdata         	: out std_logic_vector (7 downto 0);
		o_mac_tx_req           	: out std_logic;  
      i_mac_tx_granted       	: in  std_logic;
	              
		-- TX & ARP inouts
		o_lookup_req           	: out std_logic;
		o_lookup_ip            	: out std_logic_vector (31 downto 0);
		i_lookup_mac_addr      	: in  std_logic_vector (47 downto 0);
		i_lookup_mac_got       	: in  std_logic;
		i_lookup_mac_err       	: in  std_logic; 

      -- Error Status
      o_ip_tx_err_out        	: out std_logic_vector (3 downto 0);	  
        
      --******************************* RX ***************************************
		--RX Inputs
		i_mac_rx_tdata         	: in  std_logic_vector(7 downto 0);  
      i_mac_rx_tvalid        	: in  std_logic;  
      i_mac_rx_tlast         	: in  std_logic; 
			
			
      --RX Outputs	
		o_ip_rx_dout           	: out std_logic_vector(7 downto 0);
      o_ip_rx_dout_rdy       	: out std_logic;
      o_ip_rx_dout_last      	: out std_logic;
	
	
      --RX Status Outputs                              
      o_ip_rx_src_ip         	: out std_logic_vector(31 downto 0);
      o_ip_rx_dst_ip         	: out std_logic_vector(31 downto 0);
      o_ip_rx_data_len       	: out std_logic_vector(15 downto 0); 
      o_ip_rx_fragmantation     : out std_logic_vector(15 downto 0); 
      o_ip_rx_protocol       	: out std_logic_vector(7 downto 0); 
      o_ip_rx_broadcast      	: out std_logic;
		
		-- Error Status	
      o_no_ping_packet       	: out std_logic;
      o_ip_rx_err_out        	: out std_logic_vector (3 downto 0)
                
	--**************************************************************************** 
			);
end IPv4;

architecture structural of IPv4 is
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


--========================= IPv4_TX =============================================
COMPONENT IPv4_TX
generic (	
         g_GENERATE_ARP_MODULE              : boolean := true;			
         g_DEFAULT_DST_MAC_ADDR             : std_logic_vector (47 downto 0) := x"AABBCCDDEEFF"			
			);
    PORT(
			i_tx_clk               	: in  std_logic;  
         i_reset                	: in  std_logic;
	                     
	      -- IP header construction
			i_protocol             	: in  std_logic_vector (7 downto 0);
	      i_data_length          	: in  std_logic_vector (15 downto 0);
	      i_ip_tx_fragmantation     : in std_logic_vector(15 downto 0); 
	      i_our_ip_addr          	: in  std_logic_vector (31 downto 0);
	      i_our_mac_addr         	: in  std_logic_vector (47 downto 0);
	      i_dst_ip_addr          	: in  std_logic_vector (31 downto 0);	            
          
          -- IP inputs
			i_ip_tx_start          	: in  std_logic;
         o_ip_tx_ready          	: out std_logic; 
         i_data_in	           	: in  std_logic_vector (7 downto 0);
	                  
	      -- IP & ARP inouts
			o_lookup_req           	: out std_logic;
	      o_lookup_ip            	: out std_logic_vector (31 downto 0);
	      i_lookup_mac_addr      	: in  std_logic_vector (47 downto 0);
	      i_lookup_mac_got       	: in  std_logic;
	      i_lookup_mac_err       	: in  std_logic;              
          
         -- IP Outputs
			o_mac_tx_req           	: out std_logic;  
         i_mac_tx_granted       	: in  std_logic;    
         i_mac_tready           	: in  std_logic;  
         o_mac_tvalid           	: out std_logic;  
         o_mac_tlast            	: out std_logic;  
         o_mac_tdata            	: out std_logic_vector (7 downto 0);
         o_ip_tx_err_out        	: out std_logic_vector (3 downto 0)       		  
        );
		  
    END COMPONENT;
--===============================================================================	 

--============================ IPv4_RX ========================================
COMPONENT IPv4_RX
    PORT(
			-- system signals
         i_rx_clk               	: in  std_logic;  
         i_reset                	: in  std_logic;
         i_our_ip_address       	: in  std_logic_vector (31 downto 0);
				
         -- MAC layer RX inputs	
         i_mac_data_in          	: in  std_logic_vector (7 downto 0);  
         i_mac_data_in_valid    	: in  std_logic;  
         i_mac_data_in_last     	: in  std_logic;
          
         -- Outputs to udp layer              
         o_ip_dout               : out std_logic_vector(7 downto 0);
         o_ip_dout_rdy           : out std_logic;
         o_ip_data_last          : out std_logic;
                                 
         --Status Outputs        
			o_src_ip                : out std_logic_vector(31 downto 0);
         o_dst_ip                : out std_logic_vector(31 downto 0);
         o_data_len              : out std_logic_vector(15 downto 0);
         o_ip_rx_fragmantation     : out std_logic_vector(15 downto 0);  
         o_protocol              : out std_logic_vector(7 downto 0); 
         o_broadcast             : out std_logic;
			--error status
			o_no_ping_packet        : out std_logic;
			o_ip_rx_err_out         : out std_logic_vector (3 downto 0)
       );
    END COMPONENT;
--======================================================================================	 

begin

--========================= IPv4_TX ====================================================
inst_IPv4_TX :IPv4_TX 
generic map (	
             g_GENERATE_ARP_MODULE  => g_GENERATE_ARP_MODULE,
             g_DEFAULT_DST_MAC_ADDR => g_DEFAULT_DST_MAC_ADDR				 
			   )
PORT MAP (
         i_tx_clk              => i_tx_clk,
         i_reset               => i_reset,
                              
         -- IP header construction
			i_protocol         => i_ip_tx_protocol,
         i_data_length         => i_ip_tx_data_len,
         i_our_ip_addr         => i_ip_tx_src_ip,
         i_ip_tx_fragmantation => i_ip_tx_fragmantation,
         i_our_mac_addr        => i_ip_tx_src_mac,
         i_dst_ip_addr         => i_ip_tx_dst_ip,
                              
         -- IP inputs
			i_ip_tx_start         => i_ip_tx_start,
         o_ip_tx_ready         => o_ip_tx_rdy,
         i_data_in	          => i_ip_tx_din,
                             
         -- IP & ARP inouts
			o_lookup_req          => o_lookup_req,     
         o_lookup_ip           => o_lookup_ip,      
         i_lookup_mac_addr     => i_lookup_mac_addr,
         i_lookup_mac_got      => i_lookup_mac_got,
         i_lookup_mac_err      => i_lookup_mac_err, 
                              
         -- IP Outputs  
         i_mac_tready          => i_mac_tx_tready,      
         o_mac_tvalid          => o_mac_tx_tvalid,      
         o_mac_tlast           => o_mac_tx_tlast,       
         o_mac_tdata           => o_mac_tx_tdata,
         o_mac_tx_req          => o_mac_tx_req,      
         i_mac_tx_granted      => i_mac_tx_granted,

         o_ip_tx_err_out       => o_ip_tx_err_out
        );
--=====================================================================================		  

--========================= IPv4_RX ===================================================
inst_IPv4_RX :IPv4_RX PORT MAP (
          
			i_rx_clk              => i_rx_clk,
         i_reset               => i_reset,
         i_our_ip_address      => i_ip_tx_src_ip,                              
         
         i_mac_data_in         => i_mac_rx_tdata,      
         i_mac_data_in_valid   => i_mac_rx_tvalid,
         i_mac_data_in_last    => i_mac_rx_tlast,                             
         
         o_ip_dout             => o_ip_rx_dout,     
         o_ip_dout_rdy         => o_ip_rx_dout_rdy, 
         o_ip_data_last        => o_ip_rx_dout_last,
                                    
			o_src_ip              => o_ip_rx_src_ip,   
         o_dst_ip              => o_ip_rx_dst_ip,   
         o_data_len            => o_ip_rx_data_len, 
         o_ip_rx_fragmantation => o_ip_rx_fragmantation, 
         o_protocol            => o_ip_rx_protocol, 
         o_broadcast           => o_ip_rx_broadcast,
		  
			o_ip_rx_err_out       => o_ip_rx_err_out, 
			o_no_ping_packet      => o_no_ping_packet
        );
--=====================================================================================

end structural;