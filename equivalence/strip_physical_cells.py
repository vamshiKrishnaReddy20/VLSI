#!/usr/bin/env python3
"""strips physical-only cell instances (fillers, taps, decaps, diodes)
from sky130 verilog netlists so they don't trip up equivalence checks.

usage: python3 strip_physical_cells.py <in.nl.v> <out.nl.v> [--strip-modules]
"""

import re
import sys
import os

# Physical-only cell prefixes to strip
PHYSICAL_CELL_PREFIXES = [
    "sky130_fd_sc_hd__tapvpwrvgnd_",
    "sky130_fd_sc_hd__tapvgnd_",
    "sky130_fd_sc_hd__fill_",
    "sky130_ef_sc_hd__fill_",
    "sky130_fd_sc_hd__decap_",
    "sky130_ef_sc_hd__decap_",
    "sky130_fd_sc_hd__diode_",
]


def is_physical_cell(cell_name):
    """check if cell is a physical-only type"""
    for prefix in PHYSICAL_CELL_PREFIXES:
        if cell_name.startswith(prefix):
            return True
    return False


def strip_instances(input_path, output_path):
    """remove physical cell instances from a structural netlist"""
    with open(input_path, "r") as f:
        lines = f.readlines()

    output_lines = []
    skip_until_semicolon = False
    instances_stripped = 0

    for line in lines:
        if skip_until_semicolon:
            # We're inside a multi-line physical cell instance; skip lines
            # until we find the closing semicolon
            if ";" in line:
                skip_until_semicolon = False
            continue

        # Check if this line starts a physical cell instance
        # Pattern: <cell_type> <instance_name> (
        stripped = line.lstrip()
        match = re.match(r"(sky130_(?:fd|ef)_sc_hd__\w+)\s+\w+", stripped)
        if match:
            cell_type = match.group(1)
            if is_physical_cell(cell_type):
                instances_stripped += 1
                # Check if this instance ends on the same line
                if ";" in line:
                    continue  # Single-line instance, skip it
                else:
                    skip_until_semicolon = True
                    continue
        
        output_lines.append(line)

    with open(output_path, "w") as f:
        f.writelines(output_lines)

    return instances_stripped


def strip_modules(input_path, output_path):
    """remove module definitions of physical cells from a pdk verilog file"""
    with open(input_path, "r") as f:
        lines = f.readlines()

    output_lines = []
    skip_until_endmodule = False
    modules_stripped = 0

    for line in lines:
        if skip_until_endmodule:
            if line.strip().startswith("endmodule"):
                skip_until_endmodule = False
            continue

        # Check for module definition of a physical cell
        match = re.match(r"\s*module\s+(sky130_(?:fd|ef)_sc_hd__\w+)", line)
        if match:
            module_name = match.group(1)
            if is_physical_cell(module_name):
                modules_stripped += 1
                # Check if endmodule is on same line (unlikely but safe)
                if "endmodule" in line:
                    continue
                skip_until_endmodule = True
                continue

        output_lines.append(line)

    with open(output_path, "w") as f:
        f.writelines(output_lines)

    return modules_stripped


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.v> <output.v> [--strip-modules]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]
    do_strip_modules = "--strip-modules" in sys.argv

    if not os.path.exists(input_path):
        print(f"ERROR: Input file not found: {input_path}")
        sys.exit(1)

    # Create output directory if needed
    out_dir = os.path.dirname(output_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    if do_strip_modules:
        count = strip_modules(input_path, output_path)
        print(f"Stripped {count} physical cell module definitions from {os.path.basename(input_path)}")
    else:
        count = strip_instances(input_path, output_path)
        print(f"Stripped {count} physical cell instances from {os.path.basename(input_path)}")


if __name__ == "__main__":
    main()
