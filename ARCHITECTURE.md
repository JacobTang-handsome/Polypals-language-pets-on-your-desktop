# Architecture

PolyPals 0.4 uses one app model, one SwiftData container, one window manager, and one card repository. New work must extend these rather than create parallel state systems.

- `Domain.swift`: platform-neutral learning, relationship, card, scheduling, and CEFR policy types.
- `Persistence.swift`: frozen V1/V2 entities, additive V3/V4 companion records, migration plan, backup and backfill.
- `CardServices.swift`: selection, feedback, caching, snapshots, and legacy JSON import.
- `OpenAIResponsesClient.swift`: provider-configured Responses client behind `AIModelClient`; both providers receive the same language policy and use separate Keychain slots.
- `PolyPalsPluginKit`: stable declarative manifest and filesystem/asset validation shared by the app and CLI.
- `PluginServices.swift`: offline atomic installation and application-state integration.
- `AppModel.swift`: UI-facing orchestration and dependency boundary.
- UI/window/scheduler files: presentation and macOS adapters.

Dependency direction is domain/policy → services → app orchestration → UI. Persistence and networking must not become prerequisites for testing domain policies. Third-party dynamic libraries and scripts are deliberately out of scope.
