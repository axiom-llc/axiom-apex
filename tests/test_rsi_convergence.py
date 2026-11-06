"""RSI candidate acceptance, cumulative revisions, and no-op/convergence guards."""
import json
import subprocess
from pathlib import Path

import pytest
from apex import rsi


def test_material_gain_requires_absolute_relative_and_tail():
    before = {"dataset": "train", "p50_ms": 100, "p95_ms": 120, "apex_score": 0.6}
    assert rsi._material_gain(before, {**before, "p50_ms": 97, "p95_ms": 125, "apex_score": 0.61})
    assert not rsi._material_gain(before, {**before, "p50_ms": 99.5, "apex_score": 0.61})
    assert not rsi._material_gain(before, {**before, "p50_ms": 95, "p95_ms": 150, "apex_score": 0.61})
    assert not rsi._material_gain(before, {**before, "p50_ms": 95, "p95_ms": 125, "dataset": "holdout", "apex_score": 0.61})
    assert not rsi._material_gain(before, {**before, "p50_ms": float("nan"), "apex_score": 0.61})


def test_offline_benchmark_correctness_and_nonmock():
    from apex.rsi_offline_bench import measure
    train = measure("train", rounds=3, cases=40)
    holdout = measure("holdout", rounds=3, cases=40)
    assert all(x["passed"] and not x["mock"] and x["apex_score"] > 0 for x in (train, holdout))
    assert all(x["p50_ms"] > 0 and x["p95_ms"] >= x["p50_ms"] for x in (train, holdout))


def test_mock_cannot_authorize_rsi(tmp_path, monkeypatch):
    monkeypatch.setattr(rsi, "REPO_ROOT", tmp_path)
    with pytest.raises(RuntimeError, match="mock benchmark"):
        rsi.run_rsi(1, 20000, str(tmp_path / "tasks.json"), True, "")


def test_no_material_candidate_stops_without_git_effects(tmp_path, monkeypatch, capsys):
    repo = tmp_path / "repo"
    (repo / "apex/core").mkdir(parents=True)
    (repo / "apex/core/loop.py").write_text("VALUE = 0\n")
    (repo / "apex/core/planner.py").write_text("pass\n")
    subprocess.run(["git", "init", "-b", "main", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=RSI Test", "-c",
                    "user.email=test@example.invalid", "commit", "-qm", "fixture"], check=True)
    before = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True)
    monkeypatch.setattr(rsi, "REPO_ROOT", repo)
    monkeypatch.setattr(rsi, "_run_candidate_process", lambda *a, **kw: type("R", (), {"returncode": 0})())
    monkeypatch.setattr(rsi, "_run_bench", lambda *a, dataset="train", **kw: {
        "dataset": dataset, "p50_ms": 100, "p95_ms": 120, "apex_score": .5})
    monkeypatch.setattr(rsi, "_generate_patch", lambda *a: None)
    tasks = tmp_path / "tasks.json"
    tasks.write_text("[]")
    rsi.run_rsi(3, 10000, str(tasks), False, "")
    out = json.loads(capsys.readouterr().out)
    assert out["accepted_branches"] == []
    assert out["rsi_results"][0]["outcome"] == "NO_MATERIAL_CANDIDATE"
    after = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True)
    assert before == after
    assert subprocess.check_output(["git", "-C", str(repo), "branch", "--list", "rsi/*"]) == b""


def test_cumulative_two_generation_git_branches(tmp_path, monkeypatch, capsys):
    repo = tmp_path / "repo"
    (repo / "apex/core").mkdir(parents=True)
    (repo / "apex/core/loop.py").write_text("VALUE = 0\n")
    (repo / "apex/core/planner.py").write_text("pass\n")
    subprocess.run(["git", "init", "-b", "main", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "RSI Test"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "fixture"], check=True)
    monkeypatch.setattr(rsi, "REPO_ROOT", repo)
    monkeypatch.setattr(rsi, "_run_candidate_process", lambda *args, **kwargs: type("Result", (), {"returncode": 0})())
    def baseline(tasks, mock=False, *, dataset="train", k=3):
        value = int((repo / "apex/core/loop.py").read_text().split("=")[1])
        return {"dataset": dataset, "p50_ms": 100 - value * 10,
                "p95_ms": 120 - value * 10, "apex_score": 0.5 + value * 0.1,
                "cpu_ms": 90 - value * 10, "peak_rss_kib": 16000,
                "work_units_per_round": 19000}
    monkeypatch.setattr(rsi, "_run_bench", baseline)
    def patch(api_key, sources, score, budget):
        value = int((repo / "apex/core/loop.py").read_text().split("=")[1])
        return f"--- a/apex/core/loop.py\n+++ b/apex/core/loop.py\n@@ -1 +1 @@\n-VALUE = {value}\n+VALUE = {value + 1}\n"
    monkeypatch.setattr(rsi, "_generate_patch", patch)
    def candidate(ci, diff, tasks, mock, k=3, *, dataset="train", evidence=None):
        value = int((repo / "apex/core/loop.py").read_text().split("=")[1]) + 1
        if evidence is not None:
            evidence.update({"dataset": dataset, "p50_ms": 100-value*10,
                            "p95_ms": 120-value*10, "apex_score": .5+value*.1,
                            "cpu_ms": 90-value*10, "peak_rss_kib": 16000,
                            "work_units_per_round": 19000})
        return .5+value*.1
    monkeypatch.setattr(rsi, "_run_candidate", candidate)
    tasks = tmp_path / "tasks.json"
    tasks.write_text("[]")
    rsi.run_rsi(2, 50000, str(tasks), False, "")
    output = json.loads(capsys.readouterr().out)
    branches = output["accepted_branches"]
    assert len(branches) == 2
    assert output["rsi_results"][1]["train_baseline"]["p50_ms"] == 90
    assert subprocess.check_output(["git", "-C", str(repo), "show", "main:apex/core/loop.py"], text=True) == "VALUE = 0\n"
    assert subprocess.check_output(["git", "-C", str(repo), "show", f"{branches[0]}:apex/core/loop.py"], text=True) == "VALUE = 1\n"
    assert subprocess.check_output(["git", "-C", str(repo), "show", f"{branches[1]}:apex/core/loop.py"], text=True) == "VALUE = 2\n"
