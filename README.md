# ZnKeyboard for macOS

Menu bar companion to ZnKeyboard for Android: polish or translate selected text in any app, using
the same prompts and 14 target languages. Providers: Google Gemini (Flash-Lite models only) or any
OpenAI-compatible API (OpenAI, DeepSeek, OpenRouter…), each with its own key.

- **⌥⌘R** polish the selected text · **⌥⌘T** translate it into the target language
- Select text in a text box (e.g. ⌘A) and 润色 | AI 翻译为 [EN ▾] appears beside it, where the app reports the selection.
- A panel near the pointer shows the result: **Return** replaces the selection, **Esc** cancels, **⌘C** copies.
- Menu bar: choose the target language, open Settings (provider, API key, model, permission, language).

Needs macOS 14+ and the Accessibility permission (System Settings → Privacy & Security →
Accessibility) to read and replace the selection. API keys are stored in the Keychain.

Build (Command Line Tools are enough, no Xcode): `scripts/build_app.sh`, then `open build/ZnKeyboard.app`.
The build is signed ad hoc, so macOS asks for the Accessibility permission again after each rebuild.

Licensed under GPL-3.0 (see LICENSE). Prompts come from ZnKeyboard for Android.
