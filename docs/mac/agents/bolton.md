# bolton: memory, files, knowledge

> **The one-liner:** Bolton remembers everything worth remembering and finds anything you've ever seen, written, saved or been sent, with the source.
> **Package:** Core · **Monogram:** `bn` · **App name:** *Bolton*

## Role in the team
Bolton is the shared memory and the librarian. Every agent reads context from Bolton and writes what's worth keeping through Bolton's curator. For you, Bolton is the file browser, the notes app, the search engine for your life's work, and the place to inspect (and edit or forget) everything 11am knows.

## Replaces / enhances
Finder (finding and organising, not system operations), Spotlight (semantic search over content), Apple Notes / Obsidian / Notion (personal knowledge), Preview (viewing, reading, asking PDFs), clipboard managers and shelf apps (Maccy, Yoink, Dropover), the Downloads-folder mess.

## Use cases
1. **"Find the contract I signed with Acme last year."** Hybrid search: entities (Acme) + type (contract) + time + content, ranked, with a preview and a "why this result".
2. **"What did we decide about pricing?"** The decisions log, with the meeting, email or note each decision came from.
3. **Drop anything on the notch.** A receipt goes to George, a contract has its terms extracted, a business card becomes a Marc contact, an article goes to James's reading list. Bolton files the original.
4. **Tidy:** "clean up my Downloads". Bolton proposes moves and renames grouped by project/type, previews them, applies on approval, and keeps a full undo journal.
5. **Project spaces:** one place for everything about "Supplier switch": files, notes, emails (Marc), decisions, research (James), numbers (George).
6. **Notes that link themselves:** write a note and Bolton suggests links to people, projects and earlier notes, and extracts tasks for Leo.
7. **Memory inspector:** "What does 11am know about Sarah?" View, correct or forget any fact, with its source. This is the core of trust.
8. **Ask a document:** open a 60-page PDF and ask "what are the termination clauses?" The answer comes back with page references.

## Features

### v1 (MVP)
- **Indexer:** user-chosen folders (default: Documents, Desktop, Downloads, iCloud Drive's 11am folder); FSEvents incremental; extraction: PDF (PDFKit), images/scans (Vision OCR), docx/xlsx/pptx (Rust parsers / MarkItDown-style), Markdown/text/code, email and attachments via Marc; chunking; local embeddings.
- **Search:** one big search field ("What are you looking for?") with hybrid retrieval (FTS5 + sqlite-vec + metadata filters + entity matching + reranking); natural-language filters ("pdfs from last March over 5 MB"); `NSMetadataQuery` for name/kind/date queries (reuses Spotlight's index for free).
- **File browser:** list, columns, gallery; Quick Look; Finder tags (read and write, interoperable with Finder); "Reveal in Finder"; basic file ops (rename, move, new folder) with an undo journal.
- **About this file** (agent pane): summary, key facts (dates, parties, amounts), related items, where it came from (`kMDItemWhereFroms` download URL, the email it arrived in), ask box.
- **Notes:** Markdown files on disk (`~/11am/Notes`), backlinks, quick note (⌥N from anywhere), daily note (optional).
- **Memory:** entities (people, orgs, projects, places, products), memories (facts, preferences, decisions, instructions) with provenance, confidence, validity windows and supersedes links; **curator** decides what to keep and detects conflicts.
- **Memory inspector:** browse by entity, edit, forget (with cascade), export.
- **Context packs API:** given a task + entities + a token budget, return the best memories and sources.
- **Shelf:** notch drop zone + clipboard history (text, images, files), pin items, drop onto an agent.

### v2
- **Tidy rules:** natural-language rules ("invoices → Finance/2026/Invoices, rename to vendor-date-amount") running automatically at L2, with undo.
- **Projects** (cross-agent spaces).
- **Smart folders:** saved natural-language queries.
- **PDF reading tools:** highlights, annotations, Q&A with page refs, summaries.
- **Web clips** from James (readable copies with source URL).
- **Screenshot index:** OCR every screenshot for search.
- **Duplicates and big files** clean-up (preview + approval).
- **Knowledge graph view** (entities and links), kept simple and useful, not a hairball.

### Later
- **Screen memory (opt-in, Tier D+):** screenpipe-style continuous capture, local only, with aggressive exclusions (password fields, private apps) and retention limits.
- Cloud drives via API (Google Drive, Dropbox) for files not synced locally (most users already have them on disk via File Provider, which works without any API).
- Shared spaces with an assistant (export/import packs).

### Not building
- Finder's system role (ejecting disks, permissions editor, Trash management, network shares admin).
- A cloud storage service.
- A Notion-style database builder (Johnny's specs cover custom views).
- File version control.

## How the AI is involved

| Feature | Task class | Autonomy | Trigger |
|---|---|---|---|
| Text extraction | Vision OCR, parsers (no LLM) | L3 | File added/changed |
| Key facts and summaries | `extract.small` / `summarise.medium` | L3 | After extraction (queued, power-aware) |
| Embeddings | `embed` (always local) | L3 | After chunking |
| Query understanding | `classify.small` (filters, entities, intent) | — | Each search |
| Answer synthesis | `summarise.medium` with citations | — | "Ask" queries |
| Memory curation | `classify.small` (worth keeping? supersedes? conflicts?) | L2 | Agent writes |
| Auto-linking notes | embeddings + `extract.small` | L0 (suggest) | While writing |
| Tidy proposals | rules + `classify.small` for naming/grouping; **file ops are code** | L1 (first time), L2 once a rule exists | Ask / rules |

Rule: **Bolton never moves or deletes a file without either your approval or a rule you created.** Every operation goes in the move journal and can be undone.

## Works with
- **Gets:** people and threads (Marc), voice samples and docs (William), sources and reports (James), financial facts (George), decisions (Leo meetings, Conner), assets (Robert), transcripts (Cole), cards/highlights (Harris), specs and skills (Johnny).
- **Gives:** context packs to everyone; attachments to the right agents; deadlines found in documents to Leo.

## Design and visual identity
- **Pattern:** stacked horizontal strata (archive layers).
- **Motion:** thin cards slide and stack when filing; search results settle in from the top.
- **Tone:** precise and source-first. "Found in ✉ Acme <legal@acme.com>, 14 Mar 2025 · page 3."

### Wireframe: search home
```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ bn  bolton                                                               ◐  ⋯   │
├────────────────┬─────────────────────────────────────────────────────────────────┤
│ Search         │                                                                 │
│ Recent         │           What are you looking for?                             │
│ Notes          │   ╭─────────────────────────────────────────────────────────╮   │
│ Projects    3  │   │ acme contract signed last year                        ⏎ │   │
│ Locations      │   ╰─────────────────────────────────────────────────────────╯   │
│  Documents     │   filters: org = Acme · kind = contract · 2025                  │
│  Downloads     │                                                                 │
│  iCloud/11am   │   ▤ Acme_MSA_signed.pdf        Contract · 14 Mar 2025   0.94   │
│ Smart folders  │     "…term of 24 months commencing…"  ✉ legal@acme.com          │
│  Receipts 26   │   ▤ Acme_SOW_v3.docx           Draft · 2 Mar 2025       0.71   │
│ Memory         │   ✉ Re: MSA signature           Email · 13 Mar 2025      0.66   │
│  People        │                                                                 │
│  Decisions     │   Answer ▸ The MSA was signed 14 Mar 2025, 24-month term,       │
│ Shelf       4  │   auto-renews unless 60 days' notice [1]. Renewal: 14 Mar 2027. │
│ + Tune…        │   → add renewal reminder to leo                                 │
├────────────────┴─────────────────────────────────────────────────────────────────┤
│ ⌘K · ⌘J ask bolton · indexed 48,211 items · ● on-device                          │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Wireframe: memory inspector
```
╭─ what 11am knows about · Sarah Lee ───────────────────────────────────────╮
│ Person · Partner at Northfield Ventures (✉ signature, 12 Oct)        edit │
│ ─ facts ─────────────────────────────────────────────────────────────────│
│ prefers short emails, no attachments >5MB          from: marc · 4 threads │
│ wants 3 months of >10% MoM before term sheet       from: note · 3 Sep  ✎ ✕│
│ ─ decisions involving ───────────────────────────────────────────────────│
│ "raise at A$X cap" · 28 Oct · meeting transcript                          │
│ ─ conflicts ─────────────────────────────────────────────────────────────│
│ title: "Partner" (Oct) vs "Principal" (Jun) → newer kept · resolve ▸      │
╰──────────────────────────────────────────── forget everything about ✕ ───╯
```

## Usability
- **Shortcuts:** ⌘F search · ⌥N quick note (global) · Space Quick Look · ⌘I about this file · ⌘⌫ move to Trash (with undo) · ⌘⇧T tidy.
- **Onboarding:** pick folders (explain exactly what's read, what stays local, how to exclude) → initial index with an honest ETA ("about 25 min on battery, 8 min plugged in") → first search suggestion based on what was found.
- **Exclusions:** per-folder and per-pattern; secrets (`.env`, keychains, password exports) excluded by default.
- **Empty state:** strata pattern; "Point Bolton at a folder and ask it anything."
- **Trust:** results show *why* (matched entity, date, phrase); the memory inspector is one click from any agent output.

## Notch and iPhone
- **Notch:** the Shelf page (drop → choose agent, or auto-route); "Filed 3 items" toasts.
- **iPhone:** Capture tab (VisionKit document scanner, photo, voice note → transcribed note, share sheet), search everything (metadata + extracted text synced; full files on demand), notes read/edit, memory inspector.

## Mac integration
FSEvents (`notify` crate) · `NSMetadataQuery` (Spotlight index, `kMDItemWhereFroms`) · Finder tags (xattr `com.apple.metadata:_kMDItemUserTags`) · Quick Look (`QLPreviewPanel`, Quick Look thumbnails) · **Finder Sync extension** (context menu "Ask Bolton", badges) · Share extension · Core Spotlight (index notes and memories for system Spotlight) · Vision OCR · PDFKit · App Intents ("Find in Bolton", "Save to Bolton"; macOS 27 entity schemas) · Services ("Save selection to Bolton") · `NSPasteboard` change count polling for clipboard history (cheap timer, paused when idle).
**Permissions:** folder access (per folder) or Full Disk Access (optional, for whole-disk indexing).

## Backend
- **Rust `core/bolton`:** discovery (walk + FSEvents), extraction pipeline (priority queue, power-aware), chunker, embedder (via brain), hybrid search (FTS5 BM25 + vector cosine + metadata + recency + entity boosts → reciprocal rank fusion → optional small reranker), curator (keep/skip/merge/supersede/conflict), context packs, move journal.
- **Tables:** `documents`, `chunks` (+ `chunks_fts`, `chunks_vec`), `entities`, `entity_edges`, `memories`, `decisions`, `conflicts`, `notes(id, path, title, links_json)`, `shelf(id, kind, blob_ref, created_at, pinned)`, `file_ops(id, op, from, to, ts, undone)`, `tidy_rules(id, rule_text, compiled_json, enabled)`.
- **Swift:** file browser UI, Quick Look, Finder Sync extension, Vision OCR provider, PDFKit provider, `NSMetadataQuery` provider, shelf UI.
- **Port from current repo:** `apps/bolton/src/lib/{memory/capture.ts, decisions, entities, search, summaries}` and the schema (memory_entries → memories; entities; entity_relationships → entity_edges; decisions; conflicts).

## Lower-end Macs
- **Tier A:** index chosen folders only; OCR and embeddings only on AC power or idle; small (384-d) embeddings; summaries on demand rather than for every file; answer synthesis via Apple FM (short) or cloud (opt-in); lean on `NSMetadataQuery`.
- **Tier B:** background summaries for documents < 20 pages; full search features.
- **Tier C+:** everything, including whole-library summaries and the graph view; screen memory on Tier D+.

## Open source to study
`spacedriveapp/spacedrive` (indexing architecture, AGPL: study only) · `sxyazi/yazi` (async previews) · `p0deje/Maccy` (clipboard) · `paperless-ngx/paperless-ngx` (auto-matching rules, GPL: study) · `getzep/graphiti` (temporal facts) · `mem0ai/mem0` (memory curation) · `asg017/sqlite-vec` · `microsoft/markitdown` · `docling-project/docling` · `Mintplex-Labs/anything-llm` · `khoj-ai/khoj` (AGPL: study) · `screenpipe/screenpipe` (later).

## Tunable by Johnny
Tidy rules; which folders and file types; custom views ("Receipts board", "Contracts expiring in 90 days"); custom fields on entities; memory retention policies ("forget meeting transcripts after 1 year, keep summaries"); note templates.

## Risks and open questions
- **Indexing cost on battery.** Strict power policy plus honest ETAs.
- **Wrong answers from documents.** Always cite with page/quote; "I couldn't find that" is better than guessing.
- **Privacy.** Default exclusions for secrets; Full Disk Access optional and explained.
- **Open question:** store notes inside the app library or a visible folder? Recommendation: a visible `~/11am/Notes` folder (user ownership, iCloud/Time Machine backup, Obsidian-compatible).

## Build checklist
- [ ] Folder picker + permissions + exclusions
- [ ] Discovery + FSEvents incremental
- [ ] Extraction pipeline (PDFKit, Vision, docx/xlsx/pptx, md/txt)
- [ ] Chunk + embed + FTS5 + sqlite-vec
- [ ] Hybrid search + query understanding + NSMetadataQuery path + retrieval eval
- [ ] File browser UI + Quick Look + tags + move journal
- [ ] About-this-file pane + ask
- [ ] Notes (Markdown on disk, backlinks, quick note)
- [ ] Entities/memories/decisions + curator + memory inspector
- [ ] Context packs API (used by Leo first)
- [ ] Shelf + clipboard history + notch page
- [ ] v2: tidy rules, projects, smart folders, PDF tools, clips, screenshot OCR, duplicates
