# PnR Iteration Log

Documents the full place-and-route journey for the l1_cache_core design
on Sky130 using LibreLane/OpenROAD.

## Background

The initial version of this cache used behavioral SystemVerilog for the data
arrays. Yosys synthesized each 32-bit memory word into master-slave latch pairs,
resulting in a massive design (~2500x2500 um die area). PnR was extremely slow
and the design only achieved ~40 MHz. Each iteration took hours to complete,
making it impractical to iterate on the physical design.

After discovering the OpenRAM project and its pre-built Sky130 SRAM macros
(sky130_sram_1kbyte_1rw1r_32x256_8), the data arrays were replaced with 4 SRAM
macro instances. This dramatically reduced the standard cell count and made
PnR feasible. All iterations below start from this SRAM-based design.

## Iteration Summary

| Version | Key Change | Result |
|---|---|---|
| V0 | initial floorplan, manual macro placement | routing congestion, 382 antenna violations |
| V1 | met3 adjustment (0.7) | killed after 7h resizer loop |
| V2 | met3 adjustment (0.3) | 48 antenna viols, 2 hold violations |
| V2-ECO | manual eco hold fix attempt | hold fixed but introduced new issues |
| V3 | area reduction | too tight, placement failures |
| V4 | cleaned config | clean setup, -122ps hold, 42 antenna nets |
| V5 | added SS/FF libs | incomplete (CTS partial) |
| V6 | 3-phase approach | first clean route, still had antenna issues |
| V7 | incremental antenna work | reduced violations |
| V8 | manual eco antenna fix (remove fillers, insert diodes) | DRC and LVS exploded — 51K DRC + 2.5K LVS errors. fillers destroyed, magic could not reconstruct |
| V9 | attempted signoff from V8 | same failures, confirmed V8 ODB was corrupted |
| V10 | fresh start, proper automation, heuristic diode insertion | -44ps hold, 57K DRC (N-well tap issues) |
| V11 | halo=15 to fix N-well DRC | 540 antenna nets, 1.7K DRC remaining |
| V12 | RUN_HEURISTIC_DIODE=true, macro placement adjustments | 26 antenna nets, hold timing clean — first real signoff candidate |
| V13 | diode_insertion_strategy=3 (hybrid) | 16 antenna viols but introduced 1 hold violation, too aggressive |
| V14 | density=35, routability driven placement | spread cells out for diode space |
| V15-V17 | layer adjustments, PDN geometry fixes | incremental improvements on remaining violations |
| V18 | final antenna cleanup | antenna clean |
| final | production config, full clean run | signoff run |

## Key Issues Encountered

### Behavioral Data Array Explosion
before switching to SRAMs, the data arrays were synthesized as register
files using master-slave flipflop pairs. this produced an enormous design
that was nearly impossible to place and route. each PnR run took hours.
switching to OpenRAM SRAM macros solved this by replacing ~90% of the
standard cell area with 4 pre-built macro blocks.

### Floorplan Exploration
tried multiple floorplan strategies:
- **initial placement**: macros scattered, standard cells clustering in center
- **donut floorplan**: all 4 macros in the center, std cells in a ring around them.
  this caused severe wire detours around the ~960x875um central obstruction
  and timing could not converge.
- **L-shape boundary (final)**: macros at the 4 corners, pins facing inward.
  orientations: BL=S, BR=FS, TL=FN, TR=N. this left a wide open center area
  (~700x1200um) for uniform placement and eliminated congestion.

### Manual ECO Failure (V8/V9)
attempted to manually fix antenna violations after detailed routing by
removing filler cells, inserting diodes, and re-routing using TCL scripts.
when the patched ODB was loaded back into the flow, it exploded with
51K DRC errors and 2.5K LVS errors. magic could not reconstruct the
gaps left by destroyed filler cells, and the netlist went out of
sync because manually inserted diodes were not in the verilog.
lesson: never use manual ECO after detailed routing.

### Antenna Violations
sky130 has strict antenna rules. sram macro connections and long met1/met2
routes were the main offenders. the winning strategy was:
- setting GRT_ANTENNA_ITERS=20 and RUN_HEURISTIC_DIODE_INSERTION=true
  in the librelane config
- lowering PL_TARGET_DENSITY_PCT to spread cells out and leave physical
  space for diode insertion near affected pins
- adjusting macro placement to reduce long routing paths

### Hold Timing
hold violations appeared after CTS on paths between the fsm and sram
arrays. repair_timing -hold was used within the automated flow.
timing met on nominal corners (TT 1.8V/25C and FF -40C/1.95V).
SS corner (1.6V/100C) had setup violations that could not be closed
due to the inherently slow sky130 process at that extreme PVT and
SRAM lib characterization limitations.

### SRAM PDN Integration
openram macros use vccd1/vssd1 for power while sky130 standard cells
use VPWR/VGND. required PDN_MACRO_CONNECTIONS in the config to bridge
the two domains. also needed custom core ring widths (5um) and spacing
to avoid shorts near macro boundaries.

### N-Well Tap DRC
initial runs had n-well tap spacing violations near macro edges. fixed
by adjusting macro placement and halo settings to give enough clearance
for tap cell insertion around the sram boundaries.

## Final Status

- routing DRC: clean (standard cell logic)
- SRAM-internal DRC violations: present but waivable (pre-verified OpenRAM IP, unknown GDS layers not in magic tech file)
- antenna violations: 0
- hold timing (nominal corners): met
- setup timing (nominal corners): met
- setup timing (SS 1.6V/100C): violations present (sky130 process limitation at extreme corner)
- LVS: clean
- equivalence check: some mismatches related to SRAM blackboxing and async reset handling in yosys (waivable — structural preservation verified)
