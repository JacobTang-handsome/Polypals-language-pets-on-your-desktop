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
    parser.add_argument("--aliases", default="", help="comma-separated alias=source clip mappings")
    parser.add_argument("--reverse-actions", default="", help="comma-separated action=source reversed rows")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--contact-sheet", type=Path)
    args = parser.parse_args()

    actions = [value.strip() for value in args.actions.split(",") if value.strip()]
    if not actions:
        raise SystemExit("at least one action is required")
    aliases = parse_mappings(args.aliases)
    reverse_actions = parse_mappings(args.reverse_actions)

    cell_width, cell_height, columns = 192, 208, 6
    atlas = Image.new("RGBA", (cell_width * columns, cell_height * len(actions)), (0, 0, 0, 0))
    clips = []
    for row, action in enumerate(actions):
        source_action = reverse_actions.get(action, action)
        frame_dir = args.frames_root / source_action / "idle"
        frames = sorted(frame_dir.glob("*.png"))
        if len(frames) != columns:
            raise SystemExit(f"{action}: expected {columns} extracted frames from {source_action}, found {len(frames)}")
        if action in reverse_actions:
            frames.reverse()
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

    rows_by_action = {clip["id"]: clip["row"] for clip in clips}
    for alias, source in aliases.items():
        if source not in rows_by_action:
            raise SystemExit(f"{alias}: unknown alias source {source}")
        clips.append({
            "id": alias,
            "row": rows_by_action[source],
            "frameCount": columns,
            "secondsPerFrame": 0.16,
            "loops": alias in {"nap", "perchSit", "solPerchTailWag", "mousseElegantSit", "ashSlowSquint"},
            "interruptible": True,
            "fallback": fallback(alias),
            "anchorX": 0.5,
            "anchorY": 0.15 if alias.startswith("perch") or "Perch" in alias else 0.08,
        })

    args.output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(args.output, "WEBP", lossless=True, quality=100, method=6)
    if args.contact_sheet:
        make_contact_sheet(atlas, actions, args.contact_sheet, cell_height)
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


def parse_mappings(raw: str) -> dict[str, str]:
    result = {}
    for value in (part.strip() for part in raw.split(",")):
        if not value:
            continue
        if "=" not in value:
            raise SystemExit(f"invalid mapping: {value}")
        key, source = (part.strip() for part in value.split("=", 1))
        result[key] = source
    return result


def make_contact_sheet(atlas: Image.Image, actions: list[str], output: Path, cell_height: int) -> None:
    label_width = 170
    sheet = Image.new("RGBA", (atlas.width + label_width, atlas.height), "white")
    sheet.alpha_composite(atlas, (label_width, 0))
    from PIL import ImageDraw
    draw = ImageDraw.Draw(sheet)
    for row, action in enumerate(actions):
        y = row * cell_height
        draw.rectangle((0, y, sheet.width - 1, y + cell_height - 1), outline=(205, 205, 205, 255))
        draw.text((12, y + 12), action, fill=(28, 28, 28, 255))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, "PNG")


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
