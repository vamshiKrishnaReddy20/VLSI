#!/usr/bin/env bash
# stage 2: post-synthesis vs post-cts equivalence check
# gate-to-gate, no pdk cell library needed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_DIR="$PROJECT_DIR/runs/run_area3_final"
WORK_DIR="$SCRIPT_DIR/work_stage2"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/stage2.log"

SRAM_BB="$PROJECT_DIR/src/sky130_sram_blackbox.sv"

GOLD_NL="$RUN_DIR/06-yosys-synthesis/l1_cache_core.nl.v"
GATE_NL="$RUN_DIR/34-openroad-cts/l1_cache_core.nl.v"

echo "=== LEC Stage 2: Post-Synthesis vs Post-CTS ==="
echo "Gold: $GOLD_NL"
echo "Gate: $GATE_NL"

# --- Setup ---
mkdir -p "$WORK_DIR" "$LOG_DIR"

echo "stripping physical cells from gold..."
python3 "$SCRIPT_DIR/strip_physical_cells.py" \
    "$GOLD_NL" \
    "$WORK_DIR/gold_stripped.nl.v"

echo "stripping physical cells from gate..."
python3 "$SCRIPT_DIR/strip_physical_cells.py" \
    "$GATE_NL" \
    "$WORK_DIR/gate_stripped.nl.v"

cat > "$WORK_DIR/run_equiv.ys" << YOSYS_SCRIPT
# stage 2: post-synthesis vs post-cts, equiv_simple -seq 10

# gold: post-synthesis
read_verilog -D SYNTHESIS -sv $SRAM_BB
read_verilog $WORK_DIR/gold_stripped.nl.v
hierarchy -top l1_cache_core
proc
flatten
clean
rename -top gold
hierarchy -top gold
clean

design -stash gold

# gate: post-cts
read_verilog -D SYNTHESIS -sv $SRAM_BB
read_verilog $WORK_DIR/gate_stripped.nl.v
hierarchy -top l1_cache_core
proc
flatten
clean
rename -top gate
hierarchy -top gate
clean

# build miter
design -copy-from gold -as gold gold
equiv_make gold gate equiv_module
hierarchy -top equiv_module
clean
equiv_simple -seq 10
equiv_status
YOSYS_SCRIPT

echo "running yosys equiv check..."
echo "log: $LOG_FILE"

if yosys -Q -T -l "$LOG_FILE" -s "$WORK_DIR/run_equiv.ys" 2>&1; then
    echo "stage 2 PASS: synthesis matches post-cts"
    grep -A5 "equiv_status" "$LOG_FILE" | tail -6
    exit 0
else
    echo "stage 2 FAIL: synthesis does not match post-cts"
    grep -A5 "equiv_status" "$LOG_FILE" | tail -6 || true
    exit 1
fi
