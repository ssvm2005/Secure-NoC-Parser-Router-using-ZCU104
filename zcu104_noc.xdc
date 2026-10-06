######################################################################
# ZCU104 - Secure NoC Router Phase-1
# Device: XCZU7EV-FFVC1156-2-E
#
# Top module:
#     zcu104_noc_demo_top
#
# Physical demonstration:
#     SW[3:2] = Source Port
#     SW[1:0] = Destination Port
#     btn_send  = SEND
#     btn_reset = RESET
#     LED[3:0]  = Router output indication
######################################################################


######################################################################
# 1. ZCU104 125 MHz DIFFERENTIAL PL CLOCK
######################################################################

# CLK_125_P = H11
# CLK_125_N = G11
# I/O Standard = LVDS
# Frequency = 125 MHz
# Period = 8 ns

set_property PACKAGE_PIN H11 [get_ports clk_p]
set_property IOSTANDARD LVDS [get_ports clk_p]

set_property PACKAGE_PIN G11 [get_ports clk_n]
set_property IOSTANDARD LVDS [get_ports clk_n]

create_clock -name clk_125MHz -period 8.000 -waveform {0.000 4.000} [get_ports clk_p]

######################################################################
# 2. RESET BUTTON
######################################################################

# ZCU104 CPU reset pushbutton
# SW20
# FPGA pin = M11
# Active HIGH at PL input
# I/O Standard = LVCMOS33

set_property PACKAGE_PIN M11 [get_ports btn_reset]
set_property IOSTANDARD LVCMOS33 [get_ports btn_reset]


######################################################################
# 3. SEND BUTTON
######################################################################

# ZCU104 GPIO pushbutton
# SW14
# FPGA pin = B4
# Active HIGH
# I/O Standard = LVCMOS33

set_property PACKAGE_PIN B4 [get_ports btn_send]
set_property IOSTANDARD LVCMOS33 [get_ports btn_send]


######################################################################
# 4. DIP SWITCHES
######################################################################

# ZCU104 GPIO DIP switch SW13
#
# GPIO_DIP_SW0 -> E4
# GPIO_DIP_SW1 -> D4
# GPIO_DIP_SW2 -> F5
# GPIO_DIP_SW3 -> F4
#
# All Active HIGH
# I/O Standard = LVCMOS33
#
# Our wrapper:
#
#     sw[3:2] = SOURCE PORT
#     sw[1:0] = DESTINATION PORT
#
# Therefore:
#
#     sw[0] -> E4
#     sw[1] -> D4
#     sw[2] -> F5
#     sw[3] -> F4

set_property PACKAGE_PIN E4 [get_ports {sw[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[0]}]

set_property PACKAGE_PIN D4 [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[1]}]

set_property PACKAGE_PIN F5 [get_ports {sw[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[2]}]

set_property PACKAGE_PIN F4 [get_ports {sw[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[3]}]


######################################################################
# 5. USER LEDs
######################################################################

# ZCU104 GPIO LEDs
#
# LED0 -> D5
# LED1 -> D6
# LED2 -> A5
# LED3 -> B5
#
# LEDs are ACTIVE HIGH
# I/O Standard = LVCMOS33

set_property PACKAGE_PIN D5 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN D6 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN A5 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

set_property PACKAGE_PIN B5 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]
