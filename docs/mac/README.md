# 11am for Mac and iPhone: the rebuild plan

> Start here. This folder is the full plan for rebuilding 11am as a native Mac + iPhone suite with local AI and a team of 11 agents, where each agent is also a real app.

---

## Is all of this possible?

**Yes. About 85% of it is straightforward engineering, about 10% needs workarounds, and about 5% isn't possible the way you described it, but there's a good alternative for each of those.** Here's the honest version.

| You asked for | Verdict | The catch |
|---|---|---|
| Native Mac suite, black and white, translucent | ✅ Yes | Use SwiftUI and Apple's Liquid Glass (macOS 26+). Web tech can't do real Liquid Glass. |
| A "notch" that drops down when you approach the camera housing | ✅ Yes | It's proven: boring.notch, Atoll, NotchNook and DynamicNotchKit all do it. Macs without a notch get a floating pill instead. |
| Each agent is its own app | ✅ Yes | One shared engine with an app (window or bundle) per agent. See [02-architecture](./02-architecture.md#process-model). |
| Johnny can update and improve each app for the user | ✅ Yes, with a design change | A user can't recompile a signed native app. Each app is built from **editable specs**: views, automations, prompts and mini-apps. Johnny edits those safely, with versioning and rollback. See [Malleable apps](./02-architecture.md#malleable-apps-how-johnny-edits-apps). |
| Mail app | ✅ Yes | Gmail, Outlook, iCloud and IMAP are all doable. Google needs app verification for Gmail scopes (budget weeks). |
| Messages app (iMessage) | ⚠️ Mac only, outside the App Store | Reading needs Full Disk Access to `~/Library/Messages/chat.db`. Sending uses AppleScript to drive Messages.app. **No third-party iPhone app can read iMessages.** |
| Browser | ✅ Yes | Built on WebKit (`WKWebView`), the same engine as Safari. Not Chromium. |
| Terminal | ✅ Yes | Embed libghostty (MIT, the engine behind Ghostty) or SwiftTerm. |
| File browser | ✅ Mostly | It can browse, search, organise and preview. It can't replace Finder's system role (Desktop, Trash, mounting drives), and it doesn't need to. |
| Rust backend | ✅ Not silly, it's a good choice | Rust core and Swift UI, bridged with UniFFI. The same core runs on iPhone later. See [02-architecture](./02-architecture.md#rust-or-not). |
| Local models like the new Kimi | ⚠️ Not on a normal Mac | **Kimi K3.1 Pro (Oct 2026) has about 2.8 trillion parameters.** Even the 1T-parameter Kimi K2.6 needs roughly 240–600 GB of memory. Local everyday models are Qwen 3.6, Gemma 4 and Apple's on-device model. Kimi becomes the "cloud brain" via API, or runs on a 4× Mac Studio cluster for the extreme power user. See [03-ai-brain](./03-ai-brain.md). |
| Easy to add more models | ✅ Yes | A pluggable provider layer covers local MLX, local GGUF, Apple Foundation Models, any OpenAI-compatible endpoint (Kimi, OpenRouter, LM Studio, Ollama, exo) plus Anthropic and Google. |
| Mac ↔ iPhone connection | ✅ Yes | CloudKit sync with no server, a local-network fast path, Live Activities and Dynamic Island, widgets, Siri/App Intents, Handoff. The phone can use your Mac as its brain. |
| Runs on lower-end Macs | ✅ Yes, by design | Five hardware tiers, from an 8 GB M1 Air to a Mac Studio. Every feature degrades gracefully. **The floor is Apple Silicon + macOS 26.** Intel is not supported. |
| One app with purchasable agent add-ons | ✅ Yes | Mac: direct download (Developer ID, notarised) with licence keys. iPhone: App Store with in-app purchase. RevenueCat (or similar) ties them together. The full Mac suite **can't** be in the Mac App Store (sandbox limits). |

**Solo timeline (honest):** working on it full time with AI coding tools, expect about **3–4 months to a daily-usable core** (Leo, Bolton, the notch, the brain), **9–12 months to a sellable v1** (plus Marc, James, William, Johnny and the iPhone companion), and **14–18 months for all 11**. You can shorten that by shipping agents one at a time. Your add-on model already encourages that.

---

## The big decisions (summary)

1. **Native first.** SwiftUI + AppKit for every pixel. A Rust core for everything that isn't a pixel: data, search, sync, agent runtime, connectors and parsing.
2. **Local-first, cloud-optional.** Data lives on the Mac. Small and medium models run locally. Big thinking can use Kimi, Claude or others, but only with consent, per agent and per data class.
3. **One engine, many apps.** A single always-running core (it also owns the notch). Each agent is an app on top. Leo routes, Bolton remembers, and the others specialise.
4. **Enhance and replace.** Build the 80% of Mail, Finder, Safari, Terminal, Word, Excel, Keynote, Canva and CapCut that a founder actually uses, plus the brain. Hand the remaining 20% to the system apps (Open in Mail, Reveal in Finder).
5. **No forever features.** Every feature has to pass the [gimmick filter](./01-product.md#the-gimmick-filter). Cute ideas become **Johnny templates** that users install themselves, so they never bloat the core.
6. **Trust is the product.** Agents act on their own only within clear autonomy levels. Anything external or irreversible (send, pay, delete, post) asks first. Every action is logged with an undo.

---

## Reading order

| # | Doc | What's in it |
|---|---|---|
| 1 | [01-product.md](./01-product.md) | Vision, principles, what each agent replaces, packaging, a founder's day, the gimmick filter |
| 2 | [02-architecture.md](./02-architecture.md) | Rust vs Swift, process model, repo layout, data model, agent runtime, malleable apps, macOS integration, security, performance |
| 3 | [03-ai-brain.md](./03-ai-brain.md) | Models (the Kimi reality), provider layer, routing, hardware tiers, how AI is involved, autonomy, evals |
| 4 | [04-design-system.md](./04-design-system.md) | Visual identity, translucency, type, monograms, per-agent signatures, components, motion, **notch spec** |
| 5 | [05-iphone-and-continuity.md](./05-iphone-and-continuity.md) | iPhone app, Dynamic Island, sync, "Mac as brain", Handoff, widgets, Siri |
| 6 | [06-open-source-map.md](./06-open-source-map.md) | ~240 GitHub repos sorted by app, with licence warnings (what you can reuse vs only study) |
| 7 | [07-roadmap.md](./07-roadmap.md) | **Every single thing to do**, phase by phase, with checklists, week one day by day, what to salvage from the current repo |
| 8 | [08-shipping-and-business.md](./08-shipping-and-business.md) | Distribution, payments, add-ons, legal, privacy, Google/Microsoft verification, support |
| 9 | [agents/](./agents/README.md) | **The 11 agent briefs**: features, AI, design, mockups, Mac integration, backend, low-end behaviour, build checklist |
| 9b | [09-direction-v2.md](./09-direction-v2.md) | **Round-two update:** the rewritten narrative (own it, works with your Mac, replaces apps), the frosted-vellum look, 8 GB-first model strategy. Wins over earlier docs where they conflict |
| 9c | [../../sandbox/](../../sandbox/README.md) | **The sandbox app:** a runnable native Mac build to lock the look and core flows |
| 10 | [mockups/](./mockups/README.md) · [open the canvas](https://claude.ai/artifact/WG7JfdUvy8fdtykjd8v3sE) | Visual mockups: the interactive notch, identity sheet, iPhone, and a main screen for each of the 11 apps |

## The team at a glance

| Agent | Mono | Role | The app it becomes | Replaces / enhances | Package |
|---|---|---|---|---|---|
| [Leo](./agents/leo.md) | le | Chief of staff | **11am Today**: calendar, tasks, briefs, meetings, the notch | Calendar, Reminders, Sunsama/Motion, Granola | Core |
| [Bolton](./agents/bolton.md) | bn | Memory and files | **Bolton**: files, notes, search, memory | Finder (finding), Notes/Obsidian, Preview, Spotlight, clipboard | Core |
| [Marc](./agents/marc.md) | mc | Communication | **Marc**: mail, messages, people | Mail/Outlook/Superhuman, Messages, Contacts | Add-on |
| [William](./agents/william.md) | wm | Writing and voice | **William**: documents and rewrite-anywhere | Word/Pages/Docs, Grammarly | Add-on |
| [James](./agents/james.md) | jm | Research | **James**: browser and deep research | Safari/Chrome, Perplexity, read-later | Add-on |
| [Johnny](./agents/johnny.md) | jo | Build and technical | **Johnny**: terminal, automations, app tuning, mini-apps | Terminal/Warp, Shortcuts/Zapier | Add-on (Tune-lite in Core) |
| [George](./agents/george.md) | ge | Finance | **George**: sheets, cash and runway, receipts | Excel/Numbers, budgeting apps, Dext | Add-on |
| [Conner](./agents/conner.md) | cr | Business building | **Conner**: pipeline, strategy, decks, proposals | HubSpot-lite, PowerPoint/Keynote/Pitch | Add-on |
| [Robert](./agents/robert.md) | rt | Design | **Robert**: canvas, brand kit, image tools | Canva, light Photoshop/Illustrator | Add-on |
| [Cole](./agents/cole.md) | co | Video and audio | **Cole**: record, transcript editing, clips | CapCut/Descript/Loom | Add-on |
| [Harris](./agents/harris.md) | hr | Learning | **Harris**: paths, cards, languages, reading | Anki, Duolingo-lite, Blinkist | Add-on |

---

*Research for this plan was done on 25 Oct 2026. Model names, prices and repo activity change fast. The plan expects a remotely updated model registry for exactly that reason. Things marked "check" weren't verifiable from primary sources at the time.*
