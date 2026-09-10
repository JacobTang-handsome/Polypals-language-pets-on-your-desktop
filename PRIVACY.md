# PolyPals privacy boundary

PolyPals is local-first and does not automatically read the screen, source code, keystrokes, clipboard, microphone, contacts, calendar, or the names of foreground applications.

## Stored locally

- Per-pet settings, window position, confirmed memories, inventory, plans, and relationship progress
- Chat history, unless saving is disabled for that pet
- Aggregate event counts and durations that do not include chat text or application names
- Card feedback, encounter counts, AI-card quality metadata, and schedule execution outcomes (status/reason only, never chat正文)
- The user's OpenAI and/or DeepSeek API keys in separate macOS Keychain entries using an unlocked, this-device-only accessibility policy

All local pet data and aggregate metrics can be reset from the app. Deleting a pet's data also cancels its pending notifications. The built-in role and pet-house entry remain available.

## Sent to the selected model provider

Only when the user supplies a key and initiates a model-backed action, PolyPals sends the current prompt, a bounded recent chat window, the pet's role instructions, and memories that the user previously confirmed to the selected provider (OpenAI or DeepSeek). Requests use the provider's official Responses API with `store: false`. PolyPals does not use server-side conversations or `previous_response_id`.

The app does not include a developer API key, a custom endpoint field, analytics upload, crash-report upload, or account synchronization.

## Permissions

- Notifications are requested only when the user first creates a notification plan. A denied request leaves the plan stored for in-app behavior.
- Accessibility is requested only after the user enables window-edge activity and presses the explicit permission button. Denial keeps the screen-edge fallback available.
- Screen Recording and Microphone permissions are never requested.
# Window-edge activity

PolyPals can optionally use macOS Accessibility permission to read the position and size of visible application windows so a pet can sit on or follow a window edge. It does not read window text or content. The feature is off by default, can be disabled at any time, and falls back to screen-edge activity when permission is unavailable. PolyPals does not use the microphone for personality or ear-movement reactions.
