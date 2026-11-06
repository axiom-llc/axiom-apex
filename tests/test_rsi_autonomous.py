"""Autonomous source-rule generation, acceptance separation, and resource gates."""
import json
import subprocess
from pathlib import Path
import pytest

from apex import rsi
from apex.rsi_candidate_rules import generate, _decoder_rule, _mapping_rule
from apex.rsi_lab_evidence import evaluate


def test_source_rules_are_one_time_fixed_points():
    source = Path("apex/core/planner.py").read_text(encoding="utf-8")
    for rule in (_decoder_rule, _mapping_rule):
        once = rule(source)
        if once is not None:
            assert once != source
            assert rule(once) is None


def test_generated_patches_pass_git_parser_and_restore(tmp_path, monkeypatch):
    target = tmp_path / "apex/core/planner.py"
    target.parent.mkdir(parents=True)
    target.write_text(Path("apex/core/planner.py").read_text(encoding="utf-8"))
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "add", "."], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "-c", "user.name=Test",
                    "-c", "user.email=test@example.invalid",
                    "commit", "-qm", "fixture"], check=True)
    monkeypatch.setattr(rsi, "REPO_ROOT", tmp_path)
    proposals = generate(tmp_path)
    assert 0 <= len(proposals) <= 2
    assert len({p.rule for p in proposals}) == len(proposals)
    for item in proposals:
        assert item.patch.startswith("--- a/apex/core/planner.py\n")
        assert rsi._validate_patch(item.patch)
        assert rsi._apply_patch(item.patch)
        subprocess.run(["git", "-C", str(tmp_path),
                        "checkout", "--", "apex/core/planner.py"], check=True)


def test_no_rules_when_source_has_no_patterns(tmp_path):
    target = tmp_path / "apex/core/planner.py"
    target.parent.mkdir(parents=True)
    target.write_text("_MAX_STEPS = 32\n")
    assert generate(tmp_path) == []


def test_holdout_corpus_and_resources():
    from apex.rsi_offline_bench import measure
    train = measure("train", rounds=3, cases=70, type_cases=100)
    holdout = measure("holdout", rounds=3, cases=70, type_cases=100)
    assert train["dataset"] == "train"
    assert holdout["dataset"] == "holdout"
    assert train["work_units_per_round"] == holdout["work_units_per_round"] == 170
    assert train["provider_calls"] == holdout["provider_calls"] == 0
    assert all(x["cpu_ms"] > 0 and x["peak_rss_kib"] > 0 for x in (train, holdout))


def test_resource_regressions_rejected_even_if_latency_faster():
    before = {"cpu_ms": 100, "peak_rss_kib": 15000, "work_units_per_round": 100}
    assert not rsi._resource_guard(before, {**before, "cpu_ms": 106})
    assert not rsi._resource_guard(before, {**before, "peak_rss_kib": 18000})
    assert not rsi._resource_guard(before, {**before, "work_units_per_round": 99})
    assert not rsi._resource_guard(before, {"cpu_ms": 90, "peak_rss_kib": 15000})
    assert rsi._resource_guard(before, {**before, "cpu_ms": 95, "peak_rss_kib": 15200})


def test_ledger_fails_closed_without_verified_production_volume():
    sample = {"rsi_results": [{
        "outcome": "ACCEPTED_REVIEW_REQUIRED",
        "holdout_baseline": {"p50_ms": 100, "p95_ms": 130,
                             "cpu_ms": 92, "peak_rss_kib": 10000,
                             "work_units_per_round": 500},
        "holdout_candidate": {"p50_ms": 80, "p95_ms": 121,
                              "cpu_ms": 73, "peak_rss_kib": 10000,
                              "work_units_per_round": 500}}],
        "elapsed_seconds": 60, "generator": "rules", "provider_calls": 0}
    roi = evaluate(sample)
    assert roi["status"] == "LAB_IMPROVEMENT_ROI_UNVERIFIED"
    assert roi["realized_operational_roi"] == "UNVERIFIED"
    assert roi["amortization_break_even_rounds"] == 3000
    negative = evaluate(sample, scenario_rounds=2000)
    positive = evaluate(sample, scenario_rounds=4000)
    assert negative["scenario_net_status"] == "HYPOTHETICAL_NEGATIVE"
    assert positive["scenario_net_status"] == "HYPOTHETICAL_POSITIVE"
    assert negative["realized_operational_roi"] == positive["realized_operational_roi"] == "UNVERIFIED"
    assert negative["observed_real_workload_rounds"] is None


@pytest.mark.host_isolation
def test_rules_mode_is_model_free_and_stops_when_source_exhausted(tmp_path, monkeypatch, capsys):
    target = tmp_path / "apex/core/planner.py"
    target.parent.mkdir(parents=True)
    target.write_text("_MAX_STEPS = 32\n")
    subprocess.run(["git", "init", "-b", "main", "-q", str(tmp_path)], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "add", "."], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "-c", "user.name=Test",
                    "-c", "user.email=test@example.invalid",
                    "commit", "-qm", "fixture"], check=True)
    monkeypatch.setattr(rsi, "REPO_ROOT", tmp_path)
    monkeypatch.setattr(rsi, "_generate_patch",
                        lambda *a, **k: pytest.fail("rules invoked model generator"))
    rsi.run_rsi(3, 20000, str(tmp_path / "unused.json"), False, "", generator="rules")
    output = json.loads(capsys.readouterr().out)
    assert output["accepted_branches"] == []
    assert output["provider_calls"] == 0
    assert output["stop_reason"] == "CONVERGED_NO_CANDIDATES"
