#!/usr/bin/env python3
"""compares key pnr metrics across multiple runs side-by-side.

usage: python3 compare_runs.py <run1> <run2> [run3 ...]
"""

import json
import sys
import os

METRICS = [
    ('design__instance__count',            'Instance Count'),
    ('design__instance__utilization',      'Utilization'),
    ('design__instance__area__stdcell',    'Std Cell Area'),
    ('power__total',                       'Total Power (W)'),
    ('route__drc_errors',                  'Routing DRC'),
    ('route__wirelength',                  'Wirelength'),
    ('antenna__violating__nets',           'Antenna Nets'),
    ('antenna__violating__pins',           'Antenna Pins'),
    ('antenna_diodes_count',               'Diodes Inserted'),
    ('magic__drc_error__count',            'Magic DRC'),
    ('design__lvs_error__count',           'LVS Errors'),
    ('design__max_slew_violation__count',  'Max Slew Viols'),
    ('design__max_cap_violation__count',   'Max Cap Viols'),
    ('design__max_fanout_violation__count','Max Fanout Viols'),
]

TIMING_CORNERS = [
    'nom_tt_025C_1v80', 'nom_ss_100C_1v60', 'nom_ff_n40C_1v95',
    'max_ss_100C_1v60',
]

def load_metrics(run_dir):
    path = os.path.join(run_dir, 'final', 'metrics.json')
    if not os.path.exists(path):
        print(f"Warning: {path} not found")
        return {}
    with open(path) as f:
        return json.load(f)

def fmt_val(v):
    if v is None: return 'N/A'
    if isinstance(v, float):
        if abs(v) < 0.001: return f'{v:.6f}'
        if abs(v) < 1: return f'{v:.4f}'
        return f'{v:.2f}'
    return str(v)

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <run1> <run2> [run3 ...]")
        sys.exit(1)

    runs = sys.argv[1:]
    data = {r: load_metrics(r) for r in runs}
    names = [os.path.basename(r) for r in runs]

    # Header
    col_w = max(16, max(len(n) for n in names) + 2)
    print(f"{'Metric':35s}", end='')
    for n in names:
        print(f"  {n:>{col_w}s}", end='')
    print()
    print("-" * (35 + (col_w + 2) * len(names)))

    # General metrics
    for key, label in METRICS:
        print(f"{label:35s}", end='')
        for r in runs:
            v = data[r].get(key)
            print(f"  {fmt_val(v):>{col_w}s}", end='')
        print()

    # Timing per corner
    print(f"\n{'--- TIMING ---':35s}")
    for corner in TIMING_CORNERS:
        for metric_type in ['setup__wns', 'setup_vio__count', 'hold__wns', 'hold_vio__count']:
            key = f'timing__{metric_type}__corner:{corner}'
            label = f'{corner[:6]} {metric_type}'
            print(f"{label:35s}", end='')
            for r in runs:
                v = data[r].get(key)
                print(f"  {fmt_val(v):>{col_w}s}", end='')
            print()
        print()

if __name__ == '__main__':
    main()
