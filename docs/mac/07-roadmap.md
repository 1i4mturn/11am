# 07: Roadmap: every single thing to do

> Built for one person (you) with AI coding tools. Durations are ranges for focused, near-full-time work. Each phase ends with something you **use daily**. Dogfooding is the test.

## Overview

| Phase | Goal | Duration | You can use it for |
|---|---|---|---|
| **0. Foundations** | Accounts, tools, skills, skeleton, decisions | 2–4 weeks | — |
| **1. Core spine** | Core engine + brain + Leo + Bolton + notch | 8–12 weeks | Calendar, tasks, files, notes, search, briefs |
| **2. Communication & research** | Marc, James, William, approvals, iPhone v1, sync | 10–14 weeks | Your whole email/messages/browsing/writing day |
| **3. Builder** | Johnny: terminal, Tune, automations, mini-apps | 6–8 weeks | Customising everything |
| **4. Business suite** | George, Conner, Robert | 10–14 weeks | Money, pipeline, decks, design |
| **5. Creative & growth** | Cole, Harris | 8–10 weeks | Video, learning |
| **6. Ship** (overlaps from Phase 2) | Licensing, store, website, beta, launch | ongoing | Selling it |

**Sellable v1 = end of Phase 3** (Core + Marc + James + William + Johnny + iPhone). Phases 4–5 ship as add-on releases. That's your business model working as intended.

---

## Phase 0: Foundations (2–4 weeks)

### Accounts and admin
- [ ] **Apple Developer Program** (US$99/yr). Enrol as an **organisation** (needs a D-U-N-S number, which can take 1–2 weeks, so **start day 1**) so the seller name is your company, not your personal name.
- [ ] Register the domain(s) and set up a support email.
- [ ] **Google Cloud project** for Gmail/Calendar OAuth (start the **OAuth consent screen** early; restricted Gmail scopes need verification, see [08](./08-shipping-and-business.md#google-and-microsoft-verification)).
- [ ] **Microsoft Entra app registration** (Outlook/M365 via Graph), with publisher verification.
- [ ] Model provider keys: **Moonshot** (Kimi), **OpenRouter** (one key for many models), optionally Anthropic and Google.
- [ ] Search API key for James (Brave Search API, Exa or Tavily; compare cost per 1,000 queries).
- [ ] Xero developer account (George), Stripe account (George reads; also your own billing).
- [ ] Trademark search for "11am" in your markets (AU via IP Australia, plus US and EU if selling there). Agent names are common first names, which is fine as product names, but check the class 9/42 conflicts for "11am".
- [ ] Decide the legal entity selling the app and set up a bank account for Paddle/Stripe payouts.

### Machines and tools
- [ ] Development Mac: ideally **32 GB+** (you'll run Xcode, Rust builds and a 20 GB model at once). Keep or borrow an **8 GB or 16 GB Mac** for low-tier testing (critical).
- [ ] iPhone with Apple Intelligence (15 Pro or later) for the companion app.
- [ ] Install: Xcode 27, Rust (`rustup`, stable, targets `aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim`), `uniffi-bindgen`, Tuist or XcodeGen, SwiftLint, `cargo-deny`, `just` (task runner), Python 3 + `mlx-lm` (model conversion/testing).
- [ ] AI coding setup: Claude Code (or similar) with project `CLAUDE.md` files per area (`core/`, `apple/`) describing conventions.

### Skills to learn (in this order, alongside building)
| Skill | Resource | Time |
|---|---|---|
| Swift basics + SwiftUI | Apple's "Develop in Swift" and SwiftUI tutorials; Hacking with Swift (100 Days of SwiftUI) | 2 weeks (overlaps) |
| macOS specifics (AppKit interop, NSPanel, NSWindow levels, MenuBarExtra) | Apple docs; read DynamicNotchKit and boring.notch source | 1 week |
| Liquid Glass | WWDC25 "Meet Liquid Glass" + "Build a SwiftUI app with the new design"; WWDC26 design updates | 2 days |
| Swift concurrency (async/await, actors, Sendable) | WWDC "Meet async/await", Swift 6 migration guide | 3 days |
| Rust basics | "The Rust Book" ch. 1–10, 13, 15–16; Rustlings | 2 weeks (overlaps) |
| Async Rust (Tokio) | Tokio tutorial | 3 days |
| UniFFI | UniFFI user guide (proc-macro approach, async, callback interfaces) | 2 days |
| MLX / local models | mlx-swift-examples; mlx-lm README; read about quantisation | 3 days |
| Foundation Models | WWDC25/26 sessions (incl. "What's new in the Foundation Models framework", WWDC26 #241) | 1 day |
| App Intents, WidgetKit, ActivityKit | WWDC sessions | Phase 2 |

### Repo and skeleton
- [ ] Create a branch and restructure to the [target layout](./02-architecture.md#repo-layout-target). Move the current `apps/` and `packages/` to `legacy/web/` (keep them running for reference).
- [ ] `core/` Rust workspace with the `elevenam` facade crate exposing `fn version() -> String` and an async `fn ping() -> String` via UniFFI.
- [ ] `apple/` workspace: a macOS app target that links the XCFramework and shows `version()` in a window. **This proves the whole toolchain on day 3–5.**
- [ ] `design/tokens.json` with a generator script producing `DesignSystem/Tokens.swift` (and CSS for mini-apps; reuse the existing `packages/ui/src/tokens`).
- [ ] CI: GitHub Actions on macOS runners: `cargo test`, `cargo clippy`, `cargo deny`, `xcodebuild test`.
- [ ] `docs/decisions/` (ADR log). Record every big decision (Rust core, CloudKit, Developer ID distribution…).

### Product prep
- [ ] Score your agent ideas with the [idea triage sheet](#idea-triage-sheet). Paste the results into each agent brief's "Later" or "Not building" lists.
- [ ] Build your **eval datasets** from your own data: 300 example asks (Leo routing), 500 labelled emails (Marc triage), 50 "find this file" queries (Bolton). Hand-labelling these is the most valuable boring work you'll do.
- [ ] Record a baseline: how long your current day takes in each app (for marketing and to measure yourself).

---

## Phase 1: Core spine (8–12 weeks)

### Core engine (Rust)
- [ ] `store`: SQLite (WAL), migrations, FTS5, sqlite-vec, blob store, backup/export.
- [ ] `events`: append-only log, in-process bus (Tokio broadcast), undo journal.
- [ ] `agents`: manifest loading, tool registry with JSON Schemas and risk levels, policy engine (entitlements, autonomy, data classes, budgets), agent loop, `agent.ask` with depth/budget limits.
- [ ] `scheduler`: cron + event triggers + power/idle-aware queue; persisted jobs; resume after restart.
- [ ] `brain`: provider trait; providers: OpenAI-compatible HTTP, Anthropic; callback providers for Apple FM and MLX; router with task classes; `model_calls` logging; budgets; offline detection.
- [ ] Settings and profiles; Keychain via callback.
- [ ] UniFFI surface v1: `core.start()`, `leo.*`, `bolton.*`, `brain.*`, `approvals.*`, `events.subscribe()` (stream to Swift).

### Apple shell (Swift)
- [ ] Host app: login item (`SMAppService`), activation-policy toggling, MenuBarExtra, window management per agent (`WindowGroup(id:)`).
- [ ] **ModelHost.xpc**: mlx-swift-lm loading/unloading, streaming, embeddings, memory-pressure handling, `keep_alive`.
- [ ] Apple Foundation Models adapter (availability checks; graceful absence when Apple Intelligence is off).
- [ ] Hardware tier detection + **Model manager UI** (recommended models, download with progress and SHA check, benchmark button).
- [ ] Design system package: tokens, glass components, monograms, patterns, Ask bar, Approval card, Activity row, Source chip, Model badge, Brief card.
- [ ] **Notch v1**: geometry, idle/peek/open states, pages: Now, Approvals, Ask, Shelf (drop → Bolton); fallback pill for Macs without a notch; settings.
- [ ] Global Ask bar (⌥Space) with routing preview.
- [ ] Permissions onboarding framework (per-agent explainer screens, Settings › Permissions with test buttons).
- [ ] First-run onboarding: name, the "team" intro, tier detection, model download, choose folders for Bolton, connect calendars (EventKit), choose brain mode.

### Leo v1 → [brief](./agents/leo.md)
- [ ] EventKit calendars and reminders (read and write, with approval for changes involving others).
- [ ] Today view (timeline: events + tasks + jobs).
- [ ] Router (rules + embeddings + small model) with the eval set ≥ 90% top-1.
- [ ] Morning brief, **11am check-in**, evening wrap (from the event log).
- [ ] Meeting prep cards (calendar + Bolton; Marc and James join in Phase 2).
- [ ] Approvals window (cross-agent queue) + actionable notifications.
- [ ] Activity feed with undo.

### Bolton v1 → [brief](./agents/bolton.md)
- [ ] Folder indexing (FSEvents incremental), extraction (PDFKit, Vision OCR, docx/xlsx/pptx/markdown/text), chunking, local embeddings.
- [ ] Hybrid search (FTS5 + vectors + metadata + rerank) with natural-language filters; `NSMetadataQuery` for name/metadata queries.
- [ ] File browser (list/columns/gallery, Quick Look, Finder tags).
- [ ] Notes (Markdown files on disk, backlinks).
- [ ] Memory: entities, memories, decisions with provenance; curator (port `capture.ts` / `save-heuristic`); memory inspector + forget.
- [ ] Context packs API for agents.
- [ ] Shelf (from the notch) + clipboard history.

### Phase 1 exit criteria
- [ ] You use Leo + Bolton + the notch every workday for 2 weeks.
- [ ] Runs acceptably on the 8 GB test Mac (Tier A behaviour verified).
- [ ] Crash-free, no idle CPU, memory within budget.

---

## Phase 2: Communication & research (10–14 weeks)

### Marc v1 → [brief](./agents/marc.md)
- [ ] Connectors: Gmail API (or IMAP+OAuth), Microsoft Graph, generic IMAP/SMTP, JMAP.
- [ ] Sync engine: initial sync windows, IDLE/push/delta, offline queue, attachments to the blob store.
- [ ] Unified inbox, threads, reader (sanitised HTML in WKWebView with remote content blocked by default), compose, undo send, snooze.
- [ ] Triage lanes with reasons; drafts with voice (William profile v0); follow-up detection; sender memory → Bolton.
- [ ] iMessage read (chat.db) + send via Messages automation; people timeline.
- [ ] Register as default mail app (optional toggle).
- [ ] Triage eval ≥ 0.95 recall on "needs you".

### James v1 → [brief](./agents/james.md)
- [ ] WebKit browser: tabs, vertical sidebar, spaces/profiles, content blocking, reader mode, history, bookmarks, downloads → Bolton.
- [ ] Page Q&A and tab summaries.
- [ ] Research jobs: planner → search API → fetch → extract → notes → synthesis → cited report; notch progress; reports view.
- [ ] Default browser toggle.

### William v1 → [brief](./agents/william.md)
- [ ] Native editor (TextKit 2, Markdown-backed), inline AI (continue, rewrite, shorten, tone), suggestion mode.
- [ ] Harper grammar (local), voice profile (ingest sent mail + docs), presets.
- [ ] Services menu "Rewrite with William" + hotkey rewrite-in-place via Accessibility.
- [ ] Export: docx, PDF (Typst), Markdown.

### Cross-cutting
- [ ] Approvals UX polish (edit in place, "always allow this kind").
- [ ] Prompt-injection defences live (taint tracking, reader/actor split) + injection test suite in CI.
- [ ] **iPhone app v1**: Today, Approvals, Ask, Capture; same Rust core for iOS; CloudKit sync (`CKSyncEngine`); widgets; Live Activities (local updates); App Intents; Share extension.
- [ ] Handoff between Mac and iPhone for reports and drafts.
- [ ] "Mac as brain" on the same network (Bonjour + pairing).

---

## Phase 3: Builder (6–8 weeks) → [brief](./agents/johnny.md)

- [ ] Spec schema per agent (JSON Schema), spec renderer in each agent UI (sidebar, views, fields, actions).
- [ ] Spec store with git (gix): commit, diff, history, revert, safe mode, try-for-7-days.
- [ ] **Tune** (Core): natural language → spec diff → preview → apply.
- [ ] Terminal (libghostty or SwiftTerm + `portable-pty`), AI command bar, explain/fix, safety classifier + allowlist.
- [ ] Automations engine: triggers, steps, approvals, run history, retries.
- [ ] Mini-apps: sandboxed WKWebView, capability bridge, CSP, permissions prompts, design tokens CSS.
- [ ] Sandbox runner: Seatbelt profile first; Apple Containerization for heavier jobs.
- [ ] Template gallery v0 (where your "cute" ideas go).
- [ ] **= Sellable v1.** Start the private beta (see Phase 6).

---

## Phase 4: Business suite (10–14 weeks)

- [ ] **George** → [brief](./agents/george.md): IronCalc sheets + grid UI, xlsx import/export, AI formulas, DuckDB "ask your data", finance dashboard (CSV/OFX + Xero + Stripe), receipts capture and matching, categorisation, models/calculators (port the existing ones).
- [ ] **Conner** → [brief](./agents/conner.md): CRM-lite from Marc/Leo data, pipeline board, strategy workspace (port the validate/stress-test/GTM/pricing/digest engines), decks (outline → slides with Robert's themes → PDF/PPTX/Keynote), proposals (Typst).
- [ ] **Robert** → [brief](./agents/robert.md): brand kit (shared to all agents), canvas v1, templates for social sizes, Vision image tools, image generation (local Tier C+ / cloud), critique, export.

## Phase 5: Creative & growth (8–10 weeks)

- [ ] **Cole** → [brief](./agents/cole.md): recorder (ScreenCaptureKit + camera), WhisperKit word-level transcript, text-based editing, silence/filler removal, captions, export; auto-clips v2.
- [ ] **Harris** → [brief](./agents/harris.md): learning paths, lessons, FSRS cards (incl. cards from Bolton highlights), language mode with speaking drills, daily session on iPhone, notch quick-review.

---

## Phase 6: Ship (starts in Phase 2, runs continuously)

See [08-shipping-and-business](./08-shipping-and-business.md) for detail.
- [ ] Developer ID signing + hardened runtime + **notarisation** pipeline (`notarytool`, stapling) in CI.
- [ ] Sparkle appcast + delta updates; staged rollout channel (beta/stable).
- [ ] Licensing: Paddle/Lemon Squeezy/Stripe checkout → licence keys/accounts → entitlements; RevenueCat (or similar) to unify with iOS IAP.
- [ ] Minimal backend: account + entitlements + push relay (for Live Activities) + registry hosting. Keep it tiny and serverless.
- [ ] iOS App Store: privacy labels, review notes explaining AI and data handling, StoreKit 2 products per agent, TestFlight beta.
- [ ] Google OAuth verification (restricted Gmail scopes) and Microsoft publisher verification. **Start early in Phase 2.**
- [ ] Website: product pages per agent, pricing, download, docs, privacy policy, terms, support.
- [ ] Onboarding videos (made with Cole, which is good dogfooding).
- [ ] Crash reporting (opt-in, privacy-first) and a local diagnostics bundle users can send.
- [ ] Support: email + in-app "send feedback with diagnostics" (user reviews what's included).
- [ ] Private beta (20–50 founders) → paid early access → public launch.

---

## Continuous (every phase)

- [ ] Dogfood daily. Keep a "papercuts" list and fix 3 per week.
- [ ] Evals on every prompt or model change; track scores over time.
- [ ] Test on the 8 GB Mac every week.
- [ ] Accessibility pass on every new screen (VoiceOver, keyboard, Reduce Transparency/Motion).
- [ ] Performance budgets checked (Instruments) before each release.
- [ ] Update the model registry as new models land (benchmark first).
- [ ] Security: dependency audits, injection suite, permissions review.
- [ ] Write an ADR for every decision you'd forget the reason for.

---

## Week 1, day by day (what you can do yourself, right now)

| Day | Do this | Done when |
|---|---|---|
| **Mon** | Start Apple Developer org enrolment (D-U-N-S). Install Xcode 27, Rust, Tuist. Create branch `mac-rebuild`. Read this plan's README + architecture | Toolchain installed |
| **Tue** | SwiftUI crash course: build a MenuBarExtra app with one window. Then an `NSPanel` at the top of the screen that appears on hover (copy the geometry approach from DynamicNotchKit) | A black shape follows your notch and expands on hover |
| **Wed** | Rust: `cargo new --lib core/crates/elevenam`; add UniFFI; export `version()` and `async ping()`; build an XCFramework; call it from the app | Swift prints a string from Rust |
| **Thu** | Local AI: run `mlx-swift-examples` LLMEval with a 4B model; then call Apple Foundation Models in a playground. Note tok/s on your Mac | Two local models answer in your app |
| **Fri** | Design tokens → Swift; build the 3-zone layout (glass sidebar, paper canvas, glass agent pane) with dummy content in light and dark | It looks like 11am |
| **Sat** | Wire it up: notch "Ask" field → Rust core → brain → MLX → streamed answer back into the notch | **You've built the spine in miniature** |
| **Sun** | Rest. Then score your agent ideas with the triage sheet below | Ideas sorted into core / later / templates |

Weeks 2–4: Bolton indexing one folder + search; Leo reading EventKit + Today view; the event log + activity feed; Model manager v0.

---

## Salvage from the current repo

| Current asset | Where it goes | How |
|---|---|---|
| `packages/ui/src/tokens/index.ts` (colours, agent roster, roles) | `design/tokens.json`, `registry/agents/*.toml` | Port values; regenerate Swift/CSS |
| `packages/ui/src/assets/logos/*.svg` (monograms, wordmark) | Asset catalogue (template vectors), app icons | Clean up the SVGs; Icon Composer for layered icons |
| `packages/ui/src/assets/fonts/AlteHaasGrotesk*.ttf` | App bundle fonts (display only) | **Check the licence for app embedding** |
| `apps/home/src/data/agents.ts` (taglines, copy, "use X when…") | Agent manifests + onboarding copy + website | Copy text directly |
| `apps/leo/src/lib/types.ts` (`AgentInvokeRequest/Response`) | `core/agents` protocol types | Port to Rust structs (see [architecture](./02-architecture.md#inter-agent-protocol-keep-the-existing-contract)) |
| `apps/leo/src/lib/plan/*` (daily, meeting, ops) | `core/leo` prompt packs and logic | Port prompts; replace Postgres calls |
| `apps/bolton/src/lib/db/schema.ts` (memory_entries, entities, relationships, decisions, conflicts, voice/sender profiles, inbox rules, agent summaries) | `core/store` SQLite schema | Translate to SQLite migrations; keep names where sensible |
| `apps/bolton/src/lib/memory/capture.ts`, `decisions`, `entities`, `search` | `core/bolton` curator and search | Port logic and prompts |
| `apps/james/src/lib/research/*` (engine, template, routing, save-heuristic) | `core/james` research jobs | Port the report template and heuristics |
| `apps/marc/src/lib/*` (triage, replies, rules, cleanup, briefings, handoffs) + the **safety model** + `action_log` | `core/marc` + global policy engine + `events` | Port prompts; generalise the safety model to all agents |
| `apps/william/src/lib/voice/*` (analyse, embeddings, profile jobs), generation | `core/william` voice profiles | Port; switch embeddings to local |
| `apps/george/src/lib/finance/*`, `models`, `import/spreadsheet`, `xero`, `stripe`, `TaxDisclaimer` | `core/george` | Port the engines; reuse the disclaimer copy |
| `apps/conner/src/lib/strategy/engine.ts` (validate, stress test, GTM, growth, pricing, digest) | `core/conner` strategy tools | Port prompts as tools |
| `apps/robert/src/lib/design/engine.ts` (brand direction, moodboard, logo concepts, audit, landscape, implementation brief) | `core/robert` | Port prompts as tools |
| `apps/cole/src/lib/*` (script, concepts, storyboard, motion templates, whisper, ffmpeg) | `core/cole` + Swift AVFoundation | Port prompts; replace ffmpeg with AVFoundation where possible |
| `apps/harris/src/lib/learning/engine.ts` (plan, roadmap, exercises, explain, gap plan, French SRS) | `core/harris` | Port prompts; replace SRS with FSRS |
| `packages/jobs` (queue, budget + tests, events, sandbox, GitHub, push, checks) | `core/scheduler` + `core/johnny` | Port the design; keep the budget tests as Rust tests |
| `apps/*/src/lib/tiers` (free/pro) | Entitlements system | Replace with add-on entitlements |
| Next.js apps themselves | `legacy/web/` | Keep as reference; possibly a future web/Windows companion |

---

## Idea triage sheet

Copy this table for each agent and score your ideas (see the [gimmick filter](./01-product.md#the-gimmick-filter)):

| Idea | Agent | Freq | Time | Replaces | Needs AI | Fit | Low-tier | Trust | **Total /14** | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| *e.g. "Leo plays a chime at 11am"* | Leo | 2 | 0 | 0 | 0 | 2 | 2 | 2 | **8** | Later / setting |
| *e.g. "Marc auto-unsubscribes newsletters"* | Marc | 2 | 1 | 1 | 1 | 2 | 2 | 1 | **10** | Later (v2, with preview) |
| *e.g. "Agents have little animated avatars"* | All | 2 | 0 | 0 | 0 | 0 | 2 | 2 | **6** | Template / no |
| | | | | | | | | | | |

---

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Scope explosion (11 apps solo) | High | High | Phase gates; sellable v1 at Phase 3; gimmick filter; "not building" lists |
| Learning curve (Swift + Rust at once) | High | Medium | Week-1 spine; small Rust surface at first; Swift-only fallback ADR |
| Local model quality on Tier A/B disappoints | Medium | High | Rules-first design; Apple FM; cloud option; overnight mode; honest UI |
| Google Gmail verification delays | Medium | High | Start early; IMAP for other providers; Outlook first if needed |
| Apple changes (private behaviours around the notch, TCC rules) | Medium | Medium | Use public APIs only; fallback pill; follow betas each June |
| iMessage access breaks in a macOS update | Medium | Medium | Isolate it behind an adapter; degrade gracefully; it's a feature, not the foundation |
| Prompt injection causing a harmful action | Medium | High | Taint tracking, approvals, reader/actor split, test suite |
| Kimi/cloud pricing or availability changes | Medium | Low | Provider abstraction; registry updates; multiple providers |
| Burnout | Medium | High | Dogfood joy; ship add-ons as wins; protect your own 11am check-in |
