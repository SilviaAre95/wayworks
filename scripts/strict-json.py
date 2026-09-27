#!/usr/bin/env python3
"""Exit 0 only if the input is exactly one JSON object, as JSON.parse reads it.

jq is too lenient to be the parse gate: it accepts several top-level
documents, whitespace-only input (zero documents) and bare `nan`, all of which
Claude Code's loader rejects. Those shapes passed every jq-based check.

Usage: strict-json.py <file>   or   strict-json.py - < input
"""
import json
import sys


def reject_constant(name):
    raise ValueError(f"{name} is not JSON")


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "-"
    try:
        text = sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()
        # json.loads rejects trailing data ("Extra data") and empty input.
        doc = json.loads(text, parse_constant=reject_constant)
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        print(f"{path}: not strict JSON: {exc}", file=sys.stderr)
        return 1
    if not isinstance(doc, dict):
        print(f"{path}: top level is {type(doc).__name__}, not an object", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
