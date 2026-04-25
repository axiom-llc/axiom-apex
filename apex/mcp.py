"""MCP client adapter — wraps MCP server tools as native APEX Tool instances."""
from __future__ import annotations

import json
import sys
from typing import Any

import requests

from apex.core.types import Tool

_CONNECT_TIMEOUT = 5
_CALL_TIMEOUT = 60


def _list_tools(base_url: str) -> list[dict]:
    """Call tools/list on an MCP server. Returns raw tool defs."""
    resp = requests.post(
        f"{base_url}/tools/list",
        json={},
        timeout=_CONNECT_TIMEOUT,
    )
    resp.raise_for_status()
    return resp.json().get("tools", [])


def _make_effect(base_url: str, tool_name: str):
    def effect(args: dict) -> dict:
        resp = requests.post(
            f"{base_url}/tools/call",
            json={"name": tool_name, "arguments": args},
            timeout=_CALL_TIMEOUT,
        )
        resp.raise_for_status()
        data = resp.json()
        # MCP returns {content: [{type, text}], isError: bool}
        content = data.get("content", [])
        text = " ".join(c.get("text", "") for c in content if c.get("type") == "text")
        if data.get("isError"):
            raise RuntimeError(text or "MCP tool error")
        return {"output": text, "raw": content}
    return effect


def _spec_from_schema(schema: dict) -> dict[str, type]:
    type_map = {"string": str, "integer": int, "number": float, "boolean": bool, "object": dict, "array": list}
    props = schema.get("properties", {})
    return {k: type_map.get(v.get("type", "string"), str) for k, v in props.items()}


def load_mcp_servers(server_configs: list[dict]) -> dict[str, Tool]:
    """
    Given a list of {name, url} dicts, connect to each MCP server,
    enumerate tools, and return a registry dict of namespaced Tool instances.
    """
    registry: dict[str, Tool] = {}
    for cfg in server_configs:
        server_name = cfg.get("name", "mcp")
        base_url = cfg.get("url", "").rstrip("/")
        if not base_url:
            print(f"[mcp] skipping '{server_name}': no url", file=sys.stderr)
            continue
        try:
            tool_defs = _list_tools(base_url)
        except Exception as e:
            print(f"[mcp] skipping '{server_name}' ({base_url}): {e}", file=sys.stderr)
            continue
        for td in tool_defs:
            raw_name = td.get("name", "")
            if not raw_name:
                continue
            namespaced = f"mcp__{server_name}__{raw_name}"
            input_spec = _spec_from_schema(td.get("inputSchema", {}))
            tool = Tool(
                name=namespaced,
                input_spec=input_spec,
                output_spec={"output": str, "raw": list},
                effect=_make_effect(base_url, raw_name),
            )
            registry[namespaced] = tool
        print(f"[mcp] '{server_name}': loaded {len(tool_defs)} tools", file=sys.stderr)
    return registry


def mcp_tool_docs(registry: dict[str, Tool]) -> str:
    """Generate prompt.txt-style doc lines for all MCP tools."""
    lines = []
    for name, tool in registry.items():
        args_str = ", ".join(f"{k}: {v.__name__}" for k, v in tool.input_spec.items())
        lines.append(f"- {name}: MCP tool. args: {{{args_str}}}. returns: {{output, raw}}")
    return "\n".join(lines)
