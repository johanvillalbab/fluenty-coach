# Fluenty Coach

> Instant EN ↔ ES translation on macOS — triggered by a double tap of ⌘C.

![macOS](https://img.shields.io/badge/macOS-15.0%2B-black?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## What is it?

Fluenty Coach lives quietly in your menu bar. Whenever you want to translate something, just **double-press ⌘C** — it reads the selected text, fires off a DeepL translation, and shows a floating glass panel right where your cursor is. No switching apps. No copy-paste dance.

```
Select text  →  ⌘C ⌘C  →  Glass panel appears  →  Translation ready
```

## Features

- **Double ⌘C trigger** — works in any app, system-wide
- **Auto language detection** — EN → ES or ES → EN, detected automatically
- **Floating glass panel** — native macOS Tahoe aesthetic, appears near your cursor
- **One-click copy** — grab the translation without touching the keyboard
- **DeepL powered** — high-quality neural translations
- **Menu bar only** — zero Dock clutter, always available

## Screenshots

> Coming soon — contributions welcome!

## Requirements

| Requirement | Version |
|------------|---------|
| macOS | 15.0 Sequoia or later |
| Xcode | 16+ |
| [xcodegen](https://github.com/yonaskolb/XcodeGen) | 2.x |
| DeepL API key | Free tier works |

## Getting Started

### 1. Clone & generate the Xcode project

```bash
git clone https://github.com/johanvillalba/fluenty-coach.git
cd fluenty-coach
xcodegen generate
```

> Install xcodegen with `brew install xcodegen` if you don't have it.

### 2. Add your DeepL API key

Open the app → **Settings** → paste your [DeepL Free API key](https://www.deepl.com/pro-api).

The key is stored securely in `UserDefaults` on your local machine and never leaves it.

### 3. Grant Accessibility permissions

Because Fluenty Coach reads selected text and uses a global hotkey, macOS requires Accessibility access:

**System Settings → Privacy & Security → Accessibility → enable Fluenty Coach**

### 4. Build & run

```bash
open FluentyCoach.xcodeproj
# Press ⌘R in Xcode
```

## How it works

```
Double ⌘C
    │
    ▼
HotkeyService (CGEventTap)
    │  detects two ⌘C within 400 ms
    ▼
AccessibilityService (AXUIElement)
    │  reads selected text from frontmost app
    ▼
TranslationService (DeepL REST API)
    │  detects language, sends request
    ▼
PopoverController (NSPanel)
    │  positions floating glass panel at cursor
    ▼
TranslationPopoverView (SwiftUI)
    └  displays result with copy button
```

## Project Structure

```
FluentyCoach/
├── App/
│   ├── FluentyCoachApp.swift      # App entry point & menu bar scene
│   └── AppDelegate.swift          # NSPanel lifecycle, settings window
├── UI/
│   ├── TranslationPopoverView.swift
│   ├── TranslationResultView.swift
│   ├── SettingsView.swift
│   ├── ApiKeySetupView.swift
│   ├── LanguageToggleView.swift
│   ├── GlassActionButton.swift
│   └── PopoverController.swift
├── Services/
│   ├── TranslationService.swift   # DeepL API client
│   ├── HotkeyService.swift        # CGEventTap global hotkey
│   └── AccessibilityService.swift # AXUIElement text reading
├── Models/
│   ├── TranslationDirection.swift
│   └── TranslationState.swift
└── Extensions/
    └── NSScreen+Cursor.swift
```

## Why DeepL and not Apple Translate?

Apple's Translation framework is sandboxed, on-device only, and requires explicit language selection. DeepL auto-detects the language, produces higher-quality output for EN/ES, and works with a simple REST call — making it a much better fit for this workflow.

## Privacy

- Your text is sent to DeepL's servers for translation (subject to [DeepL's privacy policy](https://www.deepl.com/privacy)).
- Your API key is stored **only on your device** in `UserDefaults`.
- No analytics, no telemetry, no third-party SDKs.

## Contributing

Pull requests are welcome. For major changes, please open an issue first.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Open a Pull Request

## License

MIT — see [LICENSE](LICENSE) for details.

---

Built with SwiftUI + AppKit on macOS Sequoia.
