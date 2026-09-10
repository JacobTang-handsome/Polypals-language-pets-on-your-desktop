# PolyPals 0.4 implementation status

## Delivered

- Native Swift 6 macOS 14+ arm64 app with Bundle ID `com.polypals.PolyPals`
- Three independent non-activating transparent pet panels with drag, edge snap, display-UUID position restore, visibility, sleep, scale, Spaces behavior, and display-change clamping
- Versioned SwiftData schema partitioned by pet for profiles, memory, chat, inventory, cards, interactions, plans, window state, and local metrics; v2 model hashes are frozen and v2→v3 adds companion records with a pre-migration backup
- Additive V4 language-profile records preserve frozen legacy schemas and migrate `Advanced` to C1 without replacing user stores
- Typed CEFR policies flow into chat and card requests; card selection and validation use compatible ranges rather than string equality
- Declarative `.polypals-pack` validation and atomic offline installation share `PolyPalsPluginKit` with the `validate-pack` command
- Local-only confirmed memories, editable memory proposals, per-pet chat history controls, inventory/gifts, seven-level non-decaying familiarity, daily award limits, and transactional pet reset
- Fixed-endpoint OpenAI and DeepSeek Responses clients with provider-isolated BYOK Keychain storage, `store: false`, bounded local context, SSE chat, strict per-card-type schema, one retry, and reviewed offline fallbacks
- Seven finite card types with 126 reviewed seeds (42 per pet), feedback-aware topic rotation, cross-modal encounter history, quality-gated AI variations, sourced culture cards, original dialogue, bundled picture prompts, system TTS, JSON content-pack import, and explicit package endings
- Character-specific chat panels with editing/resend, stop generation, categorized errors, correction disclosure cards, context preview, temporary no-save mode, and editable favorites
- Time-aware ambient actions, relationship-aware greetings, inventory context, “today happened” summaries, natural-language plans, execution history, snooze/skip, and menu-bar focus timers
- Manual, natural-pause, and occasional-invite modes; focus timer; deterministic global suppression/priority/cooldown/decline policy; per-pet quiet hours; daily and weekly plans
- Separate runtime-action/system-notification delivery with delayed permission request, collision suppression, deep link, snooze, skip, cancel, pause, and denied-permission fallback
- Manual presentation mode; no screen-content, code, clipboard, or microphone access; optional user-initiated Accessibility window-position access; local aggregate metrics; and data export/clear controls
- Simplified Chinese String Catalog with automated key synchronization and CI checking
- Three unified soft-picture-book v2 pet atlases and manifests, plus deterministic, visual, continuity, and three-reviewer blind-direction QA artifacts

## Verification completed

- `swift test`: 61 tests in 16 suites passed, including V1→V4 store migrations, CEFR/card policy, malicious plugin fixtures, base/behavior asset checks, window selection, state transitions, pointer throttling, and provider contracts
- Release build: arm64 Mach-O, macOS 14 minimum, ad-hoc signature verified
- Bundle identifier: `com.polypals.PolyPals`
- Three packaged atlases: 1536×2288 RGBA WebP, 8×11, `spriteVersionNumber: 2`, zero transparent RGB residue
- Natural-life behavior uses a cancellable state machine with window/screen-edge perch targets, deterministic candidate selection, Accessibility-gated cross-app window discovery, multi-display coordinate conversion, one-pet perch reservation, and safe screen-edge fallback.
- Additional personality and perch animations are optional sidecar atlases (`*-behavior-spritesheet.webp` + `*-behavior.json`); the existing v2 8×11 contract remains unchanged and each clip declares timing, looping, anchor, interruptibility, and a safe legacy fallback.
- The sidecar atlas is deterministically assembled from six-frame extracted rows. `perchExit` reverses `perchEnter`; Mousse and Ash reuse their restrained pride/wing gestures for celebration, and edge walking intentionally falls back to the existing direction-correct v2 running rows.
- Direct interaction, chat/detail panels, invitations, answer generation, presentation mode, sleep, hiding, and screen changes cancel ambient state and its timers. Keyboard or pointer activity inside eight seconds suppresses a new natural action; overall cadence is capped at once per ten minutes after a fifteen-minute interaction idle period.
- GUI smoke test: final SpriteKit pet, quick menu, five-section detail panel, finite offline cards, chat focus, plan controls, and explicit bundled portraits render successfully
- Short idle sample with all three pet windows: 0.0–1.5% CPU and about 108 MB resident memory
- Local DMG passes `hdiutil verify`

## Release-owner prerequisites

The checked-in release workflow is ready, but a public downloadable build still requires a Developer ID Application certificate and a configured `xcrun notarytool` Keychain profile. Local DMGs are intentionally ad-hoc-signed and are only for local testing. Complete the physical-device matrix in `RELEASE.md` before public distribution.

### Content-pack JSON

```json
{
  "schemaVersion": 1,
  "pack": { "id": "my-pack", "title": "My pack", "version": "1.0", "author": "Author", "language": "es", "license": "CC BY 4.0" },
  "cards": [
    {
      "petId": "sol", "type": "expression", "language": "es", "level": "B1",
      "estimatedSeconds": 45, "hook": "A short hook", "targetText": "echar una mano",
      "prompt": "What does it mean?", "choices": ["help", "leave"], "answer": "help",
      "chineseHelp": "表示帮忙。", "sourceTitle": null, "sourceURL": null,
      "memoryKey": "custom:echar-una-mano", "tags": ["dailyLife"], "conceptKey": "custom:echar-una-mano",
      "originMemoryKey": null, "modality": "expression", "challenge": 0
    }
  ]
}
```
