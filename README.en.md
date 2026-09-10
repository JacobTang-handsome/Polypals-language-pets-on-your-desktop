# PolyPals

简体中文 | English

PolyPals 0.4 is a native macOS 14+ desktop companion app with three independent bilingual pets: Sol (Spanish), Mousse (French), and Ash (English). Each pet has its own non-activating desktop window, profile, routine, chat history, confirmed memories, inventory, plans, relationship progress, position, and notification preferences.

The product is intentionally local-first. It does not request screen recording, Accessibility, or microphone access. Chat supports user-supplied OpenAI and DeepSeek API keys, stored in separate local Keychain entries. Every Responses API request sets `store: false`; endpoints are fixed to the providers' official APIs.

## Requirements

- Apple Silicon Mac
- macOS 14 or newer
- Xcode 16 / Swift 6

## Develop

Open `Package.swift` in Xcode, or run:

```sh
swift build
swift test
swift run PolyPals
```

The package has no third-party runtime dependencies. A network connection is only needed for optional model-backed chat and card variations; 126 reviewed seed cards remain available offline. Each pet's pool contains 42 cards (six per card type), with feedback-aware rotation, cross-modal encounters, and optional AI supplementation.

## Screenshots

Release screenshots belong in `Design/Screenshots/`; do not commit local test captures or private desktop content.

## v0.4 features

- OpenAI and DeepSeek BYOK with separate Keychain slots and a connection test
- Seven non-decaying familiarity levels per pet; points are capped per day
- Time-aware ambient actions and a small, character-specific chat panel
- Card feedback, topic preferences, AI quality gating, local cache pruning, and JSON content-pack import
- Per-pet CEFR A1–C2 profiles with separate receptive/productive levels, fixed or conservative adaptive mode, and range-aware cards
- Declarative content and pet packs with offline validation, SHA-256 integrity, atomic installation, examples, schemas, and a shared CLI validator
- Natural-language schedules, execution history, snooze/skip actions, global invitation limits, and menu-bar 25/50-minute focus timers
- SwiftData V1 → V4 migration with pre-migration backup; existing model hashes stay frozen and language settings use an additive companion record

## API keys and privacy

Choose OpenAI or DeepSeek in Settings and paste that provider's key. Keys are kept in separate macOS Keychain entries, never in SwiftData, exports, logs, snapshots, or the repository. Only the selected provider receives a bounded request. Unconfirmed memory is not uploaded. See [PRIVACY.md](PRIVACY.md).

## Build a local application bundle

```sh
Scripts/build-app.sh
open Distribution/PolyPals.app
```

`Scripts/build-app.sh` creates an ad-hoc-signed arm64 application bundle for local testing. Release signing and notarization require credentials that are intentionally absent from the repository.

For an explicitly local, ad-hoc-signed disk image:

```sh
Scripts/build-local-dmg.sh
```

Do not redistribute the `-local.dmg` as a release build. A public build requires Developer ID signing and notarization:

```sh
POLYPALS_SIGNING_IDENTITY='Developer ID Application: …' \
POLYPALS_NOTARY_PROFILE='polypals-notary' \
Scripts/sign-and-notarize.sh
```

## Project layout

- `Sources/PolyPals`: app, persistence, model client, scheduler, notifications, and UI
- `Sources/PolyPalsPluginKit`: stable public manifest and pack validation boundary
- `Sources/ValidatePack`: community-facing validation command
- `Examples` and `Schemas`: importable content/pet examples and matching JSON Schemas
- `Tests`: deterministic domain, persistence, network-contract, and UI-state tests
- `Design/References`: source references retained as design inputs only
- `Design/PetRuns`: reproducible hatch-pet generation and QA artifacts
- `Sources/PolyPals/Resources/Pets`: packaged v2 sprite atlases and manifests

See [PRIVACY.md](PRIVACY.md) for the data boundary and [RELEASE.md](RELEASE.md) for the release checklist.
Chinese setup and daily-use instructions are in [使用指南.md](使用指南.md).

## Plugins and contributing

Read [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md) or [插件开发指南.md](插件开发指南.md), then validate both examples with `Tools/validate-pack`. Contribution rules are in [CONTRIBUTING.md](CONTRIBUTING.md); report vulnerabilities through GitHub Security Advisories as described in [SECURITY.md](SECURITY.md).

## Current limits

PolyPals does not load dynamic libraries, run plugin scripts, expose runtime model-provider plugins, sync memory to a cloud account, or configure Developer ID/notarization credentials. Pet packs are declarative assets and metadata; they cannot replace the stable built-in Sol, Mousse, or Ash IDs.

## Licensing

Source code is offered under Apache-2.0. Example content is CC BY 4.0 and the generated blank pet-atlas fixture is CC0. Built-in character designs, source references, and artwork are not automatically relicensed by the code license; do not redistribute them without an explicit asset grant.
