"""Host-side lifetime checks independent of the candidate's private filesystem."""
from pathlib import Path
import time
from types import SimpleNamespace
import uuid

import pytest


@pytest.fixture(autouse=True)
def resource_scopes_are_empty(request, monkeypatch):
    if request.node.get_closest_marker('host_isolation') is None:
        yield
        return
    from apex import _rsi_sandbox as sandbox
    units = []

    def identifier():
        value = uuid.uuid4()
        units.append(f'axiom-rsi-{value.hex}.scope')
        return value

    monkeypatch.setattr(sandbox, 'uuid', SimpleNamespace(uuid4=identifier))
    yield
    deadline = time.monotonic() + 3
    while True:
        populated = []
        for unit in units:
            for group in Path('/sys/fs/cgroup').rglob(unit):
                try:
                    if 'populated 1' in (group / 'cgroup.events').read_text():
                        populated.append(str(group))
                except FileNotFoundError:
                    pass  # The kernel removed the now-empty scope.
        if not populated or time.monotonic() >= deadline:
            break
        time.sleep(0.02)
    assert not populated, f'candidate descendants survived: {populated}'


@pytest.fixture
def http_rag_config(tmp_path, monkeypatch):
    """Real isolated server store behind the public HTTP wire adapter."""
    import io
    from apex.core.rag.config import load_config
    import server.app as api

    monkeypatch.setenv('HOME', str(tmp_path))
    monkeypatch.setenv('RAG_BASE_URL', 'http://test')
    for key in ('RAG_HTTP_NAMESPACES', 'RAG_HTTP_GENERATION_MODELS', 'RAG_GENERATION_MODEL'):
        monkeypatch.delenv(key, raising=False)
    cfg = load_config(gemini_api_key='', chroma_path='~/.rag/chroma',
                      collection_name='documents-gemini-embedding-2', embedding_dimension=3072)
    from dataclasses import replace
    monkeypatch.setattr(api, '_config', replace(cfg, gemini_api_key='server-test-only'))
    monkeypatch.setattr(api, '_api_token', '')
    http = api.app.test_client()

    def call(self, request, timeout):
        assert b'gemini_api_key' not in request.data and b'chroma_path' not in request.data
        response = http.post(request.full_url.removeprefix('http://test'),
                             data=request.data, headers=dict(request.header_items()))
        value = io.BytesIO(response.data)
        value.code = response.status_code
        return value

    from urllib.request import OpenerDirector
    monkeypatch.setattr(OpenerDirector, 'open', call)
    return cfg
