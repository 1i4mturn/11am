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
| **Vellum shell** | A window you can see through: the desktop reads through the sidebar, sheets are frosted white paper, real brand monograms and wordmark | Move the window over a busy wallpaper or other windows. Switch dark mode |
| **The notch** | Black island that grows out of the camera notch. Idle ears, hover to peek, click to open: **Now**, **Ask**, **Overnight** | Move the pointer to the notch. Press **⌥Space** anywhere to ask |
| **Brain** | Routes each request to the cheapest brain that can do it: Apple's on-device model → a local model server (optional) → Claude with your key (optional) | Settings › Brain. Try "On this Mac only", then "Balanced" with a key |
| **Today** (Leo) | Your real calendar (or a sample day), the brief, an optional 11am check-in notification | "Connect Calendars", then "Write my brief" |
| **Mail** (Marc) | Mail sorted into **Needs you · FYI · Later · Noise**, each with a reason. Replies drafted in your voice, opened in your own Mail app to send | Start with the sample inbox. Then **Read Apple Mail on this Mac** (needs Full Disk Access) or open an exported .mbox. Right-click an email to move it: Marc remembers the sender |
| **Write** (William) | Plain documents on your Mac. Select text (or nothing, for the whole draft), choose **Shorter**, **Clearer**, **Warmer** or **In my voice**, then accept or reject the suggestion | Try **In my voice** on the sample investor update. Edit **Your voice**: Marc uses it too |
| **Files** (Bolton) | Local index of folders you choose (PDF, Word, RTF, Markdown, text), with name, content and meaning search | Add a folder, search, then "Ask Bolton about these results" |
| **Research** (James) | A WebKit browser with James beside it: summarise or ask the page, add pages as sources, then a report that cites them, sent to Write | Open a start-page link, **Add to sources**, then ask a question under **Report** |
| **Money** (George) | Cash, burn, runway, six months in and out, where it goes, and "ask your numbers". Imports a bank CSV; change a category and George remembers the payee | Ask "What happens if we hire one more engineer at 10k a month?" |
| **Business** (Conner) | The pipeline as a board: drag deals between stages, weighted value, "going quiet" nudges, follow-ups drafted in your voice | Drag a deal to **Proposal**, open it, **Draft follow-up** |
| **Design** (Robert) | Quick on-brand graphics exported as PNG, subject lift and black-and-white on this Mac, and the brand kit | Make a **Big number** graphic and **Export PNG**. Drop a photo into **Image tools** and **Lift subject** |
| **Photo** (Robert) | Non-destructive photo editing: looks, light, colour, three colour wheels, colour by colour, curve, sharpen, noise, fade, vignette, grain and .cube LUTs. Crop to a shape, straighten (or **Auto** level the horizon), rotate, flip. **Clean up** paints out dust, spots and small distractions. **Cut out** removes the background. RAW files open too. Undo, before/after, export JPEG, HEIC, PNG or TIFF at full resolution | Press **Auto**, then try a look. **Crop** › 4:5 and drag the corners. **Clean up** › paint over the sun |
| **Video** (Cole) | A real timeline: add clips, drag their edges to trim, **⌘B** to split at the playhead, reorder, duplicate, speed (¼× to 4×). Each clip has its own grade (the same colour panel as Photo), volume and mute. **Clean up the voice** runs Apple's Voice Isolation, a rumble filter and levelling on this Mac. Reframe for 9:16, 1:1 or 4:5. Dip to black or white between clips, fade in and out. Transcribe a clip and strike lines to cut them. Export H.264, HEVC, 720p, ProRes or sound only, plus captions | **Try two sample clips**, drag the second clip's left edge, grade it with **Teal & orange**, switch the shape to **9:16**, play |
| **Learn** (Harris) | Flashcards with spaced repetition and a flip-card review, cards made from your notes, learning paths | Review the sample deck. Paste notes and **Make cards** |
| **Build** (Johnny) | Tune 11am by describing the change (preview, apply, undo). **Make a colour look** from a description, saved for Photo and Video. A terminal where Johnny suggests commands but only you run them | Try "Warmer, and a bit more see-through", then **Revert**. Make "Warm film with soft blacks" and find it under Looks in Photo |
| **Overnight** | Heavy jobs wait for the charger, a cool Mac and idle time or your overnight window. Writes tomorrow's brief ahead of time | "Run Now" to see it work immediately. **⇧⌘R** does the same |
| **The Suite** | The apps that replace the subscription pile, and which ones are in this sandbox | Look, react, tell us what's missing or unnecessary |
| **Design Lab** | Live sliders for paper tone, frost, **clarity** (how much of the desktop shows through), grain, depth, ink, **motion**, radius, display face and backdrop. Starts from your round-one picks | Tune it until it feels right, then **Copy Values** and paste them into your feedback |

Shortcuts: **⌘1–⌘9** switch between the first nine apps · **⌘Z / ⇧⌘Z** undo and redo in Photo and Video · **⌘B** splits, **⌘↩** plays and pauses, **⌘⌫** removes a clip in Video · **⌘\\** shows or hides the agent pane (it also steps aside on narrow windows) · **⌥Space** asks from anywhere · **⇧⌘R** runs tonight's work now · **⌘,** opens settings.

Screenshots from the CI Mac (a small virtual display without a notch, so the notch shows as a pill, with a busy test desktop behind the app) are on the `ci/sandbox-shots` branch. Push a commit with `[shots]` in its message to refresh them.

## Photo and Video: what's under the hood

- **One colour engine for both.** Core Image does the work on the GPU. Tone, contrast, the three colour wheels (lift, gamma, gain), saturation and colour-by-colour are baked into a single 33×33×33 colour cube, so a grade costs one lookup per pixel and plays in real time on video. Exposure, white balance, highlights and shadows, vibrance, sharpening, noise reduction, vignette and grain are Core Image filters around it.
- **Looks are plain files.** Every look you save (or Johnny makes) is a small JSON file in `~/Library/Application Support/11am-sandbox/Looks`. Drop `.cube` LUTs from Resolve, Premiere or a LUT pack into **Import .cube…** and they work in both apps.
- **Clean-ups stay on this Mac.** The spot healer fills each spot from the nearby patch whose surroundings match best, colour-matched and feathered. Background removal is Vision's subject mask. Auto straighten is Vision's horizon detector.
- **Video never re-encodes until you export.** Trims, splits, speed and transcript cuts are an `AVMutableComposition`. Colour, reframing and dips are a per-frame Core Image pass. Volume and fades are an audio mix. Voice clean-up uses Apple's `AUSoundIsolation` unit rendered offline, and falls back to a rumble filter and levelling if Voice Isolation isn't available.
- **Adding more later.** Ask Johnny for a look in plain English. For a new tool (a mask brush, keyframes, titles), ask Claude Code in this repo: the engine is in `ElevenAm/Media` (shared) and `Features/Photo` and `Features/Video` (the apps), and each piece is small enough to extend.

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
