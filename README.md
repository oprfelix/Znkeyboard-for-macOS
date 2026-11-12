# ZnKeyboard for macOS

Menu bar companion to ZnKeyboard for Android and iPhone: translate selected text in any app, using
the same prompts and 14 target languages. Providers: DeepSeek (address built in, `deepseek-flash`),
Google (Flash-Lite models), or any OpenAI-compatible API at an address you enter, each with its own key.

- **⇧⌘E** AI 翻译: text selected in a text box is translated in place into the target language; text selected
  on a web page or in a document gets a translation to read (changeable in Settings, as is ⇧⌘2)
- Select text in a text box (e.g. ⌘A) and AI 翻译为 [EN ▾] appears beside it, where the app reports the selection.
- Reading translation (on by default, Settings → Usage): select text on a web page or in a document with the
  mouse and 翻译为 [ZH ▾] appears; it translates faithfully into the reading language screenshots use, and
  the card shows the original above the translation, each to copy.
- Clicking elsewhere closes a translation to read (reading and screenshot); the pin in its header keeps it open,
  remembered for next time.
- A panel near the pointer shows the result: **Return** replaces the selection, **Esc** cancels, **⌘C** copies.
- **⇧⌘2** screenshot translate: drag over any part of the screen; its text is recognised on this Mac (Vision)
  and translated faithfully into your reading language (Simplified Chinese by default; Chinese text goes to
  English). The image never leaves the Mac. Needs the Screen Recording permission.
- Menu bar: choose the target language, open Settings (provider, API key, model, permission, language).

Website: [znkeyboard.2amz.com](https://znkeyboard.2amz.com/) (mirror of oprfelix.github.io/znkeyboard). Updates come
from znkeyboard.2amz.com, or from GitHub Releases when that fails. Once a day ZnKeyboard sends an anonymous ping
(a random ID, platform, version and how many times it translated; never any text) for the usage
numbers on the website; Settings → General turns it off.

Needs macOS 14+ and the Accessibility permission (System Settings → Privacy & Security →
Accessibility) to read and replace the selection; screenshot translate also needs Screen Recording.
API keys are stored in the Keychain.

Build (Command Line Tools are enough, no Xcode): `scripts/build_app.sh`, then `open build/ZnKeyboard.app`.
It signs with the keychain's Developer ID Application certificate when there is one (permissions then
carry over between versions), otherwise ad hoc (macOS asks for permissions again after each rebuild).

Licensed under GPL-3.0 (see LICENSE). Prompts come from ZnKeyboard for Android.
