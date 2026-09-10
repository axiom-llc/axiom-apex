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
