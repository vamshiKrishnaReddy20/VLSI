#!/usr/bin/env bash
# signoff: rtl vs final netlist end-to-end equivalence check
# synthesizes rtl to gates, then compares gate-to-gate
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_DIR="$PROJECT_DIR/runs/run_area3_final"
WORK_DIR="$SCRIPT_DIR/work_signoff"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/signoff.log"

SRAM_BB="$PROJECT_DIR/src/sky130_sram_blackbox.sv"
LIBERTY="/home/one/.ciel/ciel/sky130/versions/0fe599b2afb6708d281543108caf8310912f54af/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"

# rtl source files
RTL_FILES=(
    "$PROJECT_DIR/src/l1_cache_pkg.sv"
    "$PROJECT_DIR/src/tag_array.sv"
    "$PROJECT_DIR/src/data_array.sv"
    "$PROJECT_DIR/src/pseudo_lru.sv"
    "$PROJECT_DIR/src/l1_cache_core.sv"
)

GATE_NL="$RUN_DIR/final/nl/l1_cache_core.nl.v"

echo "lec signoff: rtl vs final"
echo "Gold: RTL source (will be synthesized internally)"
echo "Gate: $GATE_NL"

mkdir -p "$WORK_DIR" "$LOG_DIR"

echo "stripping physical cells..."
python3 "$SCRIPT_DIR/strip_physical_cells.py" \
    "$GATE_NL" \
    "$WORK_DIR/gate_stripped.nl.v"

cat > "$WORK_DIR/run_equiv.ys" << 'YOSYS_SCRIPT'
# signoff: rtl vs final, equiv_simple -seq 20

read_liberty -lib ${LIBERTY}

# gold: synthesize rtl
read_verilog -D SYNTHESIS -sv ${SRAM_BB}
read_verilog -sv ${RTL_FILES}
hierarchy -top l1_cache_core
proc
memory
flatten
synth -top l1_cache_core -flatten
dfflibmap -liberty ${LIBERTY}
abc -liberty ${LIBERTY}
async2sync
clean
rename -top gold
hierarchy -top gold
clean

design -stash gold

# gate: final netlist
read_liberty -lib ${LIBERTY}
read_verilog -D SYNTHESIS -sv ${SRAM_BB}
read_verilog ${GATE_NL}
hierarchy -top l1_cache_core
proc
flatten
async2sync
clean
rename -top gate
hierarchy -top gate
clean

# build miter
design -copy-from gold -as gold gold
equiv_make gold gate equiv_module
hierarchy -top equiv_module
clean
equiv_simple -seq 20
equiv_status
YOSYS_SCRIPT

RTL_FILES_STR=""
for f in "${RTL_FILES[@]}"; do
    RTL_FILES_STR="$RTL_FILES_STR $f"
done

sed -i "s|\${RTL_FILES}|$RTL_FILES_STR|g" "$WORK_DIR/run_equiv.ys"
sed -i "s|\${SRAM_BB}|$SRAM_BB|g" "$WORK_DIR/run_equiv.ys"
sed -i "s|\${GATE_NL}|$WORK_DIR/gate_stripped.nl.v|g" "$WORK_DIR/run_equiv.ys"
sed -i "s|\${LIBERTY}|$LIBERTY|g" "$WORK_DIR/run_equiv.ys"

echo "running yosys equiv check..."
echo "log: $LOG_FILE"

if yosys -Q -T -l "$LOG_FILE" -s "$WORK_DIR/run_equiv.ys" 2>&1; then
    echo "signoff PASS: rtl matches final netlist"
    grep -A5 "equiv_status" "$LOG_FILE" | tail -6
    exit 0
else
    echo "signoff FAIL: rtl does not match final netlist"
    grep -A5 "equiv_status" "$LOG_FILE" | tail -6 || true
    exit 1
fi
