--****************************************************************************************
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;

library work;
use work.signal_Package.all;

entity ping is
	port (
		--	system signals
		i_tx_clk             		: in  	std_logic;  
		i_rx_clk             		: in  	std_logic;  
		i_reset              		: in  	std_logic;
	 
		-- 	MAC layer RX inputs
		i_mac_data_in        		: in  	std_logic_vector (7 downto 0);  
		i_mac_data_in_valid  		: in  	std_logic;  
		i_mac_data_in_last   		: in  	std_logic;
	 
		--	IP_RX output and status
		i_ip_rx_err_in	     			: in 	std_logic_vector(3 downto 0);
		i_no_ping_packet      		: in  	std_logic;
		
		Status_indc						: buffer std_logic_vector(7 downto 0):=x"BB";

		-- 	for transfer data to mac layer
		o_mac_tx_req         		: out 	std_logic;  
		i_mac_tx_granted     		: in  	std_logic;    
		i_mac_tready         		: in  	std_logic;  
		o_mac_tvalid         		: out 	std_logic;  
		o_mac_tlast          		: out 	std_logic;  
		o_mac_tdata          		: out 	std_logic_vector (7 downto 0)
	);
end ping;

architecture Behavioral of ping is

--======== FIFO for Saving Ping Data from Mac Layer ==========================================
component ping_fifo IS
  PORT (
	rst    				: IN  	STD_LOGIC;
	wr_clk 				: IN  	STD_LOGIC;
	rd_clk 				: IN  	STD_LOGIC;
	din    				: IN  	STD_LOGIC_VECTOR(7 DOWNTO 0);
	wr_en  				: IN  	STD_LOGIC;
	rd_en  				: IN  	STD_LOGIC;
	dout   				: OUT 	STD_LOGIC_VECTOR(7 DOWNTO 0);
	full   				: OUT 	STD_LOGIC;
	empty  				: OUT 	STD_LOGIC;
	valid  				: OUT 	STD_LOGIC
  );
END component;
--============================================================================================

--=========Sync FIFO for Convert RX_CLK Domain Signals to TX_CLK Domain Signals===============
component sync_fifo_ping IS
  PORT (
	rst    				: IN  	STD_LOGIC;
	wr_clk 				: IN  	STD_LOGIC;
	rd_clk 				: IN  	STD_LOGIC;
	din    				: IN  	STD_LOGIC_VECTOR(14 DOWNTO 0);
	wr_en  				: IN  	STD_LOGIC;
	rd_en  				: IN  	STD_LOGIC;
	dout   				: OUT 	STD_LOGIC_VECTOR(14 DOWNTO 0);
	full   				: OUT 	STD_LOGIC;
	empty  				: OUT 	STD_LOGIC;
	valid  				: OUT 	STD_LOGIC
  );
END component;
--===========================================================================================

--======== Ping Checksum Calculator =========================================================
component ping_cheksum_calc is
port
(
	i_clk           	: in  	std_logic;
	i_reset          	: in  	std_logic;
	i_din             	: in  	std_logic_vector(7 downto 0);
	i_din_rdy         	: in  	std_logic;
	i_start_calc  		: in  	std_logic;
	i_stop_calc    		: in  	std_logic;
	o_checksum_valid	: out 	std_logic;
	o_checksum    		: out 	std_logic_vector(15 downto 0)
);
end component;
--===========================================================================================

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



begin

---------------------------------------TX Data---------------------------------------
s_rd_en_fifo_ping   <=  (i_mac_tready or s_start_send)       when (st_PING_STATE=SEND_DATA) else '0';

--================== Swapping Address for Reply Ping Packet =========================
o_mac_tdata         <=  s_src_mac_ping(47 downto 40)   			when (s_rd_cnt=1)  else
                        s_src_mac_ping(39 downto 32)   			when (s_rd_cnt=2)  else
						s_src_mac_ping(31 downto 24)   			when (s_rd_cnt=3)  else
						s_src_mac_ping(23 downto 16)   			when (s_rd_cnt=4)  else
						s_src_mac_ping(15 downto 8)    			when (s_rd_cnt=5)  else
						s_src_mac_ping(7 downto 0)     			when (s_rd_cnt=6)  else
					            
						s_dst_mac_ping(47 downto 40)   			when (s_rd_cnt=7)  else
						s_dst_mac_ping(39 downto 32)   			when (s_rd_cnt=8)  else
						s_dst_mac_ping(31 downto 24)   			when (s_rd_cnt=9)  else
						s_dst_mac_ping(23 downto 16)   			when (s_rd_cnt=10) else
						s_dst_mac_ping(15 downto 8)    			when (s_rd_cnt=11) else
						s_dst_mac_ping(7  downto 0)    			when (s_rd_cnt=12) else
					            
						s_dst_ip_ping(31 downto 24)    			when (s_rd_cnt=27) else
						s_dst_ip_ping(23 downto 16)    			when (s_rd_cnt=28) else
						s_dst_ip_ping(15 downto 8)     			when (s_rd_cnt=29) else
						s_dst_ip_ping(7  downto 0)     			when (s_rd_cnt=30) else
								
						s_src_ip_ping(31 downto 24)    			when (s_rd_cnt=31) else
						s_src_ip_ping(23 downto 16)    			when (s_rd_cnt=32) else
						s_src_ip_ping(15 downto 8)     			when (s_rd_cnt=33) else
						s_src_ip_ping(7  downto 0)     			when (s_rd_cnt=34) else
								
						x"00"                           		when (s_rd_cnt=35) else
						s_checksum_data_out(15 downto 8)		when (s_rd_cnt=37) else
						s_checksum_data_out(7 downto 0) 		when (s_rd_cnt=38) else
						(s_dout_fifo_ping);
--===================================================================================								

--========================== Checksum Trig & Data ===================================
s_checksum_start_calc        <= '1'            when (s_wr_cnt=33)                else '0';
s_checksum_stop_calc         <= '1'            when (s_mac_data_in_last_d='1')   else '0';

s_checksum_data_in           <= x"00"          when (s_wr_cnt=34)                else
                                x"00"          when (s_wr_cnt=36)                else
                                x"00"          when (s_wr_cnt=37)                else
                                s_mac_data_in;
--===================================================================================

--======================== Delay in Rx_Data =========================================

p_delay:process(i_rx_clk)
begin
	if rising_edge(i_rx_clk) then
		s_mac_data_in_r         <= i_mac_data_in;
		s_mac_data_in_valid_r   <= i_mac_data_in_valid;
		s_mac_data_in_last_r    <= i_mac_data_in_last;
	end if;
end process p_delay;
--===================================================================================

--======================= Sync_fifo =================================================
s_ip_rx_in              	<= i_ip_rx_err_in & i_no_ping_packet & s_mac_data_in_last_r & s_mac_data_in_valid_r & s_mac_data_in_r;
s_ip_rx_err_in           	<= s_ip_rx_out(14 downto 11);
s_no_ping_data         		<= s_ip_rx_out(10);
s_mac_data_in_last       	<= s_ip_rx_out(9);
s_mac_data_in            	<= s_ip_rx_out(7 downto 0);
s_not_empty_sync_fifo    	<= not(s_empty_sync_fifo);

inst_sync_fifo_ping: sync_fifo_ping
  PORT map (
    rst      => i_reset,
    wr_clk   => i_rx_clk,
    rd_clk   => i_tx_clk,
    din      => s_ip_rx_in,
    wr_en    => s_mac_data_in_valid_r,
    rd_en    => s_not_empty_sync_fifo,
    dout     => s_ip_rx_out,
    full     => open,
    empty    => s_empty_sync_fifo,
    valid    => s_mac_data_in_valid
  );
--===================================================================================  

--======================== Acquire Src & Dst Address ================================
p_acquire_address:process(i_tx_clk)
begin
if rising_edge(i_tx_clk) then
  if ( s_mac_data_in_valid = '1') then
  case  s_wr_cnt   is
			--dst mac addr
			when  x"00" => 	s_dst_mac_ping(47 downto 40)    <= s_mac_data_in;
			when  x"01" => 	s_dst_mac_ping(39 downto 32)    <= s_mac_data_in;
			when  x"02" => 	s_dst_mac_ping(31 downto 24)    <= s_mac_data_in;
			when  x"03" => 	s_dst_mac_ping(23 downto 16)    <= s_mac_data_in;
			when  x"04" => 	s_dst_mac_ping(15 downto 8)     <= s_mac_data_in;
			when  x"05" => 	s_dst_mac_ping(7 downto 0)      <= s_mac_data_in;
	
			--src mac addr	
			when  x"06" => 	s_src_mac_ping(47 downto 40)    <= s_mac_data_in;
			when  x"07" => 	s_src_mac_ping(39 downto 32)    <= s_mac_data_in;
			when  x"08" => 	s_src_mac_ping(31 downto 24)    <= s_mac_data_in;
			when  x"09" => 	s_src_mac_ping(23 downto 16)    <= s_mac_data_in;
			when  x"0a" => 	s_src_mac_ping(15 downto 8)     <= s_mac_data_in;
			when  x"0b" => 	s_src_mac_ping(7 downto 0)      <= s_mac_data_in;
	
			--src ip addr	
			when  x"1a" => 	s_src_ip_ping(31 downto 24)     <= s_mac_data_in;
			when  x"1b" => 	s_src_ip_ping(23 downto 16)     <= s_mac_data_in;
			when  x"1c" => 	s_src_ip_ping(15 downto 8)      <= s_mac_data_in;
			when  x"1d" => 	s_src_ip_ping(7 downto 0)       <= s_mac_data_in;
	
			--dst ip addr	
			when  x"1e" => 	s_dst_ip_ping(31 downto 24)     <= s_mac_data_in;
			when  x"1f" => 	s_dst_ip_ping(23 downto 16)     <= s_mac_data_in;
			when  x"20" => 	s_dst_ip_ping(15 downto 8)      <= s_mac_data_in;
			when  x"21" => 	s_dst_ip_ping(7 downto 0)       <= s_mac_data_in;
		  
			when others => 	null;
	end case;
	end if;
end if;
end process p_acquire_address;
--===================================================================================

--================== Receive & Process & Transmit Ping Packets======================
p_recieve_transmit_ping_data:process(i_tx_clk)
begin
	if(rising_edge(i_tx_clk)) then
	s_wr_en_fifo_ping    	<= '0';
	s_rst_fifo_ping      	<= '0';
	s_start_send           	<= '0';
	s_mac_data_in_last_d 	<= s_mac_data_in_last;
	
	Status_indc					<=	x"A1";

		if (i_reset='1') then
			 
			s_rst_fifo_ping   	<= '1';  
			s_wr_cnt          	<= (others=>'0');  
			s_rd_cnt          	<= (others=>'0');
			
			o_mac_tlast       	<= '0';
			o_mac_tvalid      	<= '0';
			o_mac_tx_req      	<= '0'; 
			
			st_PING_STATE     	<= IDLE;
			Status_indc				<=	x"FF";

		else

			CASE st_PING_STATE IS
			--=============================================================================================
				WHEN IDLE =>
						Status_indc				<=	x"01";
						if (s_mac_data_in_valid = '1') then		         
							st_PING_STATE             	<= ACQUIRE_DATA;
							s_wr_en_fifo_ping 			<= '1';					
							s_din_fifo_ping   			<= s_mac_data_in;	
							s_wr_cnt            		<= s_wr_cnt+1;					
						 end if;
					
				----------------------------------------------------
				WHEN ACQUIRE_DATA =>
						Status_indc				<=	x"02";
						if (s_mac_data_in_valid = '1') then		         
							s_wr_en_fifo_ping 			<= '1';
							s_din_fifo_ping   			<= s_mac_data_in;	
							s_wr_cnt            		<= s_wr_cnt+1;	
							if (s_mac_data_in_last = '1') then           
								st_PING_STATE         	<= WAIT_CHN; 				  
							end if;
							if ((s_wr_cnt=34) and (s_mac_data_in/=x"08")) then
								s_rst_fifo_ping  		<= '1';
								st_PING_STATE    		<= WAIT_END;
							end if;		 		      
						 end if;
						  
						if (s_ip_rx_err_in/="0000") then		     
							s_rst_fifo_ping  			<= '1';
							st_PING_STATE           	<= WAIT_END;
							if (s_mac_data_in_last = '1') then           
								st_PING_STATE       	<= IDLE; 				  
							end if;
						end if;
						 
						if (s_no_ping_data='1') then
							s_rst_fifo_ping  			<= '1';
							st_PING_STATE            	<= WAIT_END;
							if (s_mac_data_in_last = '1') then           
								st_PING_STATE      		<= IDLE; 				  
							end if;
						end if;	 

				-----------------------------------------------------
				WHEN WAIT_END =>
						Status_indc				<=	x"03";
						if (s_mac_data_in_valid = '1') then 
							if (s_mac_data_in_last = '1') then
								s_wr_cnt           		<= (others=>'0');  
								s_rd_cnt           		<= (others=>'0');
								st_PING_STATE           <= IDLE;           
							end if;
						end if;
							
				-----------------------------------------------------	  		  
				WHEN WAIT_CHN => 
						Status_indc				<=	x"04";
						o_mac_tx_req      				<= '1';
						if (i_mac_tx_granted = '1') then                                                         
							st_PING_STATE      			<= SEND_DATA;
							s_start_send 				<= '1';
						end if;

				------------------------------------------------------
				WHEN SEND_DATA =>		
						Status_indc				<=	x"05";
						if (s_rd_cnt=0) then  			      
							s_rd_cnt            		<= s_rd_cnt+1;
							o_mac_tvalid        		<= '1';             						
						end if;
						---------------------------------
						if (i_mac_tready='1') then
							s_rd_cnt  					<= s_rd_cnt+1;
							if (s_rd_cnt=s_wr_cnt-1) then 
								o_mac_tlast          	<= '1';				  
							end if;
						end if;
						---------------------------------	  
						if (s_rd_cnt=s_wr_cnt) then				  
							s_rst_fifo_ping    			<= '1';
							s_wr_cnt             		<= (others=>'0');
							s_rd_cnt             		<= (others=>'0');
							o_mac_tx_req         		<= '0';				
							o_mac_tvalid         		<= '0';
							o_mac_tlast          		<= '0';			 
							st_PING_STATE       		<= IDLE;   						 					 
						end if;
				
			END CASE;
		end if;
	end if;
end process p_recieve_transmit_ping_data;	
--============================================================================================	  

--======== FIFO for Saving Ping Data from Mac Layer ==========================================
inst_ping_fifo :ping_fifo
PORT map 
(
	rst    				=> 	s_rst_fifo_ping,
	wr_clk 				=> 	i_tx_clk,
	rd_clk 				=> 	i_tx_clk,
	din    				=> 	s_din_fifo_ping,
	wr_en  				=> 	s_wr_en_fifo_ping,
	rd_en  				=> 	s_rd_en_fifo_ping,
	dout   				=> 	s_dout_fifo_ping,
	full   				=> 	open,
	empty  				=> 	open,
	valid  				=> 	open
);
--============================================================================================ 
  
--=========Sync FIFO for Convert RX_CLK Domain Signals to TX_CLK Domain Signals===============  
inst_ping_cheksum_calc:ping_cheksum_calc 
port map
(
	i_clk           	=> i_tx_clk,
	i_reset         	=> i_reset,
	i_din           	=> s_checksum_data_in,
	i_din_rdy       	=> s_mac_data_in_valid,
	i_start_calc    	=> s_checksum_start_calc,
	i_stop_calc     	=> s_checksum_stop_calc,
	o_checksum_valid	=> open,
	o_checksum      	=> s_checksum_data_out
);
--============================================================================================

end Behavioral;