# Contributing

Thank you for improving PolyPals. Open an issue before a large architectural or data-model change. Keep domain behavior deterministic and preserve existing user stores.

1. Build with Xcode 16 / Swift 6 on macOS 14+.
2. Run `swift test`, `swift build -c release`, and both example-pack validations.
3. Put every user-visible string in `Localizable.xcstrings` and run `Scripts/check-string-catalog.rb`.
4. Never commit API keys, user databases, logs, certificates, notarization credentials, apps, or DMGs.
5. For schema changes, add a versioned migration, a pre-migration backup, and old/empty/partial-data tests. Never delete a store after migration failure.
6. Declare content and artwork provenance. Do not contribute reference art unless you have redistribution rights.

Plugin contributions should follow [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md) and use the matching issue template. Pull requests should be focused and explain privacy and migration impact.
