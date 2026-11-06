"""Offline adapter and planner-to-ledger integration coverage."""
import json
from unittest.mock import MagicMock, Mock, patch

import pytest

from apex import history
from apex.chatgpt import ChatGPTProvider
from apex.config import load_config
from apex.core.loop import run
from apex.core.types import Tool
from apex.providers import GeminiProvider, OllamaProvider, get_provider


def response(text, *, status="completed", tokens=7):
    return json.dumps({"status": status, "output": [
        {"type": "message", "content": [{"type": "output_text", "text": text}]}
    ], "usage": {"total_tokens": tokens}}).encode()


def fake_http(body):
    stream = Mock()
    stream.read.return_value = body
    context = MagicMock()
    context.__enter__ = Mock(return_value=stream)
    context.__exit__ = Mock(return_value=None)
    return context


def test_config_selection_and_credentials(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "chatgpt")
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    with pytest.raises(ValueError, match="OPENAI_API_KEY"):
        load_config()
    monkeypatch.setenv("OPENAI_API_KEY", "secret")
    monkeypatch.setenv("OPENAI_MODEL", "chosen-model")
    config = load_config()
    assert (config.provider, config.api_key, config.model) == ("chatgpt", "secret", "chosen-model")
    assert isinstance(get_provider(config.api_key, provider=config.provider, model=config.model), ChatGPTProvider)
    assert isinstance(get_provider("secret", provider="openai"), ChatGPTProvider)
    assert isinstance(get_provider("secret", provider="gemini"), GeminiProvider)
    assert isinstance(get_provider(provider="ollama"), OllamaProvider)


def test_api_request_usage_and_redacted_failure():
    provider = ChatGPTProvider("secret", "test-model")
    with patch("apex.chatgpt.urlopen", return_value=fake_http(response("ok", tokens=13))) as call:
        assert provider.complete("private task") == {"text": "ok", "tokens": 13, "error": None}
    request = call.call_args.args[0]
    assert request.full_url == "https://api.openai.com/v1/responses"
    assert request.get_header("Authorization") == "Bearer secret"
    assert json.loads(request.data) == {"model": "test-model", "input": "private task",
                                      "max_output_tokens": 8192, "store": False}
    assert call.call_args.kwargs["timeout"] == 60
    assert provider.total_tokens == 13
    with patch("apex.chatgpt.urlopen", side_effect=RuntimeError("secret private task")) as call:
        assert provider.complete("private task") == {
            "text": None, "tokens": 0, "error": "ChatGPT provider request failed"}
        call.assert_called_once()
    assert provider.total_tokens == 13


@pytest.mark.parametrize("body", [
    response("{}", status="in_progress"),
    json.dumps({"status": "completed", "output": []}).encode(),
    response("{}", tokens=-2),
    b"invalid json",
])
def test_incomplete_and_invalid_responses_fail_closed(body):
    with patch("apex.chatgpt.urlopen", return_value=fake_http(body)):
        assert ChatGPTProvider("key").complete("x")["text"] is None


def test_chatgpt_plan_executes_once_and_records_ledger(monkeypatch, tmp_path):
    monkeypatch.setattr(history, "DB_PATH", tmp_path / "runs.db")
    monkeypatch.setenv("LLM_PROVIDER", "chatgpt")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("OPENAI_MODEL", "test-model")
    monkeypatch.setenv("APEX_DB_PATH", str(tmp_path / "memory.db"))
    effects = []
    registry = {"append": Tool("append", {"value": str}, {"count": int},
                               lambda args: (effects.append(args["value"]) or {"count": len(effects)}))}
    plan = json.dumps({"goal": "append once", "steps": [
        {"type": "tool", "name": "append", "args": {"value": "ok"}},
        {"type": "halt", "reason": "done"},
    ]})
    with patch("apex.chatgpt.urlopen", return_value=fake_http(response(plan, tokens=9))) as call:
        state = run("append once", config=load_config(), registry=registry)
    assert state.status == "HALTED"
    assert state.run_id is not None
    assert state.token_count == 9
    assert effects == ["ok"]
    assert history.load_run_detail(state.run_id)["ledger"]["plan_digest"]
    call.assert_called_once()


def test_invalid_plan_never_dispatches(monkeypatch, tmp_path):
    monkeypatch.setattr(history, "DB_PATH", tmp_path / "runs.db")
    monkeypatch.setenv("LLM_PROVIDER", "chatgpt")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    effects = []
    registry = {"append": Tool("append", {"value": str}, {"count": int},
                               lambda args: (effects.append(args["value"]) or {"count": len(effects)}))}
    invalid = '{"goal":"x","steps":[]}'
    with patch("apex.chatgpt.urlopen", return_value=fake_http(response(invalid))):
        state = run("x", config=load_config(), registry=registry)
    assert state.status == "ERROR"
    assert effects == []
