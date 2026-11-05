# APEX bounded-team evaluation

Standalone standard-library prototype, Python 3.11+. Retained for evaluation on a
separate branch; not installed, imported or invoked by APEX production code/CI.

Read [DESIGN.md](DESIGN.md) for behavior, alternatives and integration boundaries;
[EVALUATION.md](EVALUATION.md) records measurements and limitations.

From this directory:

```bash
python -m unittest discover -v
python benchmark.py --repeats 30 --output results.json
```

The benchmark performs no network, provider or paid operation. It overwrites only
the selected result file. Raw observations and source hashes are in results.json.

## Minimal callback example

```python
import asyncio
from team import Task, Worker, coordinate

async def specialist(task, inputs, feedback):
    # Replace with an authorized agent adapter only in a separately reviewed test.
    # Here deterministic roles demonstrate a dependency result handoff.
    if task.id == "inspect":
        return {"finding": "candidate needs a check"}
    return {"review": inputs["inspect"]["finding"], "accepted": True}

def validate(task, result):
    expected = {"finding"} if task.id == "inspect" else {"review", "accepted"}
    return None if isinstance(result, dict) and set(result) == expected else "wrong shape"

report = asyncio.run(coordinate(
    [Task("inspect", instruction="Inspect a candidate"),
     Task("review", instruction="Review the accepted finding", deps=("inspect",))],
    [Worker("specialist", specialist)], validate))
assert report.states == {"inspect": "accepted", "review": "accepted"}
```

This example validates shape only. Real task correctness requires a stronger
independent validator. Fixture output is not evidence of reasoning quality.

Files: team.py (runtime), test_team.py (regressions), benchmark.py (paired scheduler
evaluation), results.json (raw/summary evidence), DESIGN.md, EVALUATION.md and PLAN.md.
