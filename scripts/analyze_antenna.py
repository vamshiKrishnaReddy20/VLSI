#!/usr/bin/env python3
"""parses antenna_summary.rpt from a pnr run and prints
violation counts by layer, severity, and top offending nets.

usage: python3 analyze_antenna.py <run_directory>
"""

import re
import sys
import os
from collections import Counter

def parse_antenna_summary(rpt_path):
    """parse antenna report table"""
    violations = []
    with open(rpt_path) as f:
        for line in f:
            m = re.search(
                r'│\s+([\d.]+)\s+│\s+([\d.]+)\s+│\s+([\d.]+)\s+│\s+(\S+)\s+│\s+(\S+)\s+│\s+(\S+)\s+│',
                line
            )
            if m:
                violations.append({
                    'ratio': float(m.group(1)),
                    'actual': float(m.group(2)),
                    'limit': float(m.group(3)),
                    'net': m.group(4),
                    'pin': m.group(5),
                    'layer': m.group(6),
                })
    return violations

def categorize_net(net):
    """map net name to a signal category"""
    if 'data_rd' in net: return 'DATA_READ'
    if 'data_wdata' in net or 'data_wr' in net: return 'DATA_WRITE'
    if 'data_wsel' in net: return 'DATA_WSEL'
    if 'cur_wdata' in net or 'cur_wstrb' in net: return 'CUR_WRITE'
    if net.startswith('net') or 'fanout' in net or 'wire' in net: return 'BUFFER/WIRE'
    if 'clk' in net: return 'CLOCK'
    if 'rst' in net: return 'RESET'
    if 'req_' in net or 'resp_' in net or 'mem_' in net: return 'INTERFACE'
    if 'dirty' in net: return 'DIRTY_BIT'
    if 'valid' in net: return 'VALID_BIT'
    if 'tag' in net or 'u_tag' in net: return 'TAG_ARRAY'
    if 'lru' in net: return 'LRU'
    if 'refill' in net: return 'REFILL'
    if 'state' in net: return 'FSM_STATE'
    return 'INTERNAL_LOGIC'

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <run_directory>")
        sys.exit(1)

    run_dir = sys.argv[1]

    # Find the latest antenna check report
    candidates = []
    for d in sorted(os.listdir(run_dir)):
        rpt = os.path.join(run_dir, d, 'reports', 'antenna_summary.rpt')
        if os.path.exists(rpt) and 'checkantennas' in d:
            candidates.append(rpt)

    if not candidates:
        print("No antenna report found!")
        sys.exit(1)

    rpt_path = candidates[-1]  # Use the latest one
    print(f"Analyzing: {rpt_path}\n")

    violations = parse_antenna_summary(rpt_path)

    # summary
    unique_nets = set(v['net'] for v in violations)
    print(f"Total violation entries: {len(violations)}")
    print(f"Unique violating nets:  {len(unique_nets)}")

    # by layer
    layer_counts = Counter(v['layer'] for v in violations)
    print(f"\n{'Layer':>6s}  {'Count':>5s}  {'Pct':>5s}")
    print("-" * 20)
    for layer, cnt in layer_counts.most_common():
        print(f"{layer:>6s}  {cnt:>5d}  {100*cnt/len(violations):>4.1f}%")

    # severity distribution
    bins = [(1.0, 1.05), (1.05, 1.1), (1.1, 1.2), (1.2, 1.5), (1.5, 2.0), (2.0, 100.0)]
    labels = ['1.00-1.05x', '1.05-1.10x', '1.10-1.20x', '1.20-1.50x', '1.50-2.00x', '>2.00x']
    print(f"\n{'Ratio Range':>12s}  {'Count':>5s}  {'Severity'}")
    print("-" * 40)
    for (lo, hi), label in zip(bins, labels):
        cnt = sum(1 for v in violations if lo <= v['ratio'] < hi)
        sev = 'Marginal' if hi <= 1.2 else ('Moderate' if hi <= 2.0 else 'Severe')
        print(f"{label:>12s}  {cnt:>5d}  {sev}")

    # top violating nets
    net_max_ratio = {}
    net_pin_count = Counter()
    for v in violations:
        net_pin_count[v['net']] += 1
        if v['net'] not in net_max_ratio or v['ratio'] > net_max_ratio[v['net']]:
            net_max_ratio[v['net']] = v['ratio']

    print(f"\nTop 20 Worst Nets (by max ratio):")
    print(f"{'Ratio':>6s}  {'Pins':>4s}  {'Net':35s}  {'Type'}")
    print("-" * 70)
    for net in sorted(net_max_ratio, key=net_max_ratio.get, reverse=True)[:20]:
        ntype = categorize_net(net)
        print(f"{net_max_ratio[net]:>6.2f}  {net_pin_count[net]:>4d}  {net:35s}  {ntype}")

    # design signal violations
    design_signals = [v for v in violations if categorize_net(v['net']) != 'INTERNAL_LOGIC']
    if design_signals:
        print(f"\nDesign-Level Signal Violations:")
        print(f"{'Ratio':>6s}  {'Net':35s}  {'Layer':>6s}  {'Type'}")
        print("-" * 65)
        seen = set()
        for v in sorted(design_signals, key=lambda x: -x['ratio']):
            key = (v['net'], v['layer'])
            if key not in seen:
                seen.add(key)
                print(f"{v['ratio']:>6.2f}  {v['net']:35s}  {v['layer']:>6s}  {categorize_net(v['net'])}")

if __name__ == '__main__':
    main()
