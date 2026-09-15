from unittest.mock import patch
from types import SimpleNamespace
from apex.providers import GeminiProvider, OllamaProvider, get_provider


def test_gemini_failure_is_single_attempt_and_redacted():
    with patch('google.genai.Client') as client:
        generate = client.return_value.__enter__.return_value.models.generate_content
        generate.side_effect = RuntimeError('secret-key private-prompt')
        result = GeminiProvider('secret-key').complete('private-prompt')
        assert result == {'text': None, 'tokens': 0, 'error': 'Gemini provider request failed'}
        generate.assert_called_once()
        options = client.call_args.kwargs['http_options']
        assert options.timeout == 60000
        assert options.retry_options.attempts == 1
        client.return_value.__exit__.assert_called_once()


def test_gemini_success_preserves_usage():
    with patch('google.genai.Client') as client:
        client.return_value.__enter__.return_value.models.generate_content.return_value = SimpleNamespace(
            text='OK', usage_metadata=SimpleNamespace(total_token_count=7))
        provider = GeminiProvider('key')
        assert provider.complete('test') == {'text': 'OK', 'tokens': 7, 'error': None}
        assert provider.total_tokens == 7


def test_ollama_failure_is_single_attempt_and_redacted():
    with patch('urllib.request.urlopen', side_effect=RuntimeError('private-prompt')) as request:
        assert OllamaProvider().complete('private-prompt')['error'] == 'Ollama provider request failed'
        request.assert_called_once()
        assert request.call_args.kwargs['timeout'] == 300


def test_explicit_gemini_model_overrides_environment(monkeypatch):
    monkeypatch.setenv("GEMINI_MODEL", "env-model")
    provider = GeminiProvider("key", model="resolved-model")
    assert provider._model == "resolved-model"


def test_explicit_ollama_model_overrides_environment(monkeypatch):
    monkeypatch.setenv("OLLAMA_MODEL", "env-model")
    provider = OllamaProvider(model="resolved-model")
    assert provider._model == "resolved-model"


def test_explicit_provider_profile_ignores_later_environment(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "ollama")
    monkeypatch.setenv("GEMINI_MODEL", "env-model")
    provider = get_provider(api_key="key", provider="gemini", model="resolved-model")
    assert isinstance(provider, GeminiProvider)
    assert provider._model == "resolved-model"
