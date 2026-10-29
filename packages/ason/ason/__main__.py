"""ASON CLI entry point."""
from __future__ import annotations
import json
import os
import sys


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "submit":
        from ason.schema import ASONRequest
        from ason.executor import ASONExecutor
        if len(sys.argv) < 3:
            print(
                "usage: ason submit <json_file_or_-> [--apex-url URL] "
                "[--authority-ref REF]",
                file=sys.stderr,
            )
            sys.exit(1)
        src = sys.argv[2]
        raw = sys.stdin.read() if src == "-" else open(src).read()
        apex_url = os.environ.get("APEX_URL", "http://127.0.0.1:8080")
        authority_ref = os.environ.get("ASON_AUTHORITY_REF")
        if "--apex-url" in sys.argv:
            apex_url = sys.argv[sys.argv.index("--apex-url") + 1]
        if "--authority-ref" in sys.argv:
            authority_ref = sys.argv[sys.argv.index("--authority-ref") + 1]
        req = ASONRequest.model_validate(json.loads(raw))
        ex = ASONExecutor(
            apex_url=apex_url,
            api_key=os.environ.get("APEX_API_KEY"),
            authority_ref=authority_ref,
        )
        result = ex.submit(req)
        print(json.dumps(result, indent=2))
        response = result.get("apex_response") or {}
        sys.exit(0 if result.get("accepted") and not result.get("error") and response.get("exit_code") == 0 else 1)

    print("ASON 0.3.0")
    print("subcommands: submit")
    sys.exit(0)


if __name__ == "__main__":
    main()
