#!/usr/bin/env bash
# run all 5 lec stages and print a summary
# exits 0 if all pass, 1 if any fail
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "l1_cache_core multi-stage equivalence check (run_area3_final)"
echo "started: $(date)"
echo ""

# Track results
declare -a STAGE_NAMES=(
    "Stage 1: RTL vs Synthesis"
    "Stage 2: Synthesis vs CTS"
    "Stage 3: CTS vs Routing"
    "Stage 4: Routing vs Final"
    "Signoff: RTL vs Final"
)
declare -a STAGE_SCRIPTS=(
    "run_lec_stage1.sh"
    "run_lec_stage2.sh"
    "run_lec_stage3.sh"
    "run_lec_stage4.sh"
    "run_lec_signoff.sh"
)
declare -a STAGE_RESULTS=()
declare -a STAGE_TIMES=()
OVERALL_PASS=true

# Run each stage
for i in "${!STAGE_SCRIPTS[@]}"; do
    echo "--------------------------------------------------"
    echo "running: ${STAGE_NAMES[$i]}"
    echo "--------------------------------------------------"
    
    START_TIME=$(date +%s)
    
    if bash "$SCRIPT_DIR/${STAGE_SCRIPTS[$i]}"; then
        STAGE_RESULTS+=("PASS")
    else
        STAGE_RESULTS+=("FAIL")
        OVERALL_PASS=false
    fi
    
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    STAGE_TIMES+=("${ELAPSED}s")
    
    echo ""
done

# summary
echo ""
echo "--------------------------------------------------"
echo "lec summary"
echo "--------------------------------------------------"
printf "  %-35s  %-8s  %-6s\n" "stage" "result" "time"
echo ""

for i in "${!STAGE_NAMES[@]}"; do
    RESULT="${STAGE_RESULTS[$i]}"
    printf "  %-35s  %-8s  %-6s\n" "${STAGE_NAMES[$i]}" "$RESULT" "${STAGE_TIMES[$i]}"
done

echo ""
echo "done: $(date)"

if $OVERALL_PASS; then
    echo "all stages passed"
    exit 0
else
    echo "some stages failed, check equivalence/logs/"
    exit 1
fi
