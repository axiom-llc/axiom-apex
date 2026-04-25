"""Tool autoloading — scans a directory for Tool instances and merges into registry."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from apex.core.types import Tool


def load_tools_dir(directory: Path) -> dict[str, Tool]:
    """
    Import all .py files in directory, collect Tool instances at module level.
    Returns dict[tool_name, Tool]. Skips files that fail to import.
    """
    tools: dict[str, Tool] = {}
    if not directory.exists():
        return tools

    for py_file in sorted(directory.glob("*.py")):
        module_name = f"_apex_user_tool_{py_file.stem}"
        spec = importlib.util.spec_from_file_location(module_name, py_file)
        if spec is None or spec.loader is None:
            continue
        module = importlib.util.module_from_spec(spec)
        sys.modules[module_name] = module
        try:
            spec.loader.exec_module(module)
        except Exception as e:
            print(f"[toolloader] skipping {py_file.name}: {e}", flush=True)
            continue
        for attr_name in dir(module):
            obj = getattr(module, attr_name)
            if isinstance(obj, Tool):
                tools[obj.name] = obj

    return tools
