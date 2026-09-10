# Security policy

Please report vulnerabilities privately through GitHub Security Advisories rather than a public issue. Include affected version, impact, and minimal reproduction without real API keys or user data.

Supported line: 0.4.x. PolyPals stores provider keys only in macOS Keychain, keeps confirmed memory and history local, sends `store: false`, and never loads executable plugin code. Plugin installation is offline and rejects traversal, symlinks, scripts, oversized payloads, digest mismatches, malformed manifests, and reserved built-in pet IDs.

Do not attach a real SwiftData store, chat transcript, Keychain export, signing certificate, or notarization credential to any report.
