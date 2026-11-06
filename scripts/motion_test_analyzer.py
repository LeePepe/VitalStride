#!/usr/bin/env python3
"""Deterministic motion metrics and review artifacts for frame-sequence tests."""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from pathlib import Path
from typing import Any, Iterable, Sequence


def _flat(value: Any) -> list[float]:
    if isinstance(value, (int, float)):
        return [float(value)]
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
        result: list[float] = []
        for item in value:
            result.extend(_flat(item))
        return result
    raise TypeError("frame values must be numeric, 1D, or 2D sequences")


def _distance(left: Any, right: Any) -> float:
    a, b = _flat(left), _flat(right)
    if len(a) != len(b):
        raise ValueError("all frames must have the same shape")
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def _similarity(left: Any, right: Any) -> float:
    a, b = _flat(left), _flat(right)
    if len(a) != len(b):
        raise ValueError("all frames must have the same shape")
    if not a:
        return 1.0
    scale = max(max(a), max(b), 1.0) - min(min(a), min(b), 0.0)
    return max(0.0, 1.0 - sum(abs(x - y) for x, y in zip(a, b)) / len(a) / scale)


def _progress(frames: Sequence[Any]) -> list[float]:
    if len(frames) < 2:
        return [0.0] * len(frames)
    total = _distance(frames[0], frames[-1])
    if total == 0:
        return [0.0] * len(frames)
    return [max(0.0, min(1.0, _distance(frames[0], frame) / total)) for frame in frames]


def zero_frame_hard_cut(frames: Sequence[Any]) -> dict[str, Any]:
    """Measure intermediate frames and flag a transition with at most one."""
    progress = _progress(frames)
    intermediate = [p for p in progress[1:-1] if 0.02 < p < 0.98]
    return {
        "metric": "zero_frame_hard_cut",
        "intermediate_frames": len(intermediate),
        "progress": progress,
        "detected": len(intermediate) <= 1,
    }


def double_jump_jitter(
    frames: Sequence[Any] | None = None,
    *,
    positions: Sequence[Any] | None = None,
) -> dict[str, Any]:
    """Detect velocity reversals or two separated frame-difference peaks."""
    if positions is not None:
        values = [_flat(item)[0] for item in positions]
        progress = _progress(values)
        velocities = [b - a for a, b in zip(values, values[1:])]
        reversals = [
            i + 1
            for i, (a, b) in enumerate(zip(velocities, velocities[1:]))
            if a * b < 0 and 0.1 <= progress[min(i + 1, len(progress) - 1)] <= 0.85
        ]
    else:
        if frames is None:
            raise ValueError("frames or positions is required")
        progress = _progress(frames)
        velocities = [_distance(a, b) for a, b in zip(frames, frames[1:])]
        reversals = []
    peaks = [
        i for i in range(1, len(velocities) - 1)
        if velocities[i] > velocities[i - 1] and velocities[i] >= velocities[i + 1]
    ]
    separated_peaks = any(
        1 <= (right - left - 1) <= 5 for left, right in zip(peaks, peaks[1:])
    )
    return {
        "metric": "double_jump_jitter",
        "detected": bool(reversals or separated_peaks),
        "velocity_reversals": reversals,
        "difference_peaks": peaks,
        "velocities": velocities,
    }


def one_frame_flicker(frames: Sequence[Any]) -> dict[str, Any]:
    """Use the temporal sandwich score to find isolated frame spikes."""
    scores: list[float] = [0.0]
    for index in range(1, len(frames) - 1):
        score = _similarity(frames[index - 1], frames[index + 1]) - 0.5 * (
            _similarity(frames[index - 1], frames[index])
            + _similarity(frames[index], frames[index + 1])
        )
        scores.append(score)
    if frames:
        scores.append(0.0)
    spikes = [index for index, score in enumerate(scores) if score > 0.13]
    return {
        "metric": "one_frame_flicker",
        "detected": bool(spikes),
        "threshold": 0.13,
        "scores": scores,
        "spikes": spikes,
    }


def frozen_frame_jank(
    timestamps_ms: Sequence[float],
    positions: Sequence[Any],
    *,
    static_delta: float = 0.0,
    pause_ms: float = 100.0,
) -> dict[str, Any]:
    """Find a >100ms static run followed by a spatial catch-up jump."""
    if len(timestamps_ms) != len(positions):
        raise ValueError("timestamps_ms and positions must have the same length")
    runs: list[dict[str, Any]] = []
    for start in range(max(0, len(positions) - 2)):
        end = start
        while end + 1 < len(positions) and _distance(positions[end], positions[end + 1]) <= static_delta:
            end += 1
        if end > start and end + 1 < len(positions):
            elapsed = timestamps_ms[end] - timestamps_ms[start]
            catch_up = _distance(positions[end], positions[end + 1])
            if elapsed > pause_ms and catch_up > static_delta:
                runs.append({"start": start, "end": end, "pause_ms": elapsed, "catch_up": catch_up})
    return {"metric": "frozen_frame_jank", "detected": bool(runs), "runs": runs}


def analyze_motion(
    *,
    frames: Sequence[Any] | None = None,
    timestamps_ms: Sequence[float] | None = None,
    positions: Sequence[Any] | None = None,
) -> dict[str, Any]:
    """Return all four objective metrics as a JSON-compatible record."""
    if frames is None and positions is None:
        raise ValueError("frames or positions is required")
    frame_values = frames if frames is not None else positions
    result = {
        "zero_frame_hard_cut": zero_frame_hard_cut(frame_values),
        "double_jump_jitter": double_jump_jitter(frames, positions=positions),
        "one_frame_flicker": one_frame_flicker(frame_values),
    }
    if timestamps_ms is not None and positions is not None:
        result["frozen_frame_jank"] = frozen_frame_jank(timestamps_ms, positions)
    else:
        result["frozen_frame_jank"] = {
            "metric": "frozen_frame_jank",
            "detected": False,
            "runs": [],
            "skipped": True,
        }
    return result


def _matrix_size(frame: Any) -> tuple[int, int]:
    if isinstance(frame, Sequence) and frame and isinstance(frame[0], Sequence):
        return len(frame), len(frame[0])
    return 1, max(1, len(_flat(frame)))


def render_contact_sheet_svg(
    frames: Sequence[Any],
    *,
    rois: Sequence[tuple[int, int, int, int]] | None = None,
    width: int = 900,
    height: int = 900,
) -> str:
    """Render a deterministic 3x3 grayscale SVG with red #01-#09 labels."""
    if not frames:
        raise ValueError("at least one frame is required")
    selected = [frames[min(len(frames) - 1, round(i * (len(frames) - 1) / 8))] for i in range(9)]
    cell_w, cell_h = width // 3, height // 3
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">']
    for index, frame in enumerate(selected):
        origin_x, origin_y = (index % 3) * cell_w, (index // 3) * cell_h
        values = _flat(frame)
        rows, cols = _matrix_size(frame)
        maximum = max(values) if values else 1.0
        minimum = min(values) if values else 0.0
        scale = maximum - minimum or 1.0
        pixel_w, pixel_h = cell_w / cols, cell_h / rows
        for p, value in enumerate(values[: rows * cols]):
            x, y = p % cols, p // cols
            shade = round(255 * (value - minimum) / scale)
            parts.append(
                f'<rect x="{origin_x + x * pixel_w:g}" y="{origin_y + y * pixel_h:g}" '
                f'width="{pixel_w:g}" height="{pixel_h:g}" fill="rgb({shade},{shade},{shade})"/>'
            )
        if rois and index < len(rois):
            x, y, w, h = rois[index]
            parts.append(f'<rect x="{origin_x + x:g}" y="{origin_y + y:g}" width="{w:g}" height="{h:g}" fill="none" stroke="red" stroke-width="2"/>')
        parts.append(f'<text x="{origin_x + cell_w - 12:g}" y="{origin_y + cell_h - 12:g}" text-anchor="end" fill="red" font-family="monospace" font-size="24" font-weight="bold">#{index + 1:02d}</text>')
    parts.append("</svg>")
    return "".join(parts)


RUBRIC_AXES = ("curve_continuity", "safe_area_keyboard_sync", "row_reorder_coherence", "zero_flicker")


def build_vlm_review_prompt(metrics: dict[str, Any]) -> str:
    return (
        "Review this workout motion transition using the supplied contact sheet and frame sequence. "
        "Return JSON only. Objective CV metrics are prior context:\n"
        f"{json.dumps(metrics, sort_keys=True, separators=(',', ':'))}\n"
        "Score each rubric axis from 0 to 1: " + ", ".join(RUBRIC_AXES) + ". "
        "Use verdict PASS only when all axes are at least 0.8; otherwise use CONCERNS."
    )


def validate_vlm_verdict(verdict: Any) -> dict[str, Any]:
    if not isinstance(verdict, dict) or set(verdict) != {"verdict", "scores", "rationale"}:
        raise ValueError("verdict must contain exactly verdict, scores, and rationale")
    if verdict["verdict"] not in {"PASS", "CONCERNS"}:
        raise ValueError("verdict must be PASS or CONCERNS")
    scores = verdict["scores"]
    if not isinstance(scores, dict) or set(scores) != set(RUBRIC_AXES):
        raise ValueError("scores must contain the four rubric axes")
    if any(not isinstance(value, (int, float)) or not 0 <= value <= 1 for value in scores.values()):
        raise ValueError("scores must be numbers from 0 to 1")
    if not isinstance(verdict["rationale"], str) or not verdict["rationale"].strip():
        raise ValueError("rationale must be a non-empty string")
    expected = "PASS" if all(value >= 0.8 for value in scores.values()) else "CONCERNS"
    if verdict["verdict"] != expected:
        raise ValueError("verdict does not match rubric scores")
    return verdict


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="JSON file containing frames and optional timestamps_ms/positions")
    parser.add_argument("--contact-sheet", type=Path)
    parser.add_argument("--prompt", type=Path)
    args = parser.parse_args(argv)
    payload = json.loads(args.input.read_text(encoding="utf-8"))
    result = analyze_motion(
        frames=payload.get("frames"),
        timestamps_ms=payload.get("timestamps_ms"),
        positions=payload.get("positions"),
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    if args.contact_sheet:
        args.contact_sheet.write_text(render_contact_sheet_svg(payload.get("frames") or payload.get("positions")), encoding="utf-8")
    if args.prompt:
        args.prompt.write_text(build_vlm_review_prompt(result), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
