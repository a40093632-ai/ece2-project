# Rebuild and reject a timing-failing design before bitstream generation.
if {[llength [get_projects -quiet]] == 0} {error "Run prepare_fixed_project.tcl first"}
if {[get_property NAME [current_project]] ne "system2"} {error "Open system2 before rebuilding"}
set system_dir [file normalize [file dirname [info script]]]
set evidence_dir [file normalize [file join $system_dir ../../evidence/stage2_timing]]
file mkdir $evidence_dir
catch {close_design}
reset_run synth_1
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1
set run_status [get_property STATUS [get_runs impl_1]]
if {![string match {*route_design Complete*} $run_status]} {error "Implementation did not complete: $run_status"}
open_run impl_1
report_timing_summary -report_unconstrained -file [file join $evidence_dir timing_routed.rpt]
report_drc -file [file join $evidence_dir drc_routed.rpt]
set setup_paths [get_timing_paths -delay_type max -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup_paths] == 0 || [llength $hold_paths] == 0} {error "No timed paths; inspect clock constraints"}
set setup_slack [get_property SLACK $setup_paths]
set hold_slack [get_property SLACK $hold_paths]
puts "SETUP_SLACK=$setup_slack ns; HOLD_SLACK=$hold_slack ns"
if {$setup_slack < 0 || $hold_slack < 0} {error "TIMING FAILED. No new bitstream was requested. See evidence/stage2_timing."}
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
set run_status [get_property STATUS [get_runs impl_1]]
if {![string match {*write_bitstream Complete*} $run_status]} {error "Bitstream generation failed: $run_status"}
puts "BUILD COMPLETE: [get_property DIRECTORY [get_runs impl_1]]/top.bit"
puts "No hardware programming was performed."
