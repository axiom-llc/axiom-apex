#!/usr/bin/env bash
# generative-3d.sh — Iterative AI-driven 3D model generator
# Each iteration: agent reads current .scad + compile result → writes improved version
# Demonstrates: compile-test-fix convergence loop, automated design refinement
# Usage: ./generative-3d.sh [iterations]
# Requires: openscad (headless), apex

set -euo pipefail

ITERATIONS="${1:-3}"

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTDIR="$HOME/generative-3d/$(date +%Y%m%d_%H%M%S)"
SCAD="$OUTDIR/enclosure.scad"
LOG="$OUTDIR/build.log"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ Iterations : $ITERATIONS"
echo "▶ Output     : $OUTDIR"
echo ""

# ── Iteration 0: generate initial SCAD ───────────────────────────────────────
echo "── Iteration 0 : initial generation"

apex "Write an OpenSCAD script for a parametric electronics enclosure to ${SCAD} using write_file.

OpenSCAD rules:
- Primitives: cube([x,y,z]) sphere(r) cylinder(h,r1,r2)
- Booleans: union(){} difference(){} intersection(){}
- Transforms: translate([x,y,z]) rotate([x,y,z]) scale([x,y,z])
- Parameters: define at top as variables e.g. box_w = 100;
- NO semicolons after closing braces
- No external libraries or include statements

Design goals:
- All key dimensions as parametric variables at top of file
- Rectangular enclosure body with removable lid
- Use difference() to cut mounting holes, ventilation slots, and cable entry points
- Use union() to add internal standoffs and lid alignment tabs
- Scale: approx 120mm x 80mm x 40mm
- Wall thickness min 2mm, standoff height 5mm
- Clean manifold geometry (printable)"

[[ ! -f "$SCAD" ]] && echo "✗ Initial generation failed" && exit 1

# ── Main loop ─────────────────────────────────────────────────────────────────
for i in $(seq 1 "$ITERATIONS"); do

    echo "── Iteration $i/$ITERATIONS"

    STL="$OUTDIR/enclosure_iter_${i}.stl"
    COMPILE_OK=false

    if openscad --hardwarnings -o "$STL" "$SCAD" 2>"$LOG"; then
        COMPILE_OK=true
        echo "   ✓ compiled → $(du -sh "$STL" | cut -f1)"
    else
        echo "   ✗ compile failed"
        cat "$LOG"
    fi

    if [[ "$COMPILE_OK" == true ]]; then

        apex "OpenSCAD enclosure iteration ${i}/${ITERATIONS} — compile succeeded.

Read the current SCAD using read_file from ${SCAD}
Read the compile log using read_file from ${LOG}

Improve the design. Pick one or two focus areas:
- Functional detail: additional mounting features, improved vent geometry, snap-fit lid
- Parametric structure: more variables, cleaner relationships between dimensions
- Geometry: remove redundant operations, improve manifold integrity
- Print readiness: avoid overhangs over 45deg, enforce minimum wall thickness

Rules:
- Read the file first, then write the complete improved version
- Preserve all existing parametric variables
- No markdown fences in output — pure OpenSCAD only
- No semicolons after closing braces

Write complete improved file to ${SCAD} using write_file"

    else

        apex "OpenSCAD enclosure iteration ${i}/${ITERATIONS} — compile FAILED.

Read the broken SCAD using read_file from ${SCAD}
Read the compile errors using read_file from ${LOG}

Fix every error. Common causes:
- Semicolons after closing braces
- Unclosed braces
- Undefined variables
- Missing commas in vectors: [x y z] must be [x,y,z]

Read the files first, then write the complete fixed version.
Pure OpenSCAD only — no markdown fences.

Write fixed file to ${SCAD} using write_file"

    fi

    [[ ! -f "$SCAD" ]] && echo "  ⚠ no scad written — stopping" && break

done

# ── Final compile ─────────────────────────────────────────────────────────────
echo ""
echo "── Final compile..."
FINAL_STL="$OUTDIR/enclosure_final.stl"

if openscad -o "$FINAL_STL" "$SCAD" 2>"$LOG"; then
    echo "✓ Final STL: $FINAL_STL ($(du -sh "$FINAL_STL" | cut -f1))"
else
    echo "✗ Final compile failed — see $LOG"
    echo "  SCAD still at: $SCAD"
fi

echo ""
echo "✓ Done"
echo "  Iterations : $OUTDIR/enclosure_iter_*.stl"
echo "  Final SCAD : $SCAD"
echo "  Final STL  : $FINAL_STL"
echo "  Log        : $LOG"
