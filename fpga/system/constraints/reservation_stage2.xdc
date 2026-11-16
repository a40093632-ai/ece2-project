## Combo II-DLD S75, standalone reservation_board_top ONLY.
## Physical clock display must be 50 MHz. SW5 contact OFF connects PORT A.
## Proposed external assignment: A I/O00 Gate, I/O01 RX, I/O02 TX.
## Verify GPIO LOW/HIGH and shared GND before external circuit connection.
set_property PACKAGE_PIN B6 [get_ports clk_50mhz]
set_property PACKAGE_PIN K4 [get_ports rst_p]
set_property PACKAGE_PIN N8 [get_ports btn_start]
set_property PACKAGE_PIN N4 [get_ports btn_clear]
set_property PACKAGE_PIN N1 [get_ports btn_mode]
set_property PACKAGE_PIN P6 [get_ports btn_set]
set_property PACKAGE_PIN F8 [get_ports gate_en]
set_property PACKAGE_PIN E8 [get_ports uart_rx]
set_property PACKAGE_PIN A7 [get_ports uart_tx]
set_property PACKAGE_PIN L4 [get_ports {led[0]}]
set_property PACKAGE_PIN M4 [get_ports {led[1]}]
set_property PACKAGE_PIN M2 [get_ports {led[2]}]
set_property PACKAGE_PIN N7 [get_ports {led[3]}]
set_property PACKAGE_PIN M7 [get_ports {led[4]}]
set_property PACKAGE_PIN M3 [get_ports {led[5]}]
set_property PACKAGE_PIN M1 [get_ports {led[6]}]
set_property PACKAGE_PIN N5 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports *]
create_clock -name clk_50mhz -period 20.000 [get_ports clk_50mhz]
set_false_path -from [get_ports {rst_p btn_start btn_clear btn_mode btn_set uart_rx}]
## Do not guess CFGBVS / CONFIG_VOLTAGE: obtain module bank-0 supply/strap evidence.
