#!/usr/bin/env openroad
# eco hold fix with explicit wire rc from sky130 pdk

set design_dir "/home/one/my_designs/l1_cache_pnr"
set run_dir "$design_dir/runs/run_area3_V2"
set eco_dir "$run_dir/eco_fix"

file mkdir $eco_dir

puts "loading design..."
read_db $run_dir/55-odb-cellfrequencytables/l1_cache_core.odb

read_liberty /home/one/.ciel/ciel/sky130/versions/0fe599b2afb6708d281543108caf8310912f54af/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

# SDC
create_clock -name clk -period 12.5 [get_ports clk]
set_propagated_clock [get_clocks clk]
set_input_delay -clock clk 2.5 [all_inputs]
set_output_delay -clock clk 2.5 [all_outputs]
set_load 0.033442 [all_outputs]
set_clock_uncertainty 0.25 [get_clocks clk]
set_timing_derate -early 0.95
set_timing_derate -late 1.05

# Set wire RC for SKY130 (typical values from PDK)
# met1: R=0.125 ohm/sq, C=0.0374 fF/um
# met2-met4: R=0.125 ohm/sq, C=0.0374 fF/um (approx)
set_wire_rc -signal -layer met2
set_wire_rc -clock -layer met5

puts "estimating parasitics..."
estimate_parasitics -global_routing

puts "\nbefore eco: worst hold paths"
report_checks -path_delay min -endpoint_count 5 -digits 4

puts "\nrepairing hold timing..."
repair_timing -hold -hold_margin 0.05

puts "\nlegalizing placement..."
detailed_placement
check_placement

estimate_parasitics -global_routing

puts "\nafter eco: worst hold paths"
report_checks -path_delay min -endpoint_count 5 -digits 4

puts "\nafter eco: worst setup paths"
report_checks -path_delay max -endpoint_count 3 -digits 4

puts "\nsaving eco design..."
write_db $eco_dir/l1_cache_core.odb
write_def $eco_dir/l1_cache_core.def

puts "\ndone"
exit
