# Integrated second-stage project; run from the Vivado Tcl Console.
# Sources stay in Verilog_Lab/project; Vivado outputs go to Vivado_Work/project/system2.
if {[llength [get_projects -quiet]] != 0} {
    error "Close the current project with File > Close Project, then source this script again."
}
set system_dir [file normalize [file dirname [info script]]]
# Portable default; an ignored local file may select a personal output folder.
set output_dir [file normalize [file join $system_dir ../../build/vivado/system2]]
set local_output_config [file join $system_dir vivado_output.local.tcl]
if {[file isfile $local_output_config]} {source $local_output_config}
if {[file exists $output_dir]} {
    error "system2 already exists. Open system2.xpr, or change output_dir to create a separate project."
}
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
set constraint_file [file join $system_dir constraints pins.xdc]
set sim_file [file join $system_dir sim tb_system.sv]
set lcd_sim_file [file join $system_dir sim tb_project_lcd.sv]
foreach path [concat $source_files [list $constraint_file $sim_file $lcd_sim_file]] {
    if {![file isfile $path]} {error "Missing file: $path. Apply the integrated source package first."}
}
create_project system2 $output_dir -part xc7s75fgga484-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files -fileset sources_1 $source_files
add_files -fileset constrs_1 $constraint_file
add_files -fileset sim_1 [list $sim_file $lcd_sim_file]
set_property top top [get_filesets sources_1]
set_property top tb_system [get_filesets sim_1]
set_property file_type SystemVerilog [get_files [list $sim_file $lcd_sim_file]]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "system2 created: design top=top, simulation top=tb_system. No simulation or build has been launched."
