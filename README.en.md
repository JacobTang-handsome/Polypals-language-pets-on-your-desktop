# PolyPals

[简体中文](README.md) | English

[![CI](https://github.com/JacobTang-handsome/Polypals-language-pets-on-your-desktop/actions/workflows/ci.yml/badge.svg)](https://github.com/JacobTang-handsome/Polypals-language-pets-on-your-desktop/actions/workflows/ci.yml)

PolyPals is a native macOS desktop companion and language-learning application. Three independent bilingual pets stay on your desktop and support lightweight learning through short conversations, compact cards, scheduled reminders, and natural ambient behavior:

- **Sol**: Spanish companion
- **Mousse**: French companion
- **Ash**: English companion

Each pet has an independent language profile, chat history, confirmed memories, inventory, plans, familiarity progress, desktop position, and notification preferences. Pet windows do not take keyboard focus, and the built-in learning content works entirely offline.

> **Project status:** PolyPals 0.4 is under active development. There is no public Developer ID-signed and Apple-notarized installer yet. Developers can run the project from source; any `-local.dmg` is for local testing only.

## Why PolyPals

Traditional language-learning tools usually require the learner to open an app and begin a full lesson. PolyPals breaks practice into brief, low-pressure encounters throughout the day. A pet can bring one or two cards, start a short conversation, or remind the learner about a plan while respecting focus sessions, presentations, full-screen work, and quiet hours.

The project follows five principles:

- **Local first:** chats, confirmed memories, progress, and settings stay on the Mac by default.
- **Low interruption:** pet windows do not take focus, and proactive behavior is bounded by context and frequency limits.
- **Offline capable:** 126 reviewed seed cards are included and require no API key.
- **Explicit privacy boundaries:** only the limited context needed for a request is sent to the currently selected model provider.
- **Declarative extensions:** content and pet packs contain validated data and assets, never third-party executable scripts.

## Screenshots

The project still needs publication-ready screenshots or a short demo that contains no private desktop content. Useful views would include all three pets on the desktop, the chat panel, a learning card, the plan interface, and Settings.

Place approved screenshots in `Design/Screenshots/` and reference them with relative paths, for example:

```md
![Three PolyPals companions on a macOS desktop](Design/Screenshots/desktop-overview.png)
```

## Features

### Desktop companionship

- Three independent, transparent pet windows that do not take keyboard focus
- Dragging, edge snapping, multi-display position restoration, resizing, hiding, and sleep
- Time-aware ambient behavior, character-specific actions, and optional perching on window edges
- Focus mode, presentation mode, quiet hours, full-screen suppression, and proactive invitation limits
- A menu-bar focus timer with 25- and 50-minute sessions

### Language learning

- Independent CEFR A1–C2 receptive and productive levels for each pet
- Fixed difficulty or conservative adaptive difficulty
- Seven bounded card types, with 42 built-in cards per pet and 126 total
- Feedback for liked, too easy, too difficult, and overly similar content
- Cross-modal encounters, topic preferences, quality checks, and offline fallback
- System text-to-speech and optional AI-assisted card variations

### Chat, memory, and relationships

- Bring-your-own OpenAI or DeepSeek API key, configured and stored separately
- Streaming chat, stop, retry, edit and resend, favorites, and per-message no-save mode
- Only user-confirmed information can become long-term memory
- Seven independent, non-decaying familiarity levels for each pet
- Local inventory, gifts, found keepsakes, and a summary of what happened today

### Plans and extension packs

- Create daily or weekly plans with natural language
- System notifications or pet actions, execution history, one-hour snooze, and skip-today actions
- Declarative `.polypals-pack` content and pet packs
- JSON Schema, SHA-256 integrity checks, path safety checks, and atomic installation
- One shared validation implementation for the application and command-line tool

See [使用指南.md](使用指南.md) for the Chinese user guide and [IMPLEMENTATION.md](IMPLEMENTATION.md) for implementation status.

## Requirements

### To use the application

- Apple Silicon Mac
- macOS 14 or newer

### To develop from source

- Xcode 16
- Swift 6
- Git

The project has no third-party Swift package dependencies. A network connection is only needed for optional OpenAI or DeepSeek chat and AI-assisted cards.

## Get started from source

### 1. Clone the repository

```sh
git clone https://github.com/JacobTang-handsome/Polypals-language-pets-on-your-desktop.git
cd Polypals-language-pets-on-your-desktop
```

### 2. Build and test

```sh
swift build
swift test
```

Alternatively, open `Package.swift` in Xcode, select the `PolyPals` scheme, and run it.

### 3. Launch the application

```sh
swift run PolyPals
```

No API key is required on first launch. The application starts with its built-in offline content.

## Build a local application

Create an ad-hoc-signed arm64 application bundle for local testing:

```sh
Scripts/build-app.sh
open Distribution/PolyPals.app
```

Create a local test disk image:

```sh
Scripts/build-local-dmg.sh
```

These artifacts are not Developer ID-signed or Apple-notarized and must not be distributed as public releases. A public build requires the release owner to provide signing and notarization credentials:

```sh
POLYPALS_SIGNING_IDENTITY='Developer ID Application: …' \
POLYPALS_NOTARY_PROFILE='polypals-notary' \
Scripts/sign-and-notarize.sh
```

See [RELEASE.md](RELEASE.md) for the complete release checklist.

## API keys and privacy

Select OpenAI or DeepSeek in Settings, enter the corresponding provider key, and run the connection test.

- Provider keys are stored in separate macOS Keychain entries.
- Keys are never written to SwiftData, exports, logs, screenshots, or the repository.
- Only the currently selected provider receives a request.
- Requests contain only the current message, limited recent context, and user-confirmed memories.
- OpenAI Responses API requests explicitly set `store: false`.
- The application does not read screen content, source code, the clipboard, or the microphone.
- Cross-application window perching can use Accessibility access that the user explicitly grants; a screen-edge fallback remains available without that permission.

See [PRIVACY.md](PRIVACY.md) for the complete data boundary. Report vulnerabilities privately through GitHub Security Advisories as described in [SECURITY.md](SECURITY.md). Never put API keys, private chats, or user databases in a public issue.

## Content and pet packs

The repository supports two declarative extension formats:

- **Content packs** add appropriately licensed language-learning cards.
- **Pet packs** add validated pet assets and metadata.

Validate the repository examples with:

```sh
Tools/validate-pack Examples/ContentPack/ExampleContent.polypals-pack
Tools/validate-pack Examples/PetPack/ExamplePet.polypals-pack
```

Read [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md) or [插件开发指南.md](插件开发指南.md) before developing an extension. Culture cards require sources, and every text or artwork contribution must have explicit use and redistribution rights.

## Tests and quality checks

Before opening a pull request, run at least:

```sh
swift test
swift build -c release
Tools/validate-pack Examples/ContentPack/ExampleContent.polypals-pack
Tools/validate-pack Examples/PetPack/ExamplePet.polypals-pack
Scripts/check-string-catalog.sh
Scripts/check-repository-safety.sh
```

GitHub Actions repeats these checks for pull requests and pushes to `main`. The workflow is defined in [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Contributing

Contributions are welcome for bug fixes, accessibility improvements, tests, documentation, and content or pet packs with clear licensing.

Recommended workflow:

1. Open an issue before a large feature, architectural change, or data-model change.
2. Fork the repository and create a focused branch from `main`.
3. Implement a scoped change and add relevant tests and documentation.
4. Run the tests and quality checks above.
5. Open a pull request describing verification results and any privacy, migration, or licensing impact.

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed rules. Participation in the community is subject to [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Project layout

```text
Sources/PolyPals/              Application, persistence, model clients, schedules, notifications, and UI
Sources/PolyPalsPluginKit/     Declarative pack formats and security validation
Sources/ValidatePack/          validate-pack command-line tool
Sources/PolyPals/Resources/    Localization, built-in pets, and application resources
Tests/                         Domain logic, migrations, network contracts, and UI-state tests
Examples/                      Importable content-pack and pet-pack examples
Schemas/                       JSON Schemas matching the examples
Scripts/                       Build, release, localization, and repository-safety scripts
Design/                        Design inputs, generation runs, and quality-review material
Distribution/                  Packaging configuration and local build artifacts
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for architecture and dependency direction.

## Current limitations

- Apple Silicon and macOS 14+ only
- No public signed and notarized download yet
- No cloud account or cross-device synchronization; chats, memories, and progress stay local
- No dynamic libraries, plugin scripts, or arbitrary executable content in extension packs
- No runtime model-provider plugins; only the built-in OpenAI and DeepSeek configurations are supported
- Pet packs cannot replace the stable built-in Sol, Mousse, or Ash identifiers
- Developer ID and notarization credentials must be configured by the release owner and are never stored in the repository

See [ROADMAP.md](ROADMAP.md) for future directions.

## License and asset rights

- Source code is licensed under the [Apache License 2.0](LICENSE).
- Example content is licensed under CC BY 4.0.
- The generated blank pet-atlas test fixture is licensed under CC0.
- **Built-in characters and artwork are not licensed.** The names, character concepts, visual identities, sprite sheets, animation frames, illustrations, logo concepts, and original references for Sol, Mousse, and Ash are excluded from the Apache-2.0 license unless a corresponding directory contains an explicit written grant.

The Apache-2.0 source-code license grants no right to use, adapt, or redistribute those characters or art assets. Using them in forks, derivative projects, promotion, or distributed builds requires separate written permission from the rights holder. New content and artwork contributions must state their source and license, and contributors must hold the rights needed to submit and redistribute them.

## Getting help

- Usage questions and reproducible bugs: open an [Issue](https://github.com/JacobTang-handsome/Polypals-language-pets-on-your-desktop/issues)
- Feature proposals: use the repository's Feature request template
- Security vulnerabilities: report them privately as described in [SECURITY.md](SECURITY.md)
- Pack development: read [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md)
