# Release checklist

1. Run `swift test`, a release build, both `Tools/validate-pack` example checks, the String Catalog check, and the visual QA scripts for all three v2 pet atlases.
2. Verify three idle pets for five minutes on physical Apple Silicon hardware: average total CPU at or below 5% and resident memory at or below 350 MB.
3. Exercise multi-display disconnect/reconnect, scaling, Spaces, Stage Manager, full-screen apps, sleep/wake, light/dark wallpaper, and denied notification authorization.
4. Build the 0.4.0 arm64 bundle with `Scripts/build-app.sh`, then create a local-only DMG with `Scripts/build-local-dmg.sh`.
5. Provide a Developer ID Application identity and an `xcrun notarytool` Keychain profile, then run `Scripts/sign-and-notarize.sh`.
6. Install the produced DMG on a clean macOS 14+ machine and confirm Gatekeeper assessment, local persistence, notification deep links, data reset, and no sensitive permission prompts.

Developer ID signing and Apple notarization cannot be completed until the release owner installs the required certificate and notarization credentials on the build machine.
