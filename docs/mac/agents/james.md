# james: research and browser

> **The one-liner:** James is your browser and your researcher. Browse normally with a sharp assistant beside you, or hand him a question and get back a sourced, honest answer.
> **Package:** Add-on · **Monogram:** `jm` · **App name:** *James*

## Role in the team
James is how the team learns about the outside world. He researches, compares, verifies and synthesises, and he's the browser you use every day. Other agents ask James when they need facts: Leo for meeting briefs, Conner for markets, George for prices, Harris for learning sources, Robert for references.

## Replaces / enhances
Safari and Chrome (daily browsing), Google/Perplexity/ChatGPT search, read-later apps (Pocket, Instapaper), bookmarks managers, "deep research" tools, competitor-monitoring tools (Visualping).

## Use cases
1. **Research job:** *"Best payroll software in Australia for 5 staff, with STP2 support, under A$100/month."* James plans sub-questions, searches, reads 20–40 sources in the background (progress in the notch), compares them in a table, and writes a report with citations, confidence levels and "what this means for you".
2. **Page Q&A while browsing:** "what's the cancellation policy on this page?" or "summarise these 6 tabs".
3. **Compare tabs:** open 4 product pages and ask "compare price, limits, support". You get a table.
4. **Meeting briefs for Leo:** company and person background with sources, 30 minutes before the call.
5. **Watches:** "tell me when Competitor X changes their pricing page". A daily diff, alerting only on meaningful changes.
6. **Fact-check:** select a claim in William, ask James to verify, and get supporting or contradicting sources.
7. **Reading list:** save an article and James summarises it, tags it, files it in Bolton, and adds it to Harris's reading queue if it's learning material.
8. **Academic mode:** papers via arXiv/Semantic Scholar APIs, PDF reading with explanations.

## Features

### v1 (MVP)
- **Browser (WebKit):** tabs, vertical sidebar with spaces (Arc-style), per-space profiles (separate cookies via `WKWebsiteDataStore(forIdentifier:)`), pinned tabs, split view (2 panes), find-in-page, downloads → Bolton, history, bookmarks, reader mode (Readability.js injection), **content blocking** (EasyList-style lists compiled to `WKContentRuleList`), private windows, AutoFill via iCloud Keychain/Passwords where WebKit supports it.
- **James pane:** summarise page, ask the page, extract (tables, contacts, prices), "save to Bolton", "research this further".
- **Tab summaries** and "compare tabs" table.
- **Research jobs:** planner → search provider(s) → fetch → extract main content → per-source notes → synthesis with inline citations → **claim verification** (each claim must map to a quote in a source) → report.
- **Reports view:** editorial layout, sources list with credibility notes, claims with confidence, "what this means for you", follow-up questions; export to William/Bolton/PDF.
- **Default browser** toggle.

### v2
- **Agentic browsing** (in an isolated "agent" profile): navigate, click and fill forms to gather information; **any submission, purchase or login needs approval**; a visible "James is driving" overlay with a stop button.
- **Watches/monitors:** scheduled page diffs with meaningful-change detection.
- **Academic sources:** arXiv, Semantic Scholar, PubMed APIs; PDF research reader.
- **Web extensions:** `WKWebExtension` (macOS 15.4+, check maturity) for Safari-format extensions like password managers.
- **Safari extension** for people who keep Safari ("Ask James about this page").

### Later
- Research templates (market sizing, competitor teardown, vendor selection, due diligence).
- Shared research packs (export a report with sources as a bundle).

### Not building
- A Chromium fork or Chrome-extension compatibility (WebKit only).
- A search engine or crawler index (use search APIs).
- Sync with Chrome/Firefox profiles (one-time import of bookmarks and history at most).
- Social media browsing features.

## How the AI is involved

| Feature | Task class | Autonomy | Trigger |
|---|---|---|---|
| Tab/page summary | `summarise.medium` (Apple FM for short pages on Tier A) | L3 | Command / hover option |
| Page Q&A | `summarise.medium` with the page as context | — | Ask |
| Research planning | `reason.large` (Kimi's long context shines here) | L2 (plan shown) | Ask |
| Source reading/notes | `summarise.medium` in parallel (local) | L3 | Job step |
| Synthesis | `reason.large` (cloud with consent) or best local | L3 → report | Job step |
| Claim verification | Quote matching (code) + `classify.small` entailment check | L3 | Job step |
| Watches | Diff (code) + `classify.small` "meaningful?" | L2 (alert) | Schedule |
| Agentic browsing | Actor model with DOM/AX snapshot; **reader/actor split** | **L1 for any submit** | Ask |

**Security:** web pages are the most hostile input there is. Research jobs run without access to Marc, Bolton private data or tools that write externally (they're *tainted* by definition). Page content is read by a reader model; only structured notes reach the planner. Agentic browsing uses a separate profile with no saved logins unless you grant one for a task.

**Search providers (pluggable):** Brave Search API, Exa, Tavily, Kagi (API), self-hosted SearXNG, Jina Reader for fetching. Show the per-query cost in settings and let the user pick. (Bing's Search API was retired in 2025.)

## Works with
- **Leo:** meeting briefs, project research steps.
- **Conner:** market research, competitor teardowns.
- **George:** prices, benchmarks, vendor costs.
- **William:** citations and fact-checks.
- **Bolton:** saves sources, reports and clips; supplies prior research ("we looked at this in March").
- **Harris:** learning resources.
- **Robert:** visual references and moodboards.
- **Johnny:** API docs for building connectors.

## Design and visual identity
- **Pattern:** dot grid with a lens aperture.
- **Motion:** a thin scan line passes across source chips as they're read; the progress ring fills in the notch.
- **Tone:** measured and honest about uncertainty. "Two sources agree; one older source disagrees."

### Wireframe: browser with James pane
```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ jm  ◀ ▶ ⟳   🔒 keypay.com.au/pricing                          ⌕ ask james…  ⋯  │
├──────────────┬───────────────────────────────────────────────────┬───────────────┤
│ Space: Work ▾│                                                   │ james         │
│ ─ pinned ─   │    [ web page content: solid, full width ]        │ This page     │
│  Gmail       │                                                   │ ─ Plans from  │
│  Xero        │                                                   │   A$4/employee│
│ ─ today ─    │                                                   │ ─ STP2: yes   │
│ ▸ KeyPay     │                                                   │ ─ Min 1 user  │
│   Employment │                                                   │               │
│   Hero       │                                                   │ Compare 4 tabs│
│   Xero Payroll│                                                  │ Save to bn    │
│ ─ research ─ │                                                   │ Research more │
│ ◯ AU payroll │                                                   │               │
│   18/30      │                                                   │ Ask james…    │
│ + New tab    │                                                   │ ● on-device   │
└──────────────┴───────────────────────────────────────────────────┴───────────────┘
```

### Wireframe: research report
```
╭──────────────────────────────────────────────────────────────────────────────────╮
│  Payroll software for a 5-person Australian team                                 │
│  james · 31 sources · 14 min · confidence: high (pricing), medium (support)     │
│ ─────────────────────────────────────────────────────────────────────────────── │
│  Recommendation  Employment Hero (Standard): best fit at ≈A$X/mo for 5 staff,    │
│                  STP2-compliant, Xero integration native [3][7].                 │
│  What this means Switch before the new FY; George estimates A$Y/yr saving.       │
│ ─ comparison ──────────────────────────────────────────────────────────────────  │
│   Product        Price/5 staff   STP2   Xero   Support      Sources              │
│   Employment H.  A$X             ✓      ✓      chat/phone   [3][7][12]           │
│   KeyPay         A$X             ✓      ✓      email        [1][4]               │
│   Xero Payroll   incl. plan      ✓      —      email        [2][9]               │
│ ─ disagreements ── [4] (2024) lists an older price; newer sources agree on A$X.  │
│ ─ sources ── [1] keypay.com.au/pricing · fetched 28 Oct ·  primary               │
╰──────────────────────────────────── send to william ▸  save to bolton ▸ ───────╯
```

## Usability
- **Shortcuts:** ⌘T new tab · ⌘L address/ask · ⌘⇧J James pane · ⌘⇧R research this · ⌘⇧S split view · ⌃Tab switch tabs · ⌘⌥R reader mode.
- **The address bar is also the Ask bar:** type a URL, a search or a question ("? …" or ⌘⏎ for research).
- **Onboarding:** import bookmarks/history from Safari/Chrome (one-time, optional) → pick a search provider (or use the 11am default with credits) → set up spaces (Work, Personal).
- **Honesty UI:** confidence per claim, disagreements shown, "couldn't verify" sections, source dates.
- **Empty state:** dot-grid pattern; "Browse, or ask James a question worth researching."

## Notch and iPhone
- **Notch:** live research progress (ring + `18/30`); "Report ready" peek; watch alerts.
- **iPhone:** read reports, start research by voice, share sheet "Ask James about this link", watch alerts. (No iPhone browser: iOS users keep Safari, and the share sheet is the bridge.)

## Mac integration
WebKit (`WKWebView`, `WKWebsiteDataStore(forIdentifier:)`, `WKContentRuleListStore`, `WKUserScript` for Readability/extraction, `WKWebExtension` later) · default browser registration (`NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` for http/https) · Handoff from iPhone Safari (`NSUserActivity` web browsing) · PDFKit · Passwords/AutoFill · Share extension · Safari Web Extension (v2) · App Intents ("Research…", "Summarise this page").
**Permissions:** none beyond network; downloads folder access via Bolton.

## Backend
- **Rust `core/james`:** research job engine (planner DAG, parallel fetch with `reqwest`, per-domain rate limits, robots awareness, cache), search provider adapters, extraction (Readability port / `scraper` + heuristics à la trafilatura), source store, citation graph, claim verifier, report renderer (Markdown + JSON), watches (scheduled fetch + diff).
- **Tables:** `research_jobs(id, question, plan_json, status, budget, cost)`, `sources(id, url, title, fetched_at, publisher, date, text_ref, credibility)`, `notes(id, job_id, source_id, claims_json)`, `reports(id, job_id, markdown, json, confidence)`, `watches(id, url, selector, schedule, last_hash, last_alert)`, `history(id, url, title, visited_at, space)`, `bookmarks`.
- **Swift:** browser shell, tab model, WebKit configuration, injected scripts (Readability, DOM snapshot for page Q&A/agentic browsing), report UI.
- **Port from current repo:** `apps/james/src/lib/research/{engine, template, routing, memory, save-heuristic}.ts`.

## Lower-end Macs
- **Tier A:** browsing is light (WebKit). Page summaries via Apple FM (short pages) or a small model; research synthesis via cloud (consent) or **overnight**; parallel fetch limited to 3.
- **Tier B:** local page Q&A; research reading local; synthesis cloud or local "good enough" mode.
- **Tier C+:** fully local research with Qwen 3.6 35B-A3B-class models.

## Open source to study
Ora browser and `nook-browser/Nook` (WebKit browsers; licences: GPL/check, study only) · `zen-browser/desktop` (UX) · `browser-use/browser-use` (agent DOM extraction) · `assafelovic/gpt-researcher` · `stanford-oval/storm` · `ItzCrazyKns/Perplexica` · `LearningCircuit/local-deep-research` · `dzhng/deep-research` · `mozilla/readability` · `adbar/trafilatura` · `unclecode/crawl4ai` · `brave/adblock-rust` · `jina-ai/reader`.

## Tunable by Johnny
Report templates and sections; trusted and blocked domains; research depth presets (quick 5 sources / standard 20 / deep 50); watch schedules; spaces and their rules ("Work space: always reader mode for news").

## Risks and open questions
- **Site breakage with WebKit** (some sites are Chrome-only). Keep "Open in Chrome/Safari" one click away.
- **Search API costs.** Meter them, cache, and let users bring their own key.
- **Hallucinated citations.** The claim verifier must reject any claim without a matching quote, which matters more than eloquence.
- **Agentic browsing risks** (wrong purchases, data leaks). Use an isolated profile, approvals, and visible control.
- **Open question:** make James the default browser at onboarding? Recommendation: offer it after 3 days of use, not on day one.

## Build checklist
- [ ] WebKit browser shell: tabs, sidebar, spaces/profiles, history, bookmarks, downloads
- [ ] Content blocking (compiled rule lists) + reader mode
- [ ] James pane: summarise, ask, extract, save
- [ ] Compare tabs
- [ ] Search provider adapters + settings + metering
- [ ] Research job engine + notch progress + reports UI
- [ ] Claim verifier + faithfulness eval
- [ ] Default browser registration
- [ ] Leo meeting-brief integration
- [ ] v2: agentic browsing (isolated), watches, academic APIs, extensions, Safari extension
