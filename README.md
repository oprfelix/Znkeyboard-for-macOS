# ZnKeyboard for macOS

Menu bar companion to ZnKeyboard for Android: polish or translate selected text in any app, using
the same prompts and 14 target languages. Providers: Google Gemini (Flash-Lite models only) or any
OpenAI-compatible API, with a DeepSeek preset (address built in, `deepseek-flash` by default) or a custom address,
each with its own key.

- **⇧⌘R** polish the selected text · **⇧⌘T** translate it into the target language (both changeable in Settings)
- Select text in a text box (e.g. ⌘A) and 润色 | AI 翻译为 [EN ▾] appears beside it, where the app reports the selection.
- A panel near the pointer shows the result: **Return** replaces the selection, **Esc** cancels, **⌘C** copies.
- **⇧⌘E** screenshot translate: drag over any part of the screen; its text is recognised on this Mac (Vision)
  and translated faithfully into your reading language (Simplified Chinese by default; Chinese text goes to
  English). The image never leaves the Mac. Needs the Screen Recording permission.
- Menu bar: choose the target language, open Settings (provider, API key, model, permission, language).

Needs macOS 14+ and the Accessibility permission (System Settings → Privacy & Security →
Accessibility) to read and replace the selection; screenshot translate also needs Screen Recording.
API keys are stored in the Keychain.

Build (Command Line Tools are enough, no Xcode): `scripts/build_app.sh`, then `open build/ZnKeyboard.app`.
It signs with the keychain's Developer ID Application certificate when there is one (permissions then
carry over between versions), otherwise ad hoc (macOS asks for permissions again after each rebuild).

Licensed under GPL-3.0 (see LICENSE). Prompts come from ZnKeyboard for Android.
