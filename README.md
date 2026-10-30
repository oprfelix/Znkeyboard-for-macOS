# ZnKeyboard for macOS

Menu bar companion to ZnKeyboard for Android: polish or translate selected text in any app with
Gemini, using the same prompts, Flash-Lite models and 14 target languages.

- **⌥⌘R** polish the selected text · **⌥⌘T** translate it into the target language
- A panel near the pointer shows the result: **Return** replaces the selection, **Esc** cancels, **⌘C** copies.
- Menu bar: choose the target language, open Settings (Gemini API key, model, permission).

Needs macOS 14+ and the Accessibility permission (System Settings → Privacy & Security →
Accessibility) to read and replace the selection. The API key is stored in the Keychain.

Build (Command Line Tools are enough, no Xcode): `scripts/build_app.sh`, then `open build/ZnKeyboard.app`.
The build is signed ad hoc, so macOS asks for the Accessibility permission again after each rebuild.

Licensed under GPL-3.0 (see LICENSE). Prompts come from ZnKeyboard for Android.
