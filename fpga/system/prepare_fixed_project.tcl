# Run from Vivado Tcl Console after applying the code patch.
# Open or create system2 using the current source tree.
set system_dir [file normalize [file dirname [info script]]]
# Portable default; an ignored local file may select a personal output folder.
set output_dir [file normalize [file join $system_dir ../../build/vivado/system2]]
set local_output_config [file join $system_dir vivado_output.local.tcl]
if {[file isfile $local_output_config]} {source $local_output_config}
set project_file [file join $output_dir system2.xpr]
if {[llength [get_projects -quiet]] != 0} {close_project}
if {[file isfile $project_file]} {
    open_project $project_file
} elseif {[file exists $output_dir]} {
    error "Output folder exists without system2.xpr; use a new output_dir."
} else {
    create_project system2 $output_dir -part xc7s75fgga484-1
}
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set source_files {}
lappend source_files [file normalize [file join $system_dir {../stopwatch/src/button_onepulse.v}]]
lappend source_files [file normalize [file join $system_dir {../stopwatch/src/tick_gen.v}]]
lappend source_files [file normalize [file join $system_dir {../stopwatch/src/sevenseg_decode.v}]]
lappend source_files [file normalize [file join $system_dir {../stopwatch/src/seg_scan8.v}]]
lappend source_files [file normalize [file join $system_dir {../stopwatch/src/stopwatch.v}]]
lappend source_files [file normalize [file join $system_dir {../stopwatch/src/display_ctrl.v}]]
lappend source_files [file normalize [file join $system_dir {../uart/src/project_uart_rx.v}]]
lappend source_files [file normalize [file join $system_dir {../uart/src/project_uart_tx.v}]]
lappend source_files [file normalize [file join $system_dir {../uart/src/project_frame_rx.v}]]
lappend source_files [file normalize [file join $system_dir {../uart/src/project_status_tx.v}]]
lappend source_files [file normalize [file join $system_dir {../scheduler/src/scheduler_guarded.v}]]
lappend source_files [file normalize [file join $system_dir {src/stage2_button_router.v}]]
lappend source_files [file normalize [file join $system_dir {src/reservation_control.v}]]
lappend source_files [file normalize [file join $system_dir {src/display_value_adapter.v}]]
lappend source_files [file normalize [file join $system_dir {src/project_lcd_driver.v}]]
lappend source_files [file normalize [file join $system_dir {src/project_lcd_format.v}]]
lappend source_files [file normalize [file join $system_dir {src/top.v}]]
foreach path $source_files {if {![file isfile $path]} {error "Missing RTL: $path"}}
add_files -norecurse -fileset sources_1 $source_files
set xdc_file [file join $system_dir constraints pins.xdc]
add_files -norecurse -fileset constrs_1 $xdc_file
set sim_files {}
lappend sim_files [file join $system_dir sim {tb_button_router.sv}]
lappend sim_files [file join $system_dir sim {tb_display_adapter.sv}]
lappend sim_files [file join $system_dir sim {tb_project_lcd.sv}]
lappend sim_files [file join $system_dir sim {tb_reservation_control.sv}]
lappend sim_files [file join $system_dir sim {tb_system.sv}]
lappend sim_files [file normalize [file join $system_dir ../stopwatch/sim/tb_display_ctrl.sv]]
add_files -norecurse -fileset sim_1 $sim_files
set_property file_type SystemVerilog [get_files $sim_files]
set_property top top [get_filesets sources_1]
set_property top tb_system [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "system2 prepared. Run: source [file join $system_dir verify_build.tcl]"
