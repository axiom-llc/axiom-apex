#!/usr/bin/env bash
# generative-3d.sh — Iterative AI-driven 3D model generator
# Each iteration: agent reads current .scad + compile result → writes improved version
# Demonstrates: compile-test-fix convergence loop, automated design refinement
# Usage: ./generative-3d.sh [iterations] [object description]
# Requires: openscad (headless), apex

set -euo pipefail

ITERATIONS="${1:-3}"

# ── Object prompt ─────────────────────────────────────────────────────────────
if [[ -n "${2:-}" ]]; then
    OBJECT="$2"
else
    read -rp "What do you want to generate? (e.g. 'a parametric phone stand'): " OBJECT
    [[ -z "$OBJECT" ]] && echo "✗ No object specified." && exit 1
fi

APEX_ROOT="${APEX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTDIR="$HOME/generative-3d/$(date +%Y%m%d_%H%M%S)"
SCAD="$OUTDIR/model.scad"
LOG="$OUTDIR/build.log"

cd "$APEX_ROOT"
mkdir -p "$OUTDIR"

echo "▶ Object     : $OBJECT"
echo "▶ Iterations : $ITERATIONS"
echo "▶ Output     : $OUTDIR"
echo ""

# ── Iteration 0: generate initial SCAD ───────────────────────────────────────
echo "── Iteration 0 : initial generation"

apex "Write an OpenSCAD script for: ${OBJECT}

Save it to ${SCAD} using write_file.

OpenSCAD rules:
- Primitives: cube([x,y,z]) sphere(r) cylinder(h,r1,r2)
- Booleans: union(){} difference(){} intersection(){}
- Transforms: translate([x,y,z]) rotate([x,y,z]) scale([x,y,z])
- Parameters: define all key dimensions as variables at the top of the file
- NO semicolons after closing braces
- No external libraries or include statements

Design goals:
- Interpret the object description and produce a reasonable, functional model
- All key dimensions must be parametric variables at the top
- Clean manifold geometry (printable/renderable)
- Pure OpenSCAD only — no markdown fences in output"

[[ ! -f "$SCAD" ]] && echo "✗ Initial generation failed" && exit 1

# ── Main loop ─────────────────────────────────────────────────────────────────
for i in $(seq 1 "$ITERATIONS"); do

    echo "── Iteration $i/$ITERATIONS"

    STL="$OUTDIR/model_iter_${i}.stl"
    COMPILE_OK=false

    if openscad --hardwarnings -o "$STL" "$SCAD" 2>"$LOG"; then
        COMPILE_OK=true
        echo "   ✓ compiled → $(du -sh "$STL" | cut -f1)"
    else
        echo "   ✗ compile failed"
        cat "$LOG"
    fi

    if [[ "$COMPILE_OK" == true ]]; then

        apex "OpenSCAD model iteration ${i}/${ITERATIONS} — compile succeeded.
Object being modelled: ${OBJECT}

Read the current SCAD using read_file from ${SCAD}
Read the compile log using read_file from ${LOG}

Improve the design. Pick one or two focus areas:
- Detail and accuracy: refine the model to better represent the described object
- Parametric structure: more variables, cleaner dimensional relationships
- Geometry: remove redundant operations, improve manifold integrity
- Print readiness: avoid overhangs over 45deg, enforce minimum wall thickness

Rules:
- Read the file first, then write the complete improved version
- Preserve all existing parametric variables
- No markdown fences in output — pure OpenSCAD only
- No semicolons after closing braces

Write complete improved file to ${SCAD} using write_file"

    else

        apex "OpenSCAD model iteration ${i}/${ITERATIONS} — compile FAILED.
Object being modelled: ${OBJECT}

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
FINAL_STL="$OUTDIR/model_final.stl"

if openscad -o "$FINAL_STL" "$SCAD" 2>"$LOG"; then
    echo "✓ Final STL: $FINAL_STL ($(du -sh "$FINAL_STL" | cut -f1))"
else
    echo "✗ Final compile failed — see $LOG"
    echo "  SCAD still at: $SCAD"
fi

echo ""
echo "✓ Done"
echo "  Object     : $OBJECT"
echo "  Iterations : $OUTDIR/model_iter_*.stl"
echo "  Final SCAD : $SCAD"
echo "  Final STL  : $FINAL_STL"
echo "  Log        : $LOG"
