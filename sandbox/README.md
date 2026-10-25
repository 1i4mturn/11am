# 11am sandbox

A small native Mac app for settling the look and the core behaviour before building the real thing. It's more than the canvas mockups (it runs, uses your calendar, indexes your files, thinks on your Mac and lives in the notch), but it's not the product yet.

## Run it (about 5 minutes)

You need **macOS 14 or later** and **Xcode 26** (free from the App Store). Apple's on-device model needs **macOS 26 with Apple Intelligence turned on**.

```bash
cd ~/Projects/11am/sandbox
./setup.sh
```

`setup.sh` installs [XcodeGen](https://github.com/yonaskolb/XcodeGen) with Homebrew if needed, generates `ElevenAm.xcodeproj` and opens it. Press **⌘R** in Xcode.

If Homebrew isn't installed: get it from [brew.sh](https://brew.sh), then run `./setup.sh` again.

The app is signed "to run locally" (no Apple Developer account needed). Because the signature changes on each build, macOS may ask again for Calendar or Keychain access after a rebuild. That's normal for a sandbox.

## What's in it

| Part | What it does | Try this |
|---|---|---|
| **Vellum shell** | Frosted window that blurs your desktop, faint paper tint, grain, layered sheets, Alte Haas display type | Move the window over a busy wallpaper. Switch dark mode |
| **The notch** | Black island at the camera. Idle ears, hover to peek, click to open: **Now**, **Ask**, **Overnight** | Move the pointer to the notch. Press **⌥Space** anywhere to ask |
| **Brain** | Routes each request to the cheapest brain that can do it: Apple's on-device model → a local model server (optional) → Claude with your key (optional) | Settings › Brain. Try "On this Mac only", then "Balanced" with a key |
| **Today** (Leo) | Your real calendar (or a sample day), the brief, an optional 11am check-in notification | "Connect Calendars", then "Write my brief" |
| **Files** (Bolton) | Local index of folders you choose (PDF, Word, RTF, Markdown, text), with name, content and meaning search | Add a folder, search, then "Ask Bolton about these results" |
| **Overnight** | Heavy jobs wait for the charger, a cool Mac and idle time or your overnight window. Writes tomorrow's brief ahead of time | "Run Now" to see it work immediately. **⇧⌘R** does the same |
| **The Suite** | The apps that replace the subscription pile, and which ones are in this sandbox | Look, react, tell us what's missing or unnecessary |
| **Design Lab** | Live sliders for paper tone, frost, grain, depth, ink, radius, display face and backdrop | Tune it until it feels right, then **Copy Values** and paste them into your feedback |

Shortcuts: **⌘1–⌘5** switch apps · **⌘\\** shows or hides the agent pane · **⌥Space** asks from anywhere · **⇧⌘R** runs tonight's work now · **⌘,** opens settings.

## On an 8 GB MacBook Air (M2)

This sandbox is designed around your Mac:

- **Apple's on-device model is the local brain.** It ships with macOS 26 and the system manages its memory, so 11am loads nothing extra. No model downloads, no gigabytes of RAM.
- **Heavy work waits.** Indexing and the brief run overnight, on the charger, when the Mac is cool, or after 20 idle minutes. They pause in Low Power Mode.
- **The index stays small.** A few thousand characters per file and a compact on-device sentence embedding (Apple's NaturalLanguage framework). Up to 4,000 files.
- **Native everything.** No Electron, no Docker, no bundled browser engine.
- **Optional cloud.** For bigger thinking, add a Claude API key. You choose the model and set a monthly cap, and 11am stops using Claude when the cap is reached.

## Using your Claude credit

Yes, you can, with one catch: **a claude.ai Pro or Max subscription can't be used as an API key.** The API is billed separately:

1. Go to **platform.claude.com**, sign in, add credit (prepaid) and create an API key.
2. In 11am: **Settings › Brain › Claude**, paste the key, then **Test**. The key is stored in the macOS Keychain.
3. Choose a model and a monthly cap.

Prices per million tokens (Anthropic API, October 2026):

| Model | In | Out | Good for |
|---|---|---|---|
| Claude Opus 5.5 (default) | US$4 | US$20 | Best briefs and reasoning |
| Claude Sonnet 5.5 | US$2 | US$10 | Balanced |
| Claude Haiku 5.5 | US$0.10 | US$0.50 | Fast and very cheap |

A daily brief is roughly 1,000–2,000 tokens, so it costs a fraction of a cent on Haiku and a few cents on Opus. Quick questions use low effort, and briefs use medium. With Opus and Sonnet, if a safety check declines a request, the API retries it on Anthropic's recommended fallback model (server-side fallbacks are switched on).

## How it's built

- **SwiftUI + AppKit** (macOS 14+), Swift 5 language mode, no third-party packages.
- **Frosted vellum** is real system blur (`NSVisualEffectView`, behind-window) with a paper tint, a generated grain texture and hairline edges, so it reads as frosted paper rather than clear glass.
- **The notch** is a borderless, non-activating `NSPanel` above the menu bar. It reads the notch size from `NSScreen.safeAreaInsets` and the auxiliary top areas, and passes clicks through when idle. Macs without a notch get a small pill.
- **Brain** is a router over three providers: `FoundationModels` (on-device), any OpenAI-style local server (Ollama, LM Studio), and the Claude Messages API (raw HTTPS with streaming, `anthropic-version: 2026-10-21`).
- **Overnight** uses `NSBackgroundActivityScheduler`, plus IOKit power state, thermal state, Low Power Mode and idle time.
- **This is Swift-only on purpose.** The Rust core from the plan comes once the look and the flows are locked. Each folder here (Brain, Files, Today, NightShift) maps onto a core module, so the swap is mechanical.

## What to tell us after you've used it

1. **Feel:** does the vellum read as frosted paper? Paste your Design Lab values.
2. **Notch:** too eager, too slow, the wrong size? What should Now show first?
3. **Brief:** what's missing, what's noise? Morning brief, 11am check-in, or both?
4. **Overnight:** did the jobs run? Is the log reassuring or just noise?
5. **Speed:** anything sluggish on the 8 GB Air? (Activity Monitor › Memory shows 11am's footprint.)
6. **The Suite:** which app should come next?
