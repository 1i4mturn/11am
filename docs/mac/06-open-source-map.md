# 06: Open-source map (GitHub repos to learn from and build on)

## How to read this

**Licence key (this decides whether you can copy code into a closed-source, paid app):**
| Mark | Meaning | What you can do |
|---|---|---|
| ✅ | Permissive (MIT, Apache-2.0, BSD, ISC, Unlicense, BSL-1.0) or file-level copyleft (MPL-2.0) | Use the code or depend on it. Keep the licence notice (add it to `THIRD_PARTY_NOTICES`). MPL: changes to MPL files themselves must be shared |
| ⚠️ | Strong copyleft (GPL, AGPL, LGPL) | **Study the architecture and UX; don't paste code into 11am.** LGPL libraries may be dynamically linked. GPL/AGPL programs may be run as *separate, unmodified* processes only if you comply with their terms (get advice) |
| 🔶 | Source-available / custom licence | Read the terms. Usually needs a commercial licence |
| ❓ | Not verified | Check the `LICENSE` file before using |

Licences and repo locations move (projects get renamed or archived). Verify each one before depending on it. Star counts aren't listed because they change weekly.

---

## A. App shell, notch, menu bar, Mac utilities

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `MrKai77/DynamicNotchKit` | SwiftUI content in the notch, with a floating fallback for Macs without one | **Notch base or reference** | ✅ (check) |
| `TheBoredTeam/boring.notch` | Notch app: media, calendar, shelf with AirDrop, HUD replacement | Notch UX ideas, shelf, hover behaviour | ⚠️ GPL-3.0 |
| `Ebullioscopic/Atoll` | Notch app (formerly DynamicIsland): media, lock-screen widgets, stats; v2 adds terminal | Notch states and live activities patterns | ⚠️ GPL-3.0 |
| `rutmehta/Atoll` (fork) | Shows live Claude Code / Codex sessions in the notch, approve tool permissions from there | **Exactly your "approvals in the notch" idea**, a reference | ✅ MIT per README (check) |
| `Lakr233/NotchDrop` | Notch shelf / AirDrop | Shelf drag-and-drop | ❓ |
| `sindresorhus/KeyboardShortcuts` | User-customisable global hotkeys | Ask bar, voice, notch hotkeys | ✅ MIT |
| `sindresorhus/LaunchAtLogin-Modern` | `SMAppService` wrapper | Login item | ✅ MIT |
| `sindresorhus/Defaults` | Typed UserDefaults | Swift-side prefs | ✅ MIT |
| `sparkle-project/Sparkle` | Auto-updates for direct-distributed apps | **Updates** | ✅ MIT |
| `p0deje/Maccy` | Clipboard manager | Bolton shelf / clipboard history | ✅ MIT |
| `rxhanson/Rectangle` | Window management | Window layout helpers (Leo focus layouts) | ✅ MIT |
| `nikitabobko/AeroSpace` | Tiling window manager | Accessibility-driven window control reference | ✅ MIT |
| `Hammerspoon/hammerspoon` | Lua automation of macOS | Patterns for AX, Apple Events, hotkeys (Johnny) | ✅ MIT |
| `exelban/stats` | Menu bar system monitor | Johnny "Mac health" metrics (CPU, memory, battery, thermal) | ✅ MIT |
| `jordanbaird/Ice` | Menu bar manager | Menu bar item behaviour | ⚠️ GPL-3.0 |
| `MrKai77/Loop` | Radial window manager | Gesture/radial UI ideas | ⚠️ GPL-3.0 (check) |
| `lwouis/alt-tab-macos` | Window switcher | Window enumeration, thumbnails | ⚠️ GPL-3.0 |
| `raycast/extensions` | Raycast's extension store | Command-bar UX and the shape of "commands" | ✅ MIT |

## B. Swift / native UI libraries

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `apple/swift-collections`, `apple/swift-async-algorithms` | Data structures, async sequences | Everywhere | ✅ Apache-2.0 |
| `apple/swift-markdown` | Markdown parsing | Notes rendering, William | ✅ Apache-2.0 |
| `gonzalezreal/swift-markdown-ui` | Markdown rendering in SwiftUI | Reports, notes, chat-ish output | ✅ MIT |
| `pointfreeco/swift-snapshot-testing` | Snapshot tests | UI regression (light/dark/Reduce Transparency) | ✅ MIT |
| `pointfreeco/swift-composable-architecture` | State management | Optional. Plain `@Observable` is probably enough | ✅ MIT |
| `groue/GRDB.swift` | SQLite for Swift | Only if you go Swift-only (fallback plan) | ✅ MIT |
| `tuist/tuist` / `yonaskolb/XcodeGen` | Generate Xcode projects | Keep `.xcodeproj` out of git conflicts | ✅ MIT |
| `realm/SwiftLint`, `apple/swift-format` | Lint and format | CI | ✅ MIT / Apache |
| `CodeEditApp/CodeEdit` + `CodeEditSourceEditor` | Native macOS code editor | Johnny's script/spec editor | ✅ MIT |
| `krzyzanowskim/STTextView` | TextKit 2 text view | William editor base (if TextKit 2 alone isn't enough) | ❓ (dual licence, check) |
| `huggingface/swift-transformers` | Tokenizers and Hub client in Swift | Model download and tokenisation | ✅ Apache-2.0 |
| `simonbs/Runestone` | Fast code text view (iOS) | Johnny on iPhone (view scripts) | ✅ MIT |
| `apple/swift-openapi-generator` | Generate clients from OpenAPI | Connectors on the Swift side | ✅ Apache-2.0 |

## C. Rust core, bridge, infrastructure

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `mozilla/uniffi-rs` | Rust → Swift bindings generator | **The bridge** | ✅ MPL-2.0 |
| `chinedufn/swift-bridge` | Alternative Rust ↔ Swift bridge | Fallback option | ✅ MIT/Apache |
| `antoniusnaumann/cargo-swift` | Build Rust into an XCFramework + Swift package | Packaging | ❓ |
| `tokio-rs/tokio` | Async runtime | Scheduler, connectors | ✅ MIT |
| `tokio-rs/tracing` | Structured logging | Event log, diagnostics | ✅ MIT |
| `rusqlite/rusqlite` | SQLite bindings | **Storage** | ✅ MIT |
| `launchbadge/sqlx` | Async SQL | Alternative to rusqlite | ✅ MIT/Apache |
| `asg017/sqlite-vec` | Vector search inside SQLite | **Embeddings index** | ✅ MIT/Apache |
| `quickwit-oss/tantivy` | Full-text search engine | When FTS5 isn't enough (big mail corpora) | ✅ MIT |
| `lancedb/lancedb` | Embedded vector DB | Very large vector sets | ✅ Apache-2.0 |
| `qdrant/qdrant` | Vector DB | Home-server mode at scale | ✅ Apache-2.0 |
| `notify-rs/notify` | Cross-platform FS events (FSEvents on macOS) | Bolton incremental indexing | ✅ (check exact licence) |
| `automerge/automerge` | CRDT | Notes/docs merge across devices | ✅ MIT |
| `y-crdt/y-crdt` (Yrs) | CRDT (Yjs in Rust) | Alternative to Automerge | ✅ MIT |
| `n0-computer/iroh` | P2P QUIC connections with NAT traversal | "Mac as brain" off-network (v2) | ✅ MIT/Apache |
| `GitoxideLabs/gitoxide` | Pure-Rust git | **Spec versioning** (Johnny) | ✅ MIT/Apache |
| `rust-lang/git2-rs` | libgit2 bindings | Alternative | ✅ MIT/Apache |
| `seanmonstar/reqwest` | HTTP client | Connectors, cloud models | ✅ MIT/Apache |
| `ramosbugs/oauth2-rs` | OAuth2 client | Gmail, Graph, Xero | ✅ MIT/Apache |
| `Stranger6667/jsonschema` | JSON Schema validation | Tool I/O, spec validation | ✅ MIT |
| `bytecodealliance/wasmtime` | WASM runtime | Johnny user scripts (sandboxed) | ✅ Apache-2.0 |
| `EmbarkStudios/cargo-deny` | Licence and advisory checks | **CI: blocks GPL deps creeping in** | ✅ MIT/Apache |
| `0xPlaygrounds/rig` | Rust LLM application framework | Patterns for providers, tools, RAG in Rust | ✅ MIT |

## D. Local AI runtime and models

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `ml-explore/mlx` | Apple's array framework for Apple Silicon | Foundation of local inference | ✅ MIT |
| `ml-explore/mlx-lm` | LLM inference, serving, **LoRA fine-tuning** in Python | Model conversion, personal adapters (later) | ✅ MIT |
| `ml-explore/mlx-swift` | MLX for Swift | ModelHost | ✅ MIT |
| `ml-explore/mlx-swift-lm` | LLMs/VLMs, tool calling, embeddings in Swift | **ModelHost's main engine** | ✅ MIT (check) |
| `ml-explore/mlx-swift-examples` | Demo apps | Learning | ✅ MIT |
| `Blaizzy/mlx-vlm` | Vision-language models on MLX | Robert/George vision on high tiers | ✅ MIT |
| `Blaizzy/mlx-audio` | TTS/STT/STS on MLX (incl. Kokoro) | Harris, Cole voices | ✅ MIT |
| `ggml-org/llama.cpp` | GGUF inference | Fallback engine, huge model coverage | ✅ MIT |
| `utilityai/llama-cpp-rs` | `llama-cpp-2` Rust bindings | llama.cpp from the Rust core | ✅ MIT/Apache |
| `ggml-org/whisper.cpp` | Whisper in C/C++ | STT fallback | ✅ MIT |
| `argmaxinc/argmax-oss-swift` | **WhisperKit**, SpeakerKit (diarisation), TTSKit | **All on-device speech** | ✅ MIT |
| `hexgrad/kokoro` | Small high-quality TTS model | Voices for Harris/Cole | ✅ Apache-2.0 |
| `filipstrand/mflux` | FLUX and other image models on MLX | Robert local image generation (Tier C+) | ✅ MIT |
| `ollama/ollama` | Local model manager and server | Support as a provider; model-management UX reference | ✅ MIT |
| `lmstudio-ai/mlx-engine` | LM Studio's MLX engine | Reference for an MLX serving layer | ✅ MIT (check) |
| `osaurus-ai/osaurus` | Mac-native local LLM server | Reference for a Swift model server | ❓ |
| `exo-explore/exo` | Distributed inference across Macs (RDMA over Thunderbolt 5) | Tier F: run Kimi-class models at home | ❓ (check) |
| `EricLBuehler/mistral.rs` | Rust inference engine with Metal | Pure-Rust alternative | ✅ MIT |
| `huggingface/candle` | Rust ML framework | Small Rust-side models (embeddings) | ✅ MIT/Apache |
| `simonw/llm` | CLI with a plugin system for models | **Design reference for "add more models"** | ✅ Apache-2.0 |
| `dottxt-ai/outlines` | Structured generation | Ideas for constrained JSON output | ✅ Apache-2.0 |

## E. Agents, tools, MCP, memory

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `modelcontextprotocol/rust-sdk` (`rmcp`) | Official Rust MCP SDK | **11am as MCP client and server** | ❓ (check) |
| `modelcontextprotocol/swift-sdk` | Official Swift MCP SDK | Swift-side MCP if needed | ❓ (check) |
| `modelcontextprotocol/servers` | Reference MCP servers | Connector patterns | ✅ MIT |
| `aaif-goose/goose` (ex `block/goose`) | Rust agent with native MCP, desktop and CLI, local models | **Closest architecture to your core; study deeply** | ✅ Apache-2.0 |
| `openai/codex` | Rust coding agent CLI; **Seatbelt sandboxing and approval modes on macOS** | Johnny's sandbox and approval design | ✅ Apache-2.0 |
| `All-Hands-AI/OpenHands` | Autonomous coding agent platform | Johnny coding-agent patterns | ✅ MIT |
| `Aider-AI/aider` | Pair-programming agent | Repo maps, edit formats | ✅ Apache-2.0 |
| `sst/opencode` | Terminal coding agent | TUI agent UX | ✅ MIT |
| `cline/cline` | IDE agent with approvals | Approval UX for tool calls | ✅ Apache-2.0 |
| `huggingface/smolagents` | Minimal agents library (+ open deep research example) | Simple agent loops | ✅ Apache-2.0 |
| `langchain-ai/langgraph` | Graph-based agent orchestration with checkpoints | Ideas for durable multi-step jobs | ✅ MIT |
| `mem0ai/mem0` | Memory layer for agents | Bolton memory curation patterns | ✅ Apache-2.0 |
| `getzep/graphiti` | Temporal knowledge graph (bi-temporal facts) | **Bolton's validity/supersedes model** | ✅ Apache-2.0 |
| `letta-ai/letta` | Stateful agents (MemGPT) | Core/archival memory split | ✅ Apache-2.0 |
| `aurelio-labs/semantic-router` | Embedding-based intent routing | **Leo's fast router** | ✅ MIT |
| `screenpipe/screenpipe` (formerly `mediar-ai`) | 24/7 local screen and audio memory, MCP server | Optional "screen memory" in Bolton (Tier D+) | ❓ (check; site says MIT) |
| `microsoft/markitdown` | Convert Office/PDF/HTML to Markdown | Ingestion | ✅ MIT |
| `docling-project/docling` | Document parsing (layout, tables) | High-quality PDF/Office ingestion | ✅ MIT |
| `Unstructured-IO/unstructured` | Document ETL | Alternative ingestion | ✅ Apache-2.0 |

## F. Marc: mail and messages

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `elie222/inbox-zero` | AI email assistant (Gmail/Outlook): rules, drafts, bulk unsubscribe, cold-email blocker | **Triage, rule and draft UX** | ⚠️ AGPL-3.0 |
| `Mail-0/Zero` | Open-source AI email client | Modern client UX | ❓ (check) |
| `pimalaya/himalaya` | Rust CLI mail client (IMAP, Maildir, SMTP, Notmuch) | Rust mail engine reference | ✅ MIT |
| `pimalaya/core` | Rust email/IMAP/SMTP libraries behind himalaya | **Possible engine building blocks** | ✅ MIT |
| `async-email/async-imap` | Async IMAP client | IMAP sync with IDLE | ✅ MIT/Apache |
| `jonhoo/rust-imap` | IMAP client | Alternative | ✅ MIT/Apache |
| `stalwartlabs/mail-parser` | Fast, robust MIME parser | **Parsing every email** | ✅ Apache/MIT |
| `stalwartlabs/mail-send` | SMTP sending | Outbound | ✅ Apache/MIT |
| `stalwartlabs/jmap-client` | JMAP client | Fastmail and JMAP accounts | ✅ Apache/MIT |
| `lettre/lettre` | SMTP client and message builder | Outbound (alternative) | ✅ MIT |
| `cure53/DOMPurify` | HTML sanitiser | Safe HTML email rendering (in WKWebView) | ✅ Apache/MPL |
| `Foundry376/Mailspring` | Desktop mail client (C++ sync engine) | Sync engine design, UI ideas | ⚠️ GPL-3.0 |
| `thunderbird/thunderbird-desktop` (mirror) | Thunderbird | Protocol edge cases | ✅ MPL-2.0 |
| `ReagentX/imessage-exporter` | Rust `chat.db` parser/exporter | **iMessage schema knowledge** (attachments, reactions, edits) | ⚠️ GPL-3.0 |
| `openclaw/imsg` | iMessage CLI with JSON-RPC (read chat.db, send via AppleScript) | Approach reference | ❓ |
| `adelaidasofia/imessage-mcp` | iMessage MCP server with draft-and-confirm send | Safety pattern reference | ❓ |
| `BlueBubblesApp/bluebubbles-server` | iMessage bridge server on a Mac | Edge cases with Messages.app | ❓ (check) |
| `tdlib/td` | Official Telegram client library | **Telegram connector** | ✅ BSL-1.0 |
| `mautrix/*` bridges | Matrix bridges (WhatsApp, Signal…) | Reference only. Unofficial WhatsApp access breaches ToS | ⚠️ AGPL |

## G. James: browser and research

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| Ora browser (`the-ora/browser`, check path) | SwiftUI + WebKit Arc-style browser (alpha) | **Native WebKit browser architecture** | ⚠️ GPL-3.0 |
| `nook-browser/Nook` (check path) | WebKit Arc alternative | Sidebar/spaces UX | ❓ |
| `zen-browser/desktop` | Firefox-based Arc-like browser | Vertical tabs, workspaces UX | ✅ MPL-2.0 |
| `browser-use/browser-use` | AI browser agent (DOM extraction, actions) | **Agentic browsing patterns** (port the DOM snapshot ideas to injected JS in WKWebView) | ✅ MIT |
| `assafelovic/gpt-researcher` | Autonomous research agent with cited reports | **Research job pipeline** | ✅ Apache-2.0 |
| `stanford-oval/storm` | Outline-driven long-form research articles | Report structure, perspective-guided questioning | ✅ MIT |
| `ItzCrazyKns/Perplexica` | Self-hosted Perplexity alternative (SearXNG + local models) | Answer-engine UX | ✅ MIT |
| `LearningCircuit/local-deep-research` | Local deep research (arXiv, PubMed, web) with MCP server | Local-model research reference | ✅ MIT |
| `dzhng/deep-research` | Minimal recursive deep-research agent | Simple, readable algorithm | ✅ MIT (check) |
| `unclecode/crawl4ai` | LLM-friendly crawler | Fetch/extract patterns | ✅ Apache-2.0 |
| `adbar/trafilatura` | Main-content extraction | Extraction heuristics (port or reference) | ✅ Apache-2.0 |
| `mozilla/readability` | Reader-mode extraction (JS) | **Inject into WKWebView for clean text** | ✅ Apache-2.0 |
| `jina-ai/reader` | URL → LLM-ready Markdown | Reference / hosted option | ✅ Apache-2.0 |
| `brave/adblock-rust` | Brave's ad-block engine in Rust | Content blocking engine (or compile lists to `WKContentRuleList`) | ✅ MPL-2.0 |
| `gorhill/uBlock` | uBlock Origin | Filter semantics reference | ⚠️ GPL-3.0 |
| `searxng/searxng` | Metasearch engine | Optional self-hosted search backend (separate process) | ⚠️ AGPL-3.0 |
| `firecrawl/firecrawl` | Web scraping API | Reference / hosted option | ⚠️ AGPL-3.0 |
| `microsoft/playwright` | Browser automation | Only if you ever need Chromium automation | ✅ Apache-2.0 |
| `mozilla/pdf.js` | PDF rendering in JS | Research PDFs in WebView (PDFKit preferred) | ✅ Apache-2.0 |

## H. Bolton: files, knowledge, memory

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `spacedriveapp/spacedrive` | Rust "virtual distributed filesystem" file manager (v2 rewrite, P2P sync via iroh) | **File indexing architecture**, library model | ⚠️ AGPL-3.0 |
| `sxyazi/yazi` | Rust async terminal file manager | Async IO, previews, plugin model | ✅ MIT |
| `toeverything/AFFiNE` | Local-first docs + whiteboard | Block editor, local-first patterns | ❓ (check edition licences) |
| `AppFlowy-IO/AppFlowy` | Rust + Flutter Notion alternative | Rust collab (Yrs) document model | ⚠️ AGPL-3.0 |
| `logseq/logseq` | Outliner knowledge base | Backlinks, block references | ⚠️ AGPL-3.0 |
| `siyuan-note/siyuan` | Local-first PKM | Block-level references, export | ⚠️ AGPL-3.0 |
| `khoj-ai/khoj` | Personal AI over your notes and docs | Search and answer patterns | ⚠️ AGPL-3.0 |
| `Mintplex-Labs/anything-llm` | All-in-one desktop RAG app | Workspace/document RAG UX | ✅ MIT |
| `reorproject/reor` | Local AI note app (**archived Mar 2026**) | Lessons from a local-AI notes app | ⚠️ AGPL-3.0 |
| `paperless-ngx/paperless-ngx` | Document management with OCR and auto-matching | **Auto-tagging and matching rules design** | ⚠️ GPL-3.0 |
| `immich-app/immich` | Self-hosted photos with ML search | Media indexing ideas | ⚠️ AGPL-3.0 |
| `photoprism/photoprism` | Photo management with AI tagging | Media indexing ideas | ⚠️ AGPL-3.0 |
| `jgm/pandoc` | Universal document converter | Optional shell-out converter | ⚠️ GPL-2.0 |
| `datalab-to/marker` | PDF → Markdown with layout models | Reference | ⚠️ GPL-3.0 (+ model licence) |
| `ajrcarey/pdfium-render` | PDFium from Rust | Rust-side PDF text where PDFKit isn't available (iOS has PDFKit too) | ✅ MIT/Apache |
| `microsoft/markitdown`, `docling-project/docling` | (see E) | Ingestion | ✅ MIT |

## I. William: writing

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `Automattic/harper` | **Rust grammar checker, offline, fast** | Grammar and style, instant and local | ✅ Apache-2.0 |
| `vale-cli/vale` | Prose linter with custom style rules | **Brand voice rules** ("never say 'leverage'") as code | ✅ MIT |
| `typst/typst` | Rust typesetting system | **Beautiful PDF export** (docs, proposals, invoices) | ✅ Apache-2.0 |
| `bokuweb/docx-rs` | Rust .docx writer/reader | Word export/import | ✅ MIT |
| `languagetool-org/languagetool` | Grammar checker (Java) | Optional, separate service only | ⚠️ LGPL-2.1 |
| `ueberdosis/tiptap` | ProseMirror-based editor | Mini-app editors (web) | ✅ MIT |
| `facebook/lexical` | Web text editor framework | Mini-app editors (web) | ✅ MIT |
| `TypeCellOS/BlockNote` | Block-based editor | Mini-app editors (web) | ✅ MPL-2.0 |
| `krzyzanowskim/STTextView` | TextKit 2 view | Native editor base | ❓ |

## J. Johnny: terminal, automation, coding

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `ghostty-org/ghostty` | Fast terminal; **libghostty** is an embeddable C-ABI terminal | **Johnny's terminal** | ✅ MIT |
| `Lakr233/libghostty-spm` | libghostty as a Swift package (XCFramework) with SwiftUI wrapper | Easier embedding | ❓ |
| `migueldeicaza/SwiftTerm` | Pure-Swift terminal emulator view | Simpler alternative to libghostty | ✅ MIT |
| `wavetermdev/waveterm` | AI-native terminal with blocks and widgets | Terminal + AI UX | ✅ Apache-2.0 |
| `wez/wezterm` (+ `portable-pty` crate) | Terminal; PTY crate | **PTY management in Rust** | ✅ MIT |
| `alacritty/alacritty` | GPU terminal | Rendering reference | ✅ Apache-2.0 |
| `atuinsh/atuin` | Rust shell history with sync | Command history search | ✅ MIT |
| `tldr-pages/tldr` | Simplified command docs | Local data for "explain this command" | ✅ CC-BY-4.0 (data) |
| `apple/containerization` + `apple/container` | Linux containers as lightweight VMs on Apple Silicon (macOS 26) | **Sandbox for generated code** (no Docker Desktop) | ✅ Apache-2.0 |
| `activepieces/activepieces` | Open automation platform | Automation step and trigger model | ✅ MIT (community) |
| `huginn/huginn` | Agents that monitor and act | Watch-and-act patterns | ✅ MIT |
| `n8n-io/n8n` | Workflow automation | UX reference only | 🔶 Sustainable Use Licence |
| `windmill-labs/windmill` | Scripts → workflows → UIs | Script-to-app ideas | ⚠️ AGPL-3.0 |
| `CodeEditApp/CodeEdit` | Native macOS editor | Editor pane (see B) | ✅ MIT |
| `openai/codex`, `aaif-goose/goose`, `All-Hands-AI/OpenHands`, `Aider-AI/aider`, `sst/opencode` | (see E) | Coding agent | ✅ |

## K. George: finance and spreadsheets

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `ironcalc/IronCalc` | **Rust spreadsheet engine** (formulas, xlsx) | **George's sheet engine** | ✅ MIT/Apache |
| `tafia/calamine` | Read xlsx/xls/ods | Import | ✅ MIT |
| `jmcnamara/rust_xlsxwriter` | Write xlsx with formatting/charts | Export | ✅ MIT/Apache |
| `duckdb/duckdb` (+ `duckdb-rs`) | In-process analytics SQL | **"Ask your data"**: the LLM writes SQL, DuckDB computes | ✅ MIT |
| `pola-rs/polars` | DataFrames in Rust | Data cleaning and transforms | ✅ MIT |
| `grafana/augurs` | Rust time-series toolkit (ETS, MSTL, outliers) | **Forecasting** (deterministic) | ✅ MIT/Apache (check) |
| `facebook/prophet` | Forecasting (Python) | Method reference | ✅ MIT |
| `dream-num/univer` | Spreadsheet/doc web components | Sheet-like mini-apps | ✅ Apache-2.0 (check) |
| `actualbudget/actual` | Local-first envelope budgeting | Budget UX, rules, bank sync design | ✅ MIT |
| `firefly-iii/firefly-iii` | Self-hosted double-entry finance | Rules engine, categories | ⚠️ AGPL-3.0 |
| `maybe-finance/maybe` (→ fork `we-promise/sure`) | Net-worth tracker | Dashboard UX | ⚠️ AGPL-3.0 |
| `beancount/beancount` | Plain-text accounting | Ledger semantics | ⚠️ GPL-2.0 |
| `beancount/fava` | Web UI for Beancount | Reports UX | ✅ MIT |
| `simonmichael/hledger` | Plain-text accounting | Reports | ⚠️ GPL-3.0 |

## L. Conner: business, CRM, decks

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `twentyhq/twenty` | Open-source CRM | Data model, pipeline UX | ⚠️ AGPL-3.0 |
| `calcom/cal.com` | Scheduling infrastructure | Booking-link logic reference (Leo) | ⚠️ AGPL-3.0 |
| `makeplane/plane` | Project management | Projects/cycles UX | ⚠️ AGPL-3.0 |
| `documenso/documenso` | E-signature | Signing flow reference | ⚠️ AGPL-3.0 |
| `marp-team/marp` | Markdown → slides | **Outline-to-deck pipeline** | ✅ MIT |
| `slidevjs/slidev` | Developer slides | Layout system ideas | ✅ MIT |
| `hakimel/reveal.js` | HTML presentations | Web-rendered decks | ✅ MIT |
| `scanny/python-pptx` | PPTX generation (Python) | **Reference for writing OOXML .pptx directly** | ✅ MIT |
| `typst/typst` | (see I) | Proposals, quotes, one-pagers | ✅ Apache-2.0 |

## M. Robert: design and images

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `GraphiteEditor/Graphite` | Rust node-based vector/raster editor (pre-1.0) | **Procedural design engine ideas** | ✅ Apache-2.0 |
| `penpot/penpot` | Open-source design tool | Design-tool data model | ✅ MPL-2.0 |
| `excalidraw/excalidraw` | Hand-drawn whiteboard | Whiteboard mini-apps | ✅ MIT |
| `tldraw/tldraw` | Infinite canvas SDK | Reference | 🔶 tldraw licence (commercial key) |
| `linebender/vello` | GPU 2D renderer (Rust) | High-performance canvas later | ✅ MIT/Apache |
| `linebender/kurbo` | 2D curves | Vector maths | ✅ MIT/Apache |
| `linebender/resvg` | SVG renderer | SVG import/export/render | ✅ MIT/Apache |
| `danielgatis/rembg` | Background removal | Reference (Apple Vision subject-lifting is native and better) | ✅ MIT |
| `facebookresearch/sam2` | Segment Anything 2 | Click-to-select objects (high tier) | ✅ Apache-2.0 |
| `xinntao/Real-ESRGAN` | Image upscaling | Upscale (convert to Core ML) | ✅ BSD-3 |
| `lokesh/color-thief` | Palette extraction | Brand palette from images | ✅ MIT |
| `comfyanonymous/ComfyUI` | Node-based diffusion workflows | Power-user workflows via separate process | ⚠️ GPL-3.0 |
| `drawthingsai/draw-things-community` | Mac/iOS image generation app core | Native image-gen reference | ⚠️ (check) |
| `KDE/krita`, `GNOME/gimp` | Raster editors | Tool behaviour reference | ⚠️ GPL |
| `google/fonts` | Open fonts | Brand kits | ✅ OFL |

## N. Cole: video and audio

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `WyattBlue/auto-editor` | Automatic silence/dead-air cutting | **Silence removal logic** | ✅ Unlicense |
| `browser-use/video-use` | Transcript-driven editing (cut fillers, dead space) | **Text-based editing pipeline** | ✅ MIT |
| freecut (fork of video-use) | Same, with local Whisper | Local-first variant | ❓ |
| `motion-canvas/motion-canvas` | Code-driven animation | Motion templates (titles, lower thirds) | ✅ MIT |
| `remotion-dev/remotion` | React video rendering | Reference | 🔶 company licence above small-team size |
| `FFmpeg/FFmpeg` | Everything video | Conversions (prefer AVFoundation; LGPL build if bundled) | ⚠️ LGPL/GPL |
| `wulkano/Kap` | Screen recorder | Recorder UX | ✅ MIT |
| `CapSoftware/Cap` | Loom alternative (Rust + Tauri) | Recorder + share UX | ⚠️ AGPL-3.0 |
| `obsproject/obs-studio` | Streaming/recording | Capture pipeline reference | ⚠️ GPL-2.0 |
| `mifi/lossless-cut` | Lossless trimming | Fast cut UX | ⚠️ GPL-2.0 |
| `mltframework/shotcut`, `KDE/kdenlive`, `olive-editor/olive`, `OpenShot/openshot-qt` | Open NLEs | Timeline UX reference | ⚠️ GPL |
| `Rikorose/DeepFilterNet` | **Rust real-time noise suppression** | Audio clean-up | ✅ MIT/Apache |
| `facebookresearch/demucs` | Music/voice stem separation | Separate voice from music | ✅ MIT |
| `pyannote/pyannote-audio` | Speaker diarisation | Reference (use SpeakerKit natively) | ✅ MIT |
| `m-bain/whisperX` | Word-level timestamps alignment | Precise transcript cuts | ✅ BSD-2 |

## O. Harris: learning

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| `ankitects/anki` | Spaced-repetition flashcards (Rust core + UI) | Card model, scheduling UX | ⚠️ AGPL-3.0 |
| `open-spaced-repetition/fsrs-rs` | **FSRS scheduler in Rust** | Card scheduling | ❓ (check; ecosystem is permissive) |
| `open-spaced-repetition/ts-fsrs` | FSRS in TypeScript | Reference / mini-apps | ✅ MIT |
| `readium/swift-toolkit` | EPUB/PDF reading toolkit for Swift | **Reader for books** | ✅ BSD-3 |
| `koodo-reader/koodo-reader`, `readest/readest` | Ebook readers | Reader UX | ⚠️ AGPL-3.0 |
| `argosopentech/argos-translate` | Offline translation | Fallback where Apple Translation lacks a language | ✅ MIT (check) |
| `LibreTranslate/LibreTranslate` | Translation API | Reference | ⚠️ AGPL-3.0 |

## P. Leo: calendar, meetings, tasks

| Repo | What it is | Use for | Licence |
|---|---|---|---|
| Hyprnote (`fastrepl/hyprnote`, check) | Local-first AI meeting notepad | **Meeting notes UX** | ❓ |
| Meetily (`Zackriya-Solutions/meeting-minutes`, check) | Local meeting transcription and summaries | Local pipeline reference | ❓ |
| `johannesjo/super-productivity` | Tasks + time tracking + calendar | Day planning UX | ✅ MIT |
| `go-vikunja/vikunja` | Task manager | Task model | ⚠️ AGPL-3.0 |
| `zslayton/cron` | Cron parsing (Rust) | Schedules | ✅ MIT/Apache |
| `fmeringdal/rust-rrule` | iCal recurrence rules | Recurring tasks/events | ✅ MIT/Apache |
| `chronotope/chrono-tz` | Time zones | Scheduling across zones | ✅ MIT/Apache |
| `aurelio-labs/semantic-router` | (see E) | Routing | ✅ MIT |

---

## Rules for using open source in 11am

1. **Add `cargo deny` and a Swift licence check to CI** with an allow-list: MIT, Apache-2.0, BSD-2/3, ISC, Zlib, Unlicense, BSL-1.0, MPL-2.0, CC0. Anything else fails the build.
2. **Keep `THIRD_PARTY_NOTICES.md`** generated from dependencies (`cargo about` for Rust; a script for SwiftPM). Show it in Settings › About.
3. **Studying GPL code is fine; copying it isn't.** When you learn from a GPL project, write your implementation from your own understanding.
4. **Models have licences too:** Qwen (Apache-2.0 for most sizes), Gemma (Gemma terms, check the current version), Kimi (modified MIT with attribution for very large commercial deployments, check), FLUX variants (some are non-commercial). Record each model's licence in the registry and show it in the Model manager.
5. **Data sources** (filter lists, dictionaries, sentence corpora) carry licences. Track them in `THIRD_PARTY_NOTICES` as well.
