"""Bounded, deterministic APEX source-derived candidate generator.

Generates fresh unified diffs from the current cumulative Git source, not
prewritten patches. Fixed generator and acceptance tests cannot be modified
by candidates. This is not a model-backed or open-ended search.
"""
from dataclasses import dataclass
from difflib import unified_diff
from pathlib import Path
import re

TARGET = "apex/core/planner.py"


@dataclass(frozen=True)
class Proposal:
    rule: str
    patch: str


def _diff(before: str, after: str) -> str:
    return "".join(unified_diff(
        before.splitlines(keepends=True), after.splitlines(keepends=True),
        fromfile="a/" + TARGET, tofile="b/" + TARGET, n=3,
    ))


def _decoder_rule(before: str) -> str | None:
    call = "json.JSONDecoder().raw_decode(text[start:])"
    anchor = "_MAX_STEPS = 32\n"
    if before.count(call) != 1 or before.count(anchor) != 1:
        return None
    return before.replace(anchor, anchor + "_RSI_JSON_DECODER = json.JSONDecoder()\n", 1).replace(
        call, "_RSI_JSON_DECODER.raw_decode(text[start:])", 1
    )


def _mapping_rule(before: str) -> str | None:
    pattern = re.compile(
        r"(?P<signature>def _type_name\(value_type: type\) -> str:\n)"
        r"    return (?P<mapping>\{\n(?:        .*\n)+?    \})"
        r"\.get\(value_type, value_type\.__name__\)"
    )
    match = pattern.search(before)
    anchor = "_MAX_STEPS = 32\n"
    if match is None or before.count(anchor) != 1:
        return None
    lifted = "\n".join(line[4:] if line.startswith("    ") else line
                       for line in match.group("mapping").split("\n"))
    after = before.replace(anchor, anchor + "_RSI_TYPE_NAMES = " + lifted + "\n", 1)
    return after.replace(match.group(0), match.group("signature") +
                         "    return _RSI_TYPE_NAMES.get(value_type, value_type.__name__)", 1)


def generate(root: Path) -> list[Proposal]:
    """Detect every currently applicable source transformation; no model calls."""
    before = (root / TARGET).read_text(encoding="utf-8")
    proposals = []
    for name, rule in (("reuse-json-decoder", _decoder_rule),
                       ("lift-type-lookup", _mapping_rule)):
        after = rule(before)
        if after is not None and after != before:
            proposals.append(Proposal(name, _diff(before, after)))
    return proposals
