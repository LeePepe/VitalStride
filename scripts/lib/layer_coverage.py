#!/usr/bin/env python3
"""Resolve repository paths through recursively linked CONTEXT.md files."""

from __future__ import annotations

import argparse
import fnmatch
import json
import shlex
import subprocess
import sys
from pathlib import PurePosixPath

from frontmatter import parse_block_list, parse_list, parse_routes, parse_scalar, read_frontmatter


ROOT_CONTEXT = "CONTEXT.md"


class RouteError(ValueError):
    pass


def matches(path: str, pattern: str) -> bool:
    if any(char in pattern for char in "*?["):
        return fnmatch.fnmatchcase(path, pattern) or PurePosixPath(path).match(pattern)
    return path == pattern or path.startswith(pattern.rstrip("/") + "/")


def load_context(path: str) -> dict:
    fm = read_frontmatter(path)
    if fm is None:
        raise RouteError(f"{path}: missing frontmatter")
    return {
        "path": path,
        "scope": parse_scalar(fm, "scope"),
        "layer": parse_scalar(fm, "layer"),
        "paths": parse_list(fm, "paths"),
        "test_paths": parse_list(fm, "test_paths"),
        "routes": parse_routes(fm),
        "support_excludes": parse_list(fm, "support_excludes"),
        "generated_excludes": parse_list(fm, "generated_excludes"),
        "gate_tier": parse_scalar(fm, "gate_tier"),
        "build": parse_scalar(fm, "build"),
        "test": parse_scalar(fm, "test"),
        "depends_on": parse_list(fm, "depends_on"),
        "red_lines": parse_block_list(fm, "red_lines"),
    }


def resolve(path: str, context_path: str = ROOT_CONTEXT, stack: tuple[str, ...] = ()) -> dict:
    if context_path in stack:
        raise RouteError(f"context cycle: {' -> '.join(stack + (context_path,))}")
    node = load_context(context_path)
    exclusions = [
        pattern
        for pattern in node["support_excludes"] + node["generated_excludes"]
        if matches(path, pattern)
    ]
    if exclusions:
        return {"path": path, "excluded": exclusions, "context_chain": stack + (context_path,)}

    if node["routes"]:
        routes = [route for route in node["routes"] if any(matches(path, p) for p in route["paths"])]
        if not routes:
            raise RouteError(f"unmapped at {context_path}: {path}")
        if len(routes) > 1:
            raise RouteError(f"route overlap at {context_path}: {path} -> {[r['context'] for r in routes]}")
        route = routes[0]
        child = route.get("context", "")
        if not child:
            raise RouteError(f"{context_path}: route for {path} has no context")
        result = resolve(path, child, stack + (context_path,))
        if route.get("kind") == "layer" and not result.get("layer") and not result.get("excluded"):
            raise RouteError(f"{context_path}: layer route for {path} did not end at a layer")
        return result

    owners = [pattern for pattern in node["paths"] + node["test_paths"] if matches(path, pattern)]
    if not node["layer"]:
        raise RouteError(f"{context_path}: terminal context has no layer")
    if not owners:
        raise RouteError(f"parent/leaf mismatch at {context_path}: {path}")
    return {
        "path": path,
        "layer": node["layer"],
        "context": context_path,
        "context_chain": stack + (context_path,),
    }


def tracked_files() -> list[str]:
    result = subprocess.run(["git", "ls-files", "-z"], check=True, stdout=subprocess.PIPE)
    return [item.decode() for item in result.stdout.split(b"\0") if item]


def walk_contexts(context_path: str = ROOT_CONTEXT, stack: tuple[str, ...] = ()):
    if context_path in stack:
        raise RouteError(f"context cycle: {' -> '.join(stack + (context_path,))}")
    node = load_context(context_path)
    yield node
    for route in node["routes"]:
        child = route.get("context", "")
        if not child:
            raise RouteError(f"{context_path}: route missing context")
        yield from walk_contexts(child, stack + (context_path,))


def audit(files: list[str]) -> list[str]:
    errors = []
    layers = {}
    try:
        for node in walk_contexts():
            layer = node["layer"]
            if layer:
                if layer in layers and layers[layer] != node["path"]:
                    errors.append(f"duplicate layer id: {layer} -> {layers[layer]}, {node['path']}")
                layers[layer] = node["path"]
                if node["gate_tier"] not in {"local-fast", "ci-only"}:
                    errors.append(f"{node['path']}: invalid gate_tier {node['gate_tier']!r}")
    except (OSError, RouteError) as exc:
        errors.append(str(exc))
        return errors
    for path in files:
        try:
            resolve(path)
        except (OSError, RouteError) as exc:
            errors.append(str(exc))
    return sorted(set(errors))


def find_layer(layer_id: str) -> dict:
    matches_ = [node for node in walk_contexts() if node["layer"] == layer_id]
    if len(matches_) != 1:
        raise RouteError(f"layer id {layer_id!r} resolved to {len(matches_)} contexts")
    return matches_[0]


def read_paths(args) -> list[str]:
    if args.stdin:
        return [line.strip() for line in sys.stdin if line.strip()]
    return args.paths


def emit_run_failure(node: dict, action: str, code: int) -> None:
    signal = {
        "layer": node["layer"],
        "path": node["path"],
        "kind": action,
        "detail": f"{action} command exited {code}",
        "red_lines": node["red_lines"],
    }
    print("::layered-signal::" + json.dumps(signal, ensure_ascii=False))


def parse_run_argv(command: str) -> list[str]:
    if not isinstance(command, str):
        raise ValueError("run command must be a string")
    text = command.strip()
    if not text:
        raise ValueError("run command is empty")
    try:
        argv = shlex.split(text, posix=True)
    except ValueError as exc:
        raise ValueError(f"malformed run command: {exc}") from exc
    if not argv:
        raise ValueError("run command is empty")
    blocked = {"&&", "||", ";", "|", "&", "<", ">", "$", "`"}
    for token in argv:
        if any(char in token for char in ("$", "`")):
            raise ValueError(f"shell expansion rejected: {token!r}")
        if any(char in token for char in ("&", "|", ";", "<", ">")):
            raise ValueError(f"shell control rejected: {token!r}")
        if token in blocked:
            raise ValueError(f"shell control rejected: {token!r}")
    return argv


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    audit_parser = sub.add_parser("audit")
    audit_parser.add_argument("--files-from")
    for name in ("resolve", "layers"):
        command = sub.add_parser(name)
        command.add_argument("paths", nargs="*")
        command.add_argument("--stdin", action="store_true")
    field = sub.add_parser("field")
    field.add_argument("layer")
    field.add_argument("field")
    run = sub.add_parser("run")
    run.add_argument("layer")
    run.add_argument("action", choices=("build", "test"))
    sub.add_parser("contexts")
    args = parser.parse_args(argv)

    try:
        if args.command == "audit":
            files = tracked_files()
            if args.files_from:
                with open(args.files_from, encoding="utf-8") as handle:
                    files = [line.strip() for line in handle if line.strip()]
            errors = audit(files)
            if errors:
                print("\n".join(f"❌ {error}" for error in errors))
                return 1
            print(f"✅ recursive layer coverage: {len(files)} tracked paths classified")
            return 0
        if args.command in {"resolve", "layers"}:
            results = [resolve(path) for path in read_paths(args)]
            if args.command == "resolve":
                for result in results:
                    print(json.dumps(result, ensure_ascii=False))
            else:
                for layer in sorted({result["layer"] for result in results if result.get("layer")}):
                    print(layer)
            return 0
        if args.command == "contexts":
            for node in walk_contexts():
                if node["layer"]:
                    print(node["path"])
            return 0
        node = find_layer(args.layer)
        if args.command == "field":
            value = node["path"] if args.field == "context" else node.get(args.field, "")
            print(json.dumps(value, ensure_ascii=False) if isinstance(value, list) else value)
            return 0
        command = node.get(args.action, "")
        if not command:
            return 0
        try:
            argv = parse_run_argv(command)
        except ValueError as exc:
            print(f"❌ {exc}")
            return 1
        completed = subprocess.run(argv, shell=False)
        if completed.returncode:
            emit_run_failure(node, args.action, completed.returncode)
        return completed.returncode
    except (OSError, RouteError) as exc:
        print(f"❌ {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
