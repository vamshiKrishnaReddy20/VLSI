#!/usr/bin/env openroad
# eco antenna fix - remove fillers, insert diodes, re-route

set design_dir "/home/one/my_designs/l1_cache_pnr"
set run_dir "$design_dir/runs/run_area3_V8"
set eco_dir "$run_dir/eco_fix"

file mkdir $eco_dir

# load design (pre-fill odb)
puts "loading design..."
read_db $run_dir/43-openroad-resizertimingpostgrt/data_cache_core.odb

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

# Wire RC
set_wire_rc -signal -layer met2
set_wire_rc -clock -layer met5

# remove fillers to free up space
puts "\nremoving fillers..."
remove_fillers

# check antennas before fix
puts "\nantenna check (before)..."
check_antennas

# repair antennas
puts "\nre-running global route..."
global_route
puts "\nrepairing antennas..."
repair_antennas sky130_fd_sc_hd__diode_2 -iterations 15 -ratio_margin 90

# write out repaired design
puts "\nwriting repaired design..."
write_guides $run_dir/eco_fix/route.guide
write_db $run_dir/eco_fix/data_cache_core_repaired.odb
exit 0

# legalize placement
puts "\nlegalizing..."
detailed_placement
check_placement

# check antennas after fix
puts "\nantenna check (after)..."
check_antennas

# re-insert fillers
puts "\nre-inserting fillers..."
filler_placement "sky130_fd_sc_hd__fill_1 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_4 sky130_fd_sc_hd__fill_8"
check_placement

# save
puts "\nsaving eco design..."
write_db $eco_dir/data_cache_core.odb
write_def $eco_dir/data_cache_core.def

puts "\ndone"
exit
