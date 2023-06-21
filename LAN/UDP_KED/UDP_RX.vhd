library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;

library work;
use work.signal_Package.all;


entity UDP_RX is
generic (
			g_use_fragment			: boolean:= false --true 											
			);
    port (   
   -- system signals
   i_rx_clk      			: in  std_logic;  
   i_reset              : in  std_logic;
	
	-- IP layer RX inputs
   i_ip_data_in         : in  std_logic_vector (7 downto 0);  
   i_ip_data_in_valid   : in  std_logic;  
   i_ip_data_in_last    : in  std_logic;
	i_ip_protocol        : in  std_logic_vector (7 downto 0);  
	i_ip_src_ip          : in  std_logic_vector (31 downto 0);  
	i_fragmantation          : in  std_logic_vector (15 downto 0);  
	-- Outputs for application
	o_udp_dout           : buffer std_logic_vector(7 downto 0);
	o_udp_dout_rdy       : buffer std_logic;
	o_udp_dout_last      : buffer std_logic;
	
	
					
	o_src_ip             : out std_logic_vector(31 downto 0);
   o_src_port           : out std_logic_vector(15 downto 0);
   o_dst_port           : out std_logic_vector(15 downto 0);
   o_data_len           : out std_logic_vector(15 downto 0);	--application data length (udp data length-8)
	o_err_out	         : out std_logic_vector(3 downto 0)
   );                  
end UDP_RX;

architecture Behavioral of UDP_RX is
--================================= Constant ===========================================================
--Generate Block Conditional Constants
constant c_GENERATE_PING_MODULE             : boolean  := true;                                  --if Ping Block is not Used,Value is False
constant c_GENERATE_ARP_MODULE              : boolean  := true;                                  --if ARP  Block is not Used,Value is False
constant c_DEFAULT_DST_MAC_ADDR             : std_logic_vector (47 downto 0) := x"F46D04962225"; --if ARP Block is not Used,Copy PC MAC Address to This Value 	


--Application Layer Data Length
constant c_PACKET_LENGTH                    : std_logic_vector (15 downto 0):= x"05c0";          --1472 (Maximum Application Layer Packet Length)
constant c_udp_tx_src_ip                    : std_logic_vector (31 downto 0):= x"C0A86403";      --192.168.100.3(FPGA IP Adress)
constant c_udp_tx_dst_ip                    : std_logic_vector (31 downto 0):= x"C0A86402";      --192.168.100.2(PC IP Address)
constant c_udp_tx_protocol                  : std_logic_vector (7 downto 0) := x"11";            --udp Protocol
constant c_udp_tx_src_mac                   : std_logic_vector (47 downto 0):= x"112233445566";  --FPGA MAC Address
constant c_udp_tx_checksum                  : std_logic_vector (15 downto 0):= x"0000";          --udp Checksum(Value For This Constant is not Importanat)
constant c_udp_tx_src_port                  : std_logic_vector (15 downto 0):= x"0401";          --udp Src Port(Value For This Constant is not Importanat)
constant c_udp_tx_dst_port                  : std_logic_vector (15 downto 0):= x"0FF5";          --udp Dst Port(Value For This Constant is not Importanat)


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


--================================ udp Signals =========================================================
    -------- for transfer Rx data from IP to udp layer----------------
	signal s_ip_rx_dout           :  std_logic_vector(7 downto 0);
	signal s_ip_rx_dout_rdy       :  std_logic;
	signal s_ip_rx_dout_last      :  std_logic;	
	
	-------- for transfer Rx status data from IP to udp layer---------
	signal s_ip_rx_src_ip         :  std_logic_vector(31 downto 0);
    signal s_ip_rx_dst_ip         :  std_logic_vector(31 downto 0);
    signal s_ip_rx_data_len       :  std_logic_vector(15 downto 0); 
    signal s_ip_rx_protocol       :  std_logic_vector(7 downto 0); 
    signal s_ip_rx_broadcast      :  std_logic;
    signal s_ip_rx_err_out_udp        :  std_logic_vector (3 downto 0);
    signal s_ip_tx_err_out_udp        :  std_logic_vector (3 downto 0);
    signal s_arp_rx_err_out_udp       :  std_logic_vector (3 downto 0);
	
	-------- for transfer Tx data from udp to IP layer---------------
	signal s_ip_tx_start          :  std_logic; 
	signal s_ip_tx_rdy            :  std_logic; 
	signal s_ip_tx_din	          :  std_logic_vector(7 downto 0); 
	
	-------- for transfer Tx header data from udp to IP layer--------
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












--============================ udp RX Signals ===========================================================================
  type t_rx_udp_state_type is  (IDLE, udp_HDR, USER_DATA, WAIT_END); 
  signal st_RX_udp_STATE         : t_rx_udp_state_type:=IDLE;
  signal s_cnt_udp_rx         : std_logic_vector (15 downto 0):=x"0001";  
 
  signal s_src_ip_udp_rx  : std_logic_vector (31 downto 0):=(others=>'0');
  signal s_src_port       : std_logic_vector (15 downto 0):=(others=>'0');   
  signal s_dst_port       : std_logic_vector (15 downto 0):=(others=>'0'); 
  signal s_data_len_udp_rx       : std_logic_vector (15 downto 0):=(others=>'0'); 
  signal s_err_out        : std_logic_vector (3 downto 0) :=(others=>'0');
  
	signal	s_udp_Seq_Num			: std_logic_vector(31 downto 0);	
	signal	s_udp_Ack_Num			: std_logic_vector(31 downto 0);	
	signal	s_udp_offset 			: std_logic_vector(7 downto 0)	;
	signal	s_udp_udp_Flag 		: std_logic_vector(7 downto 0)	;
	signal	s_udp_Window			: std_logic_vector(15 downto 0)	;
	signal	s_udp_checksum			: std_logic_vector(15 downto 0)	;
	signal	s_udp_Urg_point		: std_logic_vector(15 downto 0) ;
	
 --======================================================================================================================= 
  
  
  
  
  
  

  
  
  
  
 --============================ udp TX Signals =============================================================================
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

signal   udp_header_len : integer:=8;
constant udp_type_protocol : std_logic_vector(7 downto 0):=x"11";

signal    EnableTlast : std_logic:='1';
signal    s_udp_dout_last : std_logic:='0';

signal    first_FG_flag, other_FG_flag, last_FG_flag : std_logic:='0';

signal    dntFragSet : std_logic:='0';
signal    MoreFrag: std_logic:='0';
signal    offset_fragment       :  std_logic_vector(12 downto 0):=(others=>'0');

signal    s_ip_data_len_pack       :  std_logic_vector(15 downto 0):=(others=>'0');

signal    rst_cntr_FG            : std_logic:='0';
signal    s_cntr_FG_timout       :  std_logic_vector(23 downto 0):=(others=>'0');

type paket_type_t is (Normal, first_FG, other_FG, last_FG);
signal  paket_type:paket_type_t;

signal	CheckSum_calc_en		: std_logic:= '0'	;
signal	rst_chk_sum 			: std_logic:= '0'	;
signal	sec_cal_sum 			: std_logic:= '0'	;
signal	Data_sum				: std_logic_vector(15 downto 0)	;
signal	CheckSum_data		: std_logic_vector(31 downto 0)	;
signal	CheckSum_data_r		: std_logic_vector(31 downto 0)	;

signal	s_chksum_udp_rx		: std_logic_vector(31 downto 0)	;
--========================================================================================================================= 


  
---------------------------------------------------------------------
begin


dntFragSet          <=  i_fragmantation(14) When g_use_fragment else    '1';
MoreFrag            <=  i_fragmantation(13);
offset_fragment     <=  i_fragmantation(12 downto 0);

paket_type          <=  Normal      When (dntFragSet = '1' OR (dntFragSet = '0' AND MoreFrag = '0'  AND offset_fragment = 0))   else
                        first_FG    When (dntFragSet = '0' AND MoreFrag = '1' AND offset_fragment = 0)   else
                        other_FG    When (dntFragSet = '0' AND MoreFrag = '1' AND offset_fragment /= 0)   else
                        last_FG     When (dntFragSet = '0' AND MoreFrag = '0' AND offset_fragment /= 0)   ;


--udp_header_len      <=  8 When (paket_type = Normal) else 
--                        8 When (paket_type = first_FG) else 
--                        0;
udp_header_len      <=  8;
--========================================================================================================================= 




--================ Status Outputs ===============================================================================
  o_src_ip          <= s_src_ip_udp_rx   ;
  o_src_port        <= s_src_port ;
  o_dst_port        <= s_dst_port ;
  o_data_len        <= s_data_len_udp_rx ;
  o_err_out         <= s_err_out ;
  
  o_udp_dout_last   <=  s_udp_dout_last AND EnableTlast;
--===============================================================================================================
--
--Data_sum(7 downto 0)    <=    i_ip_data_in  When sec_cal_sum= '1' else  (others => '0') When rst_chk_sum ='1';
--Data_sum(15 downto 8)   <=    i_ip_data_in  When sec_cal_sum= '0' else  (others => '0') When rst_chk_sum ='1';
--CheckSum_data           <=    CheckSum_data_r + Data_sum;

  
--================ Process for Recieve udp Data from IP Layer =====================================================  
p_recieve_udp_data:process(i_rx_clk)
begin
if(rising_edge(i_rx_clk)) then
if (i_reset='1') then
   st_RX_udp_STATE           	<= IDLE;
	s_cnt_udp_rx           		<= x"0001";
	--status
	s_src_ip_udp_rx           	<= (others => '0');
   s_src_port         			<= (others => '0');
	s_dst_port         			<= (others => '0');
   s_data_len_udp_rx         	<= (others => '0');
	s_err_out          			<= (others => '0');

	--output data for application
	o_udp_dout           		<= (others => '0');
   o_udp_dout_rdy       		<= '0' ;
   s_udp_dout_last      		<= '0' ;
else

	o_udp_dout           		<= (others => '0');
   o_udp_dout_rdy       		<= '0' ;
   s_udp_dout_last      		<= '0' ;
--   if (sec_cal_sum = '1') then
--        CheckSum_data_r              <=  CheckSum_data;
--   end if;
-----------------------------------------------
    if (CheckSum_calc_en = '1') then
        sec_cal_sum					<=     not sec_cal_sum;
        if (sec_cal_sum= '1') then
            Data_sum(7 downto 0)    <=    i_ip_data_in;
        else
            CheckSum_data           <=    CheckSum_data + Data_sum;
            Data_sum(15 downto 8)   <=    i_ip_data_in ;
        end if;
    end if;
    --------------------

   CASE st_RX_udp_STATE IS
      --************************************************************************************************************************************
	  WHEN IDLE =>	
	  
--	  s_cnt_udp_rx           	<= x"0001";
	  sec_cal_sum               <= '0';
--	  s_src_ip_udp_rx          <= (others => '0');
--     s_src_port         		<= (others => '0');
--	  s_dst_port         		<= (others => '0');
--     s_data_len_udp_rx        <= (others => '0');
	  s_err_out          		<= (others => '0');
	   
        
        if (rst_cntr_FG = '1') then
            s_cntr_FG_timout        <=  (others => '0');
        else
            s_cntr_FG_timout        <=  s_cntr_FG_timout + 1;
        end if;
        
        rst_cntr_FG             <=  '0';
            
        if (s_cntr_FG_timout = 125e5) then
            rst_cntr_FG             <=  '1';
            first_FG_flag           <=  '0'; 
            other_FG_flag           <=  '0'; 
            last_FG_flag            <=  '0'; 
            s_err_out               <= x"6";
        end if;
        
        
      ------------- Checking Type & Loading Source IP ------------------------------------------
		case paket_type is	
		  When    Normal  =>	        
		      EnableTlast                  <= '1'; 
            if (i_ip_data_in_valid = '1') then		         
              st_RX_udp_STATE            	<= WAIT_END;
              s_err_out                  	<= x"1";
                if(i_ip_protocol=udp_type_protocol) then
                    --status
                    s_src_ip_udp_rx        	<= i_ip_src_ip;
                    s_src_port(15 downto 8) <= i_ip_data_in;	
                    -------
--                    s_cnt_udp_rx            <= s_cnt_udp_rx+1;
                    s_cnt_udp_rx           	<= x"0002";
                    s_err_out               <= x"0";
                    first_FG_flag           <=  '0'; 
                    other_FG_flag           <=  '0'; 
                    last_FG_flag            <=  '0'; 	
--                    CheckSum_data_r         <=  (others => '0');	
--                    rst_chk_sum             <=  '1';	 
                    st_RX_udp_STATE         <= udp_HDR;
                end if;
            end if;
          
          When    first_FG  =>	         
            EnableTlast                  <= '0'; 
            if (i_ip_data_in_valid = '1') then		         
              st_RX_udp_STATE            	<= WAIT_END;
              s_err_out                  	<= x"1";
                if(i_ip_protocol=udp_type_protocol) then
                    --status
                    s_src_ip_udp_rx        	<= i_ip_src_ip;
                    s_src_port(15 downto 8) <= i_ip_data_in;	
                    -------
--                    s_cnt_udp_rx            <= s_cnt_udp_rx+1;
                    s_cnt_udp_rx           	<= x"0002";
                    s_err_out               <= x"0";			
                    first_FG_flag           <=  '1'; 
                    other_FG_flag           <=  '0'; 
                    last_FG_flag            <=  '0'; 
                    rst_cntr_FG             <=  '1';
--                    CheckSum_data_r         <=  (others => '0');
--                    rst_chk_sum             <=  '1';
                    st_RX_udp_STATE         <= udp_HDR;
                end if;
            end if;
          
          When    other_FG  =>	         
            EnableTlast                  <= '0'; 
            if (i_ip_data_in_valid = '1') then		         
              st_RX_udp_STATE            	<= WAIT_END;
              s_err_out                  	<= x"1";
                if(i_ip_protocol=udp_type_protocol and (first_FG_flag = '1' or other_FG_flag='1')) then
                    --status
                    o_udp_dout       <= i_ip_data_in;
                    o_udp_dout_rdy   <= i_ip_data_in_valid;
                    s_udp_dout_last  <= i_ip_data_in_last;
                    s_cnt_udp_rx            <= s_cnt_udp_rx+1;
                    s_err_out               <= x"0";			
                    first_FG_flag           <=  '0'; 
                    other_FG_flag           <=  '1'; 
                    last_FG_flag            <=  '0'; 
                    rst_cntr_FG             <=  '1'; 
                    st_RX_udp_STATE         <= USER_DATA;
                end if;
            end if;
          
          When    last_FG  =>	         
            EnableTlast                  <= '1'; 
            if (i_ip_data_in_valid = '1') then		         
              st_RX_udp_STATE            	<= WAIT_END;
              s_err_out                  	<= x"1";
                if(i_ip_protocol=udp_type_protocol and other_FG_flag = '1') then
                    --status
                    o_udp_dout       <= i_ip_data_in;
                    o_udp_dout_rdy   <= i_ip_data_in_valid;
                    s_udp_dout_last  <= i_ip_data_in_last;
                    s_cnt_udp_rx            <= s_cnt_udp_rx+1;
                    s_err_out               <= x"0";	
                    first_FG_flag           <=  '0'; 
                    other_FG_flag           <=  '0'; 
                    last_FG_flag            <=  '1'; 
                    rst_cntr_FG             <=  '1';		 
                    st_RX_udp_STATE         <= USER_DATA;
                end if;
            end if;
          
          
	  end case;

				  
     --************************************************************************************************************************************
	  WHEN udp_HDR =>
--	           rst_chk_sum                     <=  '0';
	  	       if (i_ip_data_in_valid = '1') then		        
					s_cnt_udp_rx  				<= s_cnt_udp_rx+1;	
				   
					 if(s_cnt_udp_rx= 2) then
						s_src_port(7 downto 0) 	<= i_ip_data_in;
					 end if;  
						
					 if(s_cnt_udp_rx= 3) then
						s_dst_port(15 downto 8) <= i_ip_data_in;
					 end if; 
						
					 if(s_cnt_udp_rx= 4) then
						s_dst_port(7 downto 0) 	<= i_ip_data_in;
					 end if; 
						
--					if (s_cnt_udp_rx = x"0005") then 	 s_udp_Seq_Num(31 downto 24)			 <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"0006") then 	 s_udp_Seq_Num(23 downto 16)			 <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"0007") then 	 s_udp_Seq_Num(15 downto 8)			 <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"0008") then 	 s_udp_Seq_Num(7 downto 0)			    <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"0009") then 	 s_udp_Ack_Num(31 downto 24)			 <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"000A") then 	 s_udp_Ack_Num(23 downto 16)			 <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"000B") then 	 s_udp_Ack_Num(15 downto 8)			 <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"000C") then 	 s_udp_Ack_Num(7 downto 0)			    <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"000D") then 	 s_udp_offset (7 downto 0)			    <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"000E") then 	 s_udp_udp_Flag (7 downto 0)			 <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"000F") then 	 s_udp_Window(15 downto 8)			    <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"0010") then 	 s_udp_Window(7 downto 0)			    <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"0011") then 	 s_udp_checksum(15 downto 8)			 <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"0012") then 	 s_udp_checksum(7 downto 0)			 <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"0013") then 	 s_udp_Urg_point(15 downto 8)			 <= i_ip_data_in;		end if;
--					if (s_cnt_udp_rx = x"0014") then 	 s_udp_Urg_point(7 downto 0)			 <= i_ip_data_in;		end if;
--					
--					if (s_cnt_udp_rx = x"0014") then	
--						st_RX_udp_STATE 						<= USER_DATA;
--					end if;


					 
					 if(s_cnt_udp_rx= 5) then
						s_data_len_udp_rx(15 downto 8) <= i_ip_data_in;
						s_data_len_udp_rx(7 downto 0)  <= (others=>'0');
				    end if; 
						
					 if(s_cnt_udp_rx= 6) then
						s_data_len_udp_rx <= ((s_data_len_udp_rx(15 downto 8) & i_ip_data_in) - udp_header_len);
						if ((s_data_len_udp_rx(15 downto 8) & i_ip_data_in) < udp_header_len) then
							s_err_out     			<= x"3";
							st_RX_udp_STATE     	<= WAIT_END;
					   end if;
				    end if; 
				    
				    if(s_cnt_udp_rx= 7) then
                        s_chksum_udp_rx(15 downto 8) <= i_ip_data_in;
                        s_chksum_udp_rx(7 downto 0)  <= (others=>'0');
                    end if; 
                    if(s_cnt_udp_rx= 8) then
                        s_chksum_udp_rx(7 downto 0) <= i_ip_data_in;
                    end if; 
                                        
				    ---------- Cheking Type ------------------------------         
	             if(s_cnt_udp_rx= 8) then  
						st_RX_udp_STATE 			<= USER_DATA;
						CheckSum_calc_en            <=    '1';
						rst_chk_sum                 <=  '0';
						if (s_data_len_udp_rx=x"0000") then
							st_RX_udp_STATE  		<= WAIT_END;
						end if;				   
				    end if; 					
					 ------------------------------------------------------
					 if ( i_ip_data_in_last = '1') then           
						s_cnt_udp_rx         	<= x"0001";
						--status
--						s_src_ip_udp_rx         <= (others => '0');
--						s_src_port       			<= (others => '0');
--						s_dst_port       			<= (others => '0');
--						s_data_len_udp_rx       <= (others => '0');
						s_err_out        			<= x"2";
						st_RX_udp_STATE         <= IDLE;
					 end if;
					------------------------------------------------------
           end if;
		   
		--************************************************************************************************************************************
      WHEN USER_DATA =>	
				o_udp_dout       <= i_ip_data_in;
				o_udp_dout_rdy   <= i_ip_data_in_valid;
                s_udp_dout_last  <= i_ip_data_in_last;
	 
				if (i_ip_data_in_valid = '1') then
					-----------------------------------------------
					s_cnt_udp_rx  <= s_cnt_udp_rx+1;
--					if (s_cnt_udp_rx = (s_data_len_udp_rx+8)) then
--						s_udp_dout_last  			<= '1';
--						st_RX_udp_STATE       	<= WAIT_END;
--               end if;
					---------------------------
					if (i_ip_data_in_last = '1') then           
--						s_cnt_udp_rx       		<= x"0001";
						st_RX_udp_STATE       	<= IDLE;
						CheckSum_calc_en        <=    '0';
						
						if (s_cnt_udp_rx /= (s_data_len_udp_rx+udp_header_len) and EnableTlast='1') then
                             s_err_out        			<= x"5";
                        end if;
						
						--status
--						s_src_ip_udp_rx       	<= (others => '0');
--                  s_src_port     			<= (others => '0');
--                  s_dst_port     			<= (others => '0');
--						s_data_len_udp_rx     	<= (others => '0');
						--error status
--						if (s_cnt_udp_rx < (s_data_len_udp_rx+8)) then
--							s_err_out  				<= x"2";
--                  end if;						
					end if;
					------------------------------------------------				 
             end if;
				 
		--*******************************************************************************************************************************************
      WHEN WAIT_END =>
           if ( i_ip_data_in_valid = '1') then 
              if (i_ip_data_in_last = '1') then
--					s_cnt_udp_rx         <= x"0001";
					st_RX_udp_STATE      <= IDLE;
					--status
--					s_src_ip_udp_rx      <= (others => '0');
--               s_src_port       		<= (others => '0');
--               s_dst_port       		<= (others => '0');
--					s_data_len_udp_rx    <= (others => '0');
					--error status
					s_err_out        		<= x"0";				           
              end if;
		   end if;	
			
	  END CASE;
	  
	end if;
  end if;	 
  end process p_recieve_udp_data;
--===============================================================================================================  
--   my_ila_Phy : entity work.ila_0
-- PORT MAP (
--     clk                   => i_rx_clk,

--     probe0(31 downto 0)    => (others => '0'),    
     
--     probe0(39 downto 32)   => i_ip_protocol,    
--     probe0(40)             => i_ip_data_in_last   ,
--     probe0(41)             => i_ip_data_in_valid   ,
--     probe0(49 downto 42)   => i_ip_data_in,
     
--     probe0(57 downto 50)    => o_udp_dout,
--     probe0(58)              => o_udp_dout_rdy,
--     probe0(59)              => o_udp_dout_last,
    
--     probe0(255 downto 60) => (others => '0')
-- );
 

 
  end Behavioral;