"""Run with python -I in a clean venv, outside both source checkouts."""
from importlib import metadata, resources
from pathlib import Path
import os
import sys
from unittest.mock import patch

import apex
import rag
from rag import http_client, remote
from apex.core.rag import store, pipeline
from apex.core.rag.config import load_config
from apex._rsi_sandbox import run
from apex import rsi

expected_apex = os.environ["APEX_EXPECTED_VERSION"]
for name, version, module in [('axiom-rag', '1.5.0', rag), ('axiom-apex', expected_apex, apex)]:
    assert metadata.version(name) == version
    assert Path(module.__file__).resolve().is_relative_to(Path(sys.prefix).resolve())
assert resources.files('apex').joinpath('prompt.txt').read_text()
assert store.create_collection is remote.create_collection
assert pipeline.query is remote.query
with patch.dict('os.environ', {'RAG_BASE_URL': 'http://127.0.0.1:8000'}):
    with patch.object(http_client.Client, 'create', return_value={'created': True}) as call:
        assert store.create_collection(load_config(gemini_api_key='')) == {'created': True}
        call.assert_called_once_with()
print(f"PASS: installed APEX {expected_apex} with RAG 1.5.0, prompt and RSI imports; no provider calls")
