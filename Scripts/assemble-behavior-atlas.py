#!/usr/bin/env python3
"""Deterministically assemble already-extracted behavior frames into a sidecar atlas."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames-root", required=True, type=Path)
    parser.add_argument("--pet-id", required=True)
    parser.add_argument("--actions", required=True, help="comma-separated row order")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    args = parser.parse_args()

    actions = [value.strip() for value in args.actions.split(",") if value.strip()]
    if not actions:
        raise SystemExit("at least one action is required")

    cell_width, cell_height, columns = 192, 208, 6
    atlas = Image.new("RGBA", (cell_width * columns, cell_height * len(actions)), (0, 0, 0, 0))
    clips = []
    for row, action in enumerate(actions):
        frame_dir = args.frames_root / action / "idle"
        frames = sorted(frame_dir.glob("*.png"))
        if len(frames) != columns:
            raise SystemExit(f"{action}: expected {columns} extracted frames, found {len(frames)}")
        for column, path in enumerate(frames):
            frame = Image.open(path).convert("RGBA")
            if frame.size != (cell_width, cell_height) or frame.getbbox() is None:
                raise SystemExit(f"{action}: invalid frame {path}")
            atlas.alpha_composite(frame, (column * cell_width, row * cell_height))
        clips.append({
            "id": action,
            "row": row,
            "frameCount": columns,
            "secondsPerFrame": 0.16,
            "loops": action in {"nap", "perchSit", "solPerchTailWag", "ashSlowSquint"},
            "interruptible": True,
            "fallback": fallback(action),
            "anchorX": 0.5,
            "anchorY": 0.15 if action.startswith("perch") or "Perch" in action else 0.08,
        })

    args.output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(args.output, "WEBP", lossless=True, quality=100, method=6)
    manifest = {
        "version": 1,
        "petID": args.pet_id,
        "cellWidth": cell_width,
        "cellHeight": cell_height,
        "columns": columns,
        "spritesheetPath": f"{args.pet_id}-behavior-spritesheet.webp",
        "clips": clips,
    }
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def fallback(action: str) -> str:
    if action in {"stretch", "celebrate", "perchEnter", "perchExit"}:
        return "jumping"
    if action == "perchWalkLeft":
        return "runningLeft"
    if action == "perchWalkRight":
        return "runningRight"
    if action == "ashInviteWing":
        return "waving"
    if action in {"solPouncePrep", "mousseGroom", "ashHeadTilt"}:
        return "review"
    if action in {"solEarTwitch", "mousseProud"}:
        return "waiting"
    return "idle"


if __name__ == "__main__":
    main()
