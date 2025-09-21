
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.std_logic_unsigned.all;
use IEEE.STD_LOGIC_ARITH.ALL;



entity ping_pong_fifo2_KED is
generic (
			g_PACKET_LENGTH			: std_logic_vector(15 downto 0):= x"05c0"; --1472(maximum UDP Packet Length)												
			g_use_fragment			: boolean:= false 											
			);
port
(
i_clk            : in  std_logic; --Tx_Clk (125MHz)
i_rst            : in  std_logic;


i_din            : in  std_logic_vector(8-1 downto 0); 
i_din_valid      : in  std_logic:='0'; 
i_din_last       : in  std_logic:='0'; 

--Read Clock
o_dout_len       : out std_logic_vector(15 downto 0):=(others=>'0');
o_start_out      : out std_logic:='0'; --Start Pulse for Ethernet 1g Block
i_rd_en          : in  std_logic;
o_dout           : out std_logic_vector(8-1 downto 0):=(others=>'0');
o_fragment       : out std_logic_vector(16-1 downto 0):=x"4000";

fifo_ready       : out std_logic;
full             : out std_logic;
o_wr_cnta        : out std_logic_vector(15 downto 0):=(others=>'0');
o_wr_cntb        : out std_logic_vector(15 downto 0):=(others=>'0')


);
end ping_pong_fifo2_KED;

architecture Behavioral of ping_pong_fifo2_KED is

--==============================================================================================
COMPONENT data_fifo_KED
  PORT (
    clk : IN STD_LOGIC;
    srst : IN STD_LOGIC;
    din : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    wr_en : IN STD_LOGIC;
    rd_en : IN STD_LOGIC;
    dout : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    full : OUT STD_LOGIC;
    empty : OUT STD_LOGIC;
    valid : OUT STD_LOGIC;
    data_count : OUT STD_LOGIC_VECTOR(10 DOWNTO 0);
    prog_full : OUT STD_LOGIC
  );
END COMPONENT;


COMPONENT Arr_fifo_KED
  PORT (
    clk : IN STD_LOGIC;
    srst : IN STD_LOGIC;
    din : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    wr_en : IN STD_LOGIC;
    rd_en : IN STD_LOGIC;
    dout : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    full : OUT STD_LOGIC;
    empty : OUT STD_LOGIC;
    valid : OUT STD_LOGIC
  );
END COMPONENT;
--========================== Signals ===========================================================

--Data fifo Signals
signal   s_dina                  :std_logic_vector(8-1 downto 0):=(others=>'0');
signal   s_dinb                  :std_logic_vector(16-1 downto 0):=(others=>'0');
signal   s_douta                 :std_logic_vector(8-1 downto 0);
signal   s_doutb                 :std_logic_vector(16-1 downto 0);
signal   s_wr_en_a               :std_logic:='0';
signal   s_wr_en_b               :std_logic:='0';
signal   s_rd_ena                :std_logic:='0';
signal   s_rd_enb                :std_logic:='0';
signal   s_rst_a                 :std_logic:='1';
signal   s_rst_b                 :std_logic:='1';
signal   s_empty_a               :std_logic;
signal   s_empty_b               :std_logic;


--Control Signals
signal   s_line_busy_for_a       :std_logic:='1';
signal   s_line_busy_for_b       :std_logic:='1';

signal   s_wr_cnta               :std_logic_vector(16-1 downto 0):=(others=>'0');
signal   s_wr_cnta_r1            :std_logic_vector(16-1 downto 0):=(others=>'0');
signal   s_wr_cnta_r2            :std_logic_vector(16-1 downto 0):=(others=>'0');
signal   s_wr_cnta_r3            :std_logic_vector(16-1 downto 0):=(others=>'0');
signal   s_wr_cntb               :std_logic_vector(16-1 downto 0):=(others=>'0');
signal   s_wd_cnt                :std_logic_vector(16-1 downto 0):=(others=>'0'); --Watch Dog Timer
signal   s_req_cnt               :std_logic_vector(5-1 downto 0):=(others=>'0'); --Watch Dog Timer

signal   s_start_out             :std_logic:='0';
signal   delay_cnt               :std_logic_vector(8-1 downto 0):=(others=>'0');

signal   s_prog_full_a			 :std_logic;
signal   s_prog_full_b			 :std_logic;

signal   s_full_a				:std_logic;
signal   s_full_b				:std_logic;

--type     t_state                 is (reset , idle , wr_in_a_rd_of_b , wait_4_free_line_from_b , wr_in_b_rd_of_a , wait_4_free_line_from_a);
--signal   st_state                : t_state:=reset;

signal  reset                    : std_logic:='1';
signal  idle                     : std_logic:='0';
signal  wr_in_a_rd_of_b          : std_logic:='0';
signal  wait_4_free_line_from_b  : std_logic:='0';
signal  wr_in_b_rd_of_a          : std_logic:='0';
signal  wait_4_free_line_from_a  : std_logic:='0';

signal  s_dout_len       :  std_logic_vector(15 downto 0):=(others=>'0');
signal  LED_state       :  std_logic_vector(7 downto 0):=(others=>'1');

signal  s_fifo_valida  : std_logic:='0';
signal  s_fifo_validb  : std_logic:='0';

signal  prog_full1  : std_logic:='0';
signal  prog_full2  : std_logic:='0';

signal  s_mac_ready  : std_logic:='0';

type General_State  is (St_init,St_idle,St_0,St_1,St_1_2,St_2,St_3,St_4,St_5,St_6,St_7);
signal  St_ctrl: General_State:=St_idle;

constant  FrRSVD  : std_logic:='0';
signal    dntFragSet : std_logic:='0';
signal    MoreFrag: std_logic:='0';

signal    s_wd_cnt_rst: std_logic:='0';

signal  offset_fragment         :  std_logic_vector(12 downto 0):=(others=>'0');
signal  s_udp_header_len        :  std_logic_vector(3 downto 0):=x"1";
signal  s_fragment              :  std_logic_vector(16-1 downto 0):=x"4000";


signal    rdySetLast            : std_logic:='0';
signal    s_wr_en_b_r0          : std_logic:='0';
signal    s_wr_en_b_r1          : std_logic:='0';
signal    s_dinb_r0             :std_logic_vector(16-1 downto 0):=(others=>'0');

signal    remain_len             :std_logic_vector(16-1 downto 0):=(others=>'0');

signal    data_fifo_cnt         :std_logic_vector(10 downto 0):=(others=>'0');
signal    LastPacket            : std_logic:='0';

signal    cntr_frag              :std_logic_vector(7 downto 0):=(others=>'0');
signal    Num_frag              :std_logic_vector(7 downto 0):=(others=>'0');
signal    Num_frag_rst          : std_logic:='0';
signal    remainPacket          : std_logic:='0';
signal    readyFornext          : std_logic:='1';
signal    cntr_wait             :std_logic_vector(7 downto 0):=(others=>'0');

begin


o_dout_len      <= s_dout_len;
o_start_out     <= s_start_out;

o_fragment      <=  s_fragment When g_use_fragment  else    x"4000";

s_mac_ready     <= i_rd_en;
s_rd_ena        <= s_mac_ready;
o_dout          <= s_douta;


--================= Process for Continues Writing and Discontinues Reading Data =================
process(i_clk)
begin
if rising_edge(i_clk) then
       s_rst_a      <= i_rst;
      
       fifo_ready   <=  not(prog_full1);-- and readyFornext;
       s_dina       <= i_din;
       s_wr_en_a    <= i_din_valid;	
--       s_wr_cnta_r1 <=  s_wr_cnta;
--       s_wr_cnta_r2 <=  s_wr_cnta_r1;
       
--       s_wr_en_b_r0 <=  i_din_last;
--       s_wr_en_b_r1 <=  s_wr_en_b_r0;
----       s_wr_cnta_r3 <=  s_wr_cnta_r2;
       
----       if (s_wr_cnta>=g_PACKET_LENGTH-1) then
----            s_dinb       <= s_wr_cntb - g_PACKET_LENGTH + 1;
----       else
--            s_dinb       <= s_wr_cntb + 1;
----       end if;
       
       s_dinb       <= s_wr_cntb + 1;
       s_wr_en_b    <= i_din_last;
--       s_dinb       <= "00000" & data_fifo_cnt;
--       s_wr_en_b    <=  s_wr_en_b_r1;
       
--       if (s_wr_cnta < (g_PACKET_LENGTH & '0' )-1 and rdySetLast =  '1') then
--        s_dinb      <=  s_dinb_r0;
--        s_wr_en_b   <=  s_wr_en_b_r0;
--        s_wr_en_b_r0  <=  '0';
--        rdySetLast  <=  '0';
--       else
--        s_wr_en_b   <=  '0';
--       end if;
       
--       if (i_din_last = '1') then
--            s_dinb_r0       <= s_wr_cntb + 1;
--            s_wr_en_b_r0    <= '1'; 
--            rdySetLast      <=  '1';
--       end if;
                 
       if (s_rst_a = '1') then
           s_wr_cnta   <=  (others => '0');
           s_wr_cntb   <=  (others => '0');
           s_wd_cnt    <=  (others => '0');
           Num_frag    <=  (others => '0');
           Cntr_frag   <=  (others => '0');
           remainPacket<=   '0';
           readyFornext<= '1';
           dntFragSet  <= '1';
           MoreFrag    <= '0';
           offset_fragment  <= (others => '0');
           s_fragment       <=  x"4000";
           s_udp_header_len <=  x"1";
           St_ctrl     <= st_idle;
--        elsif (i_din_valid = '1') then
--            if (s_wd_cnt_rst = '1') then
--               s_wr_cnta  <= s_wr_cnta - s_dout_len +1;
--            else
--                s_wr_cnta  <= s_wr_cnta + 1;
--            end if;
--        elsif (s_wd_cnt_rst = '1') then
--               s_wr_cnta  <= s_wr_cnta - s_dout_len;
        end if;
        
        if (i_din_last = '1') then
            s_wr_cntb   <=  (others => '0');
            readyFornext<= '0';
--            if (data_fifo_cnt >= g_PACKET_LENGTH-1 ) then
--                remainPacket    <= '1';
--            end if;
        else
            if (i_din_valid = '1') then
                if (s_wr_cntb >= g_PACKET_LENGTH-1) then
                    s_wr_cntb  <= s_wr_cntb - g_PACKET_LENGTH + 1;
--                    Num_frag   <= Num_frag+ 1;
                else
                    s_wr_cntb  <= s_wr_cntb + 1;
                end if;
            end if;
        end if;
            
		if (s_wd_cnt_rst = '1') then
           s_wd_cnt    <= (others => '0');
        elsif (s_mac_ready = '1') then
           s_wd_cnt    <= s_wd_cnt + 1;
        end if;
        
--        if (Num_frag_rst = '1') then
--           Num_frag    <=  (others => '0');
--        end if;
        
--        if (readyFornext = '0') then
--            cntr_wait   <=  cntr_wait + 1;
--        else
--            cntr_wait   <=  (others => '0');
--        end if;
        
--        if (cntr_wait = 100) then
--            readyFornext<=  '1';
--        end if;
        
        if (s_wd_cnt = s_dout_len -1) then
            s_wd_cnt_rst    <= '1';
        end if;

--         Num_frag_rst           <=  '0';   
				 
        case    St_ctrl is  
            When    st_idle =>
                LED_state      <=   x"FF";
                s_start_out    <=   '0';
                s_wd_cnt_rst   <= '0';
                
--                if (remainPacket   = '1') then
--                    St_ctrl     <= st_0;
--                    remainPacket<= '0';
--                els
                if (s_empty_b = '0') then
                   s_rd_enb    <= '1';
                   St_ctrl     <= st_1;
--                elsif (Cntr_frag < Num_frag) then
--                elsif (s_wr_cnta_r2 >= g_PACKET_LENGTH-1) then
                elsif (data_fifo_cnt >= g_PACKET_LENGTH-1) then
                   St_ctrl     <= st_0;
                end if;
                
              When    st_0 =>   -- Befor LastPack
                LED_state       <=  x"00";
                s_start_out     <=  '1';
                s_udp_header_len<=  x"0";
                s_fragment      <= "001" & offset_fragment;--FrRSVD & dntFragSet & MoreFrag & offset_fragment
                offset_fragment <=  offset_fragment + g_PACKET_LENGTH(15 downto 3)+s_udp_header_len;
                s_dout_len      <= g_PACKET_LENGTH;
                Cntr_frag       <= Cntr_frag + 1;
                St_ctrl         <=  st_2;
                
              When    st_1 =>
                LED_state      <=   x"01";
                s_rd_enb       <= '0';
                Cntr_frag      <= (others => '0');
--                Num_frag_rst   <= '1';
                if (s_fifo_validb = '1') then
--                   if (s_doutb >= g_PACKET_LENGTH-1 ) then
--                        remain_len  <= s_doutb - g_PACKET_LENGTH;
--                        LastPacket  <= '1';
--                        St_ctrl     <= st_0;
--                   else
--                        St_ctrl     <= st_1_2;
--                        s_dout_len  <= s_doutb; 
--                   end if;
                   St_ctrl     <= st_1_2;
                   s_dout_len  <= s_doutb;
               end if;
               
               When    st_1_2 =>  --LastPack
                  LED_state         <=  x"12";
                  s_start_out       <= '1';
                  s_udp_header_len  <=  x"1";
                  s_fragment        <= "000" & offset_fragment;--FrRSVD & dntFragSet & MoreFrag & offset_fragment
                  offset_fragment   <=  (others => '0');
--                  s_dout_len      <= s_doutb; 
                  St_ctrl           <=  st_2;
                               
              When    st_2 =>
                 LED_state      <=   x"02";
                 if (s_mac_ready = '1') then
                    St_ctrl     <= st_3;
                    if (s_wd_cnt = s_dout_len -1) then
                        s_wd_cnt_rst    <= '1';
                        s_start_out <=   '0';
                        St_ctrl     <= st_4;
--                        if (i_din_valid = '1') then
--                            s_wr_cnta  <= s_wr_cnta - s_dout_len +1;
--                        else
--                            s_wr_cnta  <= s_wr_cnta - s_dout_len;
--                        end if;
                    end if;
                 end if;
                 
              When    st_3 =>
                LED_state      <=   x"03";
                s_start_out    <=   '0';
--                if (s_mac_ready = '0') then
                if (s_wd_cnt = s_dout_len -1) then
                        s_wd_cnt_rst    <= '1';
                        St_ctrl     <= st_idle;--st_4;
--                        if (i_din_valid = '1') then
--                            s_wr_cnta  <= s_wr_cnta - s_dout_len +1;
--                        else
--                            s_wr_cnta  <= s_wr_cnta - s_dout_len;
--                        end if;
                end if;
             
             When    st_4 =>
                LED_state      <= x"04";
                s_wd_cnt_rst   <= '0';
                St_ctrl        <= st_5;  
             
             When    st_5 =>
                LED_state      <= x"05";
                St_ctrl        <= st_6;  
             
             When    st_6 =>
                LED_state      <= x"06";
                St_ctrl        <= st_7;  
             
             When    st_7 =>
                LED_state      <= x"07";
                St_ctrl        <= st_idle;  
                
            When others =>
        end case;


end if;
end process;	



--========================Fifo for Ping_Pong Writing and Reading Data =============================
inst_data_fifo:data_fifo_KED
port map
(
    clk         => i_clk,
    srst        => s_rst_a,
    wr_en       => s_wr_en_a,
    din         => s_dina,
    rd_en       => s_rd_ena,
    dout        => s_douta,
    valid       => s_fifo_valida,
    data_count  => data_fifo_cnt,
    prog_full   => prog_full1,
    full        => s_full_a,
    empty       => s_empty_a
);
--========================Fifo for Ping_Pong Writing and Reading Data =============================
inst_Tlast_fifo:Arr_fifo_KED
port map
(
    clk         => i_clk,
    srst        => s_rst_a,
    wr_en       => s_wr_en_b,
    din         => s_dinb,
    rd_en       => s_rd_enb,
    dout        => s_doutb,
    valid       => s_fifo_validb,
    full        => s_full_b,
    empty       => s_empty_b
);

--=================================================================================================
--my_ila_ping_pong : entity work.ila_LAN
--PORT MAP (
--    clk                     => i_clk,

--    probe0(0)               => s_rst_a,     
--    probe0(1)               => s_wr_en_a,   
--    probe0(9 downto 2)      => s_dina,      
--    probe0(10)              => s_rd_ena,    
--    probe0(18 downto 11)    => s_douta,     
--    probe0(19)              => s_fifo_valida,
--    probe0(20)              => prog_full1,  
--    probe0(21)              => s_full_a,    
--    probe0(22)              => s_empty_a,    
--    probe0(23)              => s_mac_ready,
--    probe0(39 downto 24)    => s_wd_cnt,
--    probe0(55 downto 40)    => s_wr_cnta,
--    probe0(56)              => i_din_valid,
--    probe0(57)              => i_din_last,
    
--    probe0(58)              => s_wr_en_b,   
--    probe0(74 downto 59)    => s_dinb,      
--    probe0(75)              => s_rd_enb,    
--    probe0(91 downto 76)    => s_doutb,     
--    probe0(92)              => s_fifo_validb,
--    probe0(93)              => s_full_b,    
--    probe0(94)              => s_empty_b,  
      
--    probe0(102 downto 95)   => LED_state,     
--    probe0(118 downto 103)  => s_fragment,     
--    probe0(134 downto 119)  => s_wr_cntb,     
--    probe0(135)             => s_wd_cnt_rst,     
--    probe0(151 downto 136)  => s_wr_cnta_r2,     
--    probe0(152)             => s_wr_en_b_r0   ,     
--    probe0(153)             => s_wr_en_b_r1   ,     
--    probe0(154)             => Num_frag_rst  ,-- LastPacket,--    ,     
--    probe0(162 downto 155)  => cntr_frag,--remain_len,--s_dinb_r0 ,     
--    probe0(170 downto 163)  => Num_frag,--data_fifo_cnt,    
--    probe0(181 downto 171)  => data_fifo_cnt,    
--    probe0(182)             => remainPacket,    
--    probe0(183)             => readyFornext,    
        
--    probe0(255 downto 184)   => (others => '0')
--);
--=================================================================================================


end Behavioral;
