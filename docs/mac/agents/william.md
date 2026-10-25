# william: writing and voice

> **The one-liner:** William writes like you, so you only review. Drafts, documents and rewrites in your authentic voice, anywhere on your Mac.
> **Package:** Add-on · **Monogram:** `wm` · **App name:** *William*

## Role in the team
William is the voice. He learns how you write from what you've actually written (sent mail, documents, posts), applies it consistently, and flags when something drifts into generic AI-speak. Every other agent that produces words (Marc's replies, Conner's proposals, Cole's scripts, George's investor updates) borrows William's voice profile.

## Replaces / enhances
Word, Pages, Google Docs (for personal and solo documents); Grammarly; Jasper/Copy.ai; Apple Writing Tools (William adds *your* voice and memory); LinkedIn/X post drafting; translation tools (translate in your voice).

## Use cases
1. **Rewrite anywhere:** select text in any app → ⌃⌥W → "shorter / warmer / clearer / in my voice / translate" → replaced in place (or copied).
2. **Draft from a brief:** "LinkedIn post about closing our first enterprise customer, humble, no emojis". Three variants in your voice, each with a "sounds like you" score.
3. **Long-form documents:** outline → sections → full draft, with James's citations and Bolton's context, all in suggestion mode so you accept piece by piece.
4. **Proposals and one-pagers** from templates (with Conner's structure and George's numbers), exported as a beautiful PDF (Typst) or .docx.
5. **Voice drift detection:** "This paragraph doesn't sound like you. It's 3× more formal than your usual and uses 'leverage'."
6. **Brand voice vs personal voice:** your company voice (shared with Robert's brand kit) and your personal voice as separate profiles.
7. **Talk to write:** dictate rambling thoughts (WhisperKit) → William turns them into a structured draft.
8. **Investor update:** monthly, using George's numbers and Conner's narrative, in your voice, sent via Marc.

## Features

### v1 (MVP)
- **Editor:** native TextKit 2, Markdown-backed storage with rich rendering (headings, lists, quotes, tables, images, code); focus mode; outline sidebar; word count and reading time.
- **Inline AI (⌘J / select):** continue, rewrite, shorten, expand, change tone, simplify, fix grammar, "in my voice", translate.
- **Suggestion mode:** AI changes appear as tracked suggestions (accept ⏎ / reject ⌫ per change or all).
- **Grammar and style:** **Harper** (Rust, local, instant) for grammar; **Vale-style rules** for your voice and brand rules ("never say 'delve'", "Oxford comma: yes").
- **Voice profile:** ingest sent mail (via Marc), documents (via Bolton), pasted samples, URLs of your posts; profile = style statistics + exemplar library for retrieval; "sounds like you" score.
- **Presets:** email, LinkedIn, X, blog, newsletter, SMS, formal letter, press release.
- **System-wide rewrite:** Services menu + global hotkey via Accessibility (read and replace the selection).
- **Export:** .docx (docx-rs), PDF (Typst themes from Robert), Markdown, HTML, copy as rich text.
- **Quick compose window** (⌃⌥N): a small floating editor for quick drafts.

### v2
- **Templates** (proposal, one-pager, PRD, press release, investor update) with fields filled from other agents.
- **Comments** on your own docs (notes to self, agent comments).
- **Citations** from James inserted as footnotes, with source chips.
- **Readability and style stats** (sentence length, passive voice, reading grade).
- **Talk to write** (dictation → structured draft).
- **Google Docs export/import** for collaborating with others.
- **iPhone keyboard extension:** "rewrite in my voice" in any iOS app (on-device where possible).

### Later
- **Personal voice adapter** (Tier C+, opt-in): LoRA fine-tune on your accepted and edited drafts with MLX, trained overnight on charger.
- Publishing integrations (Ghost, WordPress; LinkedIn's API is restricted).
- Version history UI (snapshots already exist in the event log).

### Not building
- Page layout / desktop publishing (Robert + Typst themes cover export).
- Real-time multi-person co-editing (enormous effort; export to Google Docs/Word for collaboration).
- Screenwriting or novel-writing tool features.
- Plagiarism checking.

## How the AI is involved

| Feature | Task class | Autonomy | Trigger |
|---|---|---|---|
| Grammar | Harper (deterministic, no LLM) | L3 (underlines) | Typing |
| Style/brand rules | Vale-like rule engine (deterministic) | L3 | Typing |
| Inline rewrite | `draft.medium` (Apple FM for short selections on Tier A) | L0 → suggestion | Selection + command |
| Long-form drafting | `draft.medium` / `reason.large` for structure | Suggestion mode | Ask |
| Voice profile | Style features (code) + embeddings of exemplars | L3 | Ingestion, edits |
| "Sounds like you" score | Embedding similarity + style-feature distance (code) | — | On draft |
| Learning from edits | Diff original vs edited → exemplar pairs | L3 | Every accepted/edited draft |
| Translation | Apple Translation (on-device) + rewrite pass for voice | Suggestion | Command |

## Works with
- **Marc:** supplies drafts; William's profile powers every reply.
- **Conner:** proposals, pitch copy, narratives.
- **George:** numbers for updates (William never invents numbers; they come in as data).
- **James:** citations and source summaries.
- **Robert:** brand voice and export themes; copy for graphics.
- **Cole:** scripts and captions.
- **Bolton:** stores documents; supplies samples and context.

## Design and visual identity
- **Pattern:** ruled lines and a margin rule.
- **Motion:** text "inks in" (blur to sharp, line by line) when AI writes; suggestions slide in under strike-throughs.
- **Tone:** William's interface talks least of all the agents. The writing is the interface.

### Wireframe: editor
```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ wm  Pricing page copy · draft                         Preset: Web ▾   ◐  ⋯       │
├──────────────┬───────────────────────────────────────────────────┬───────────────┤
│ Outline      │                                                   │ william       │
│  Hero        │   Your team, on your Mac.                         │               │
│  Plans       │                                                   │ Sounds like   │
│  FAQ         │   Eleven apps that work for you: mail, files,     │ you ▓▓▓▓▓▓░ 86│
│              │   research, writing and more. They think on your  │               │
│ Docs         │   Mac, so your work stays yours.                  │ 2 suggestions │
│  Recent      │                                                   │ ─ "leverage"  │
│  Templates   │   Pick the specialists you need. ~~Leverage~~     │   → "use"     │
│  Voice       │   **Use** the whole team for less than one        │ ─ sentence 4  │
│              │   subscription you already pay for.               │   too long    │
│ + Tune…      │                                                   │               │
│              │                                                   │ Ask william…  │
├──────────────┴───────────────────────────────────────────────────┴───────────────┤
│ 312 words · 1 min · Harper: 0 issues · ● on-device                               │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Wireframe: rewrite anywhere (floating panel over any app)
```
╭─ wm rewrite ──────────────────────────────────────────╮
│ "hey just checking if u got my last email re invoice" │
│ ─────────────────────────────────────────────────────│
│ ▸ Hi Tom, just checking you received my last email    │
│   about the invoice. Happy to resend if not.          │
│ [Shorter] [Warmer] [Firmer] [Translate ▾]  ⏎ replace  │
╰──────────────────────────────────────────────────────╯
```

## Usability
- **Shortcuts:** ⌃⌥W rewrite selection (global) · ⌃⌥N quick compose · ⌘J inline ask · ⌘⇧E accept all suggestions · ⌘⇧R reject all · ⌘. focus mode.
- **Onboarding:** "Teach William your voice": connect sent mail (via Marc, if owned) or drop 5–10 documents/posts → profile built in minutes → show "your voice in 5 traits" (e.g. "short sentences, warm sign-offs, no exclamation marks, Australian spelling, uses dashes"), which you can edit.
- **Never silently replace:** rewrite-anywhere always shows the result first (⏎ to replace).
- **Empty state:** ruled-paper pattern; "Start typing, or tell William what you need."

## Notch and iPhone
- **Notch:** none by default. Rewrite is a hotkey, not a notch page (avoid clutter). "Draft ready" approvals appear via Leo's Approvals page.
- **iPhone:** quick drafts, approve rewrites, the keyboard extension (v2), dictation → draft.

## Mac integration
TextKit 2 (`NSTextView` with TextKit 2 / or STTextView if needed) · `NSServices` · Accessibility (`AXSelectedText`, `AXValue` to replace; fall back to the pasteboard with restore) · **Translation** framework · App Intents ("Rewrite with William", "Draft a post about…") · SwiftUI `DocumentGroup` (file-based docs; macOS 27 improves direct disk access) · Quick Look previews for `.md` · coexist with Apple **Writing Tools** (users can use both; William's value is your voice + memory).
**Permissions:** Accessibility (rewrite in place), optional.

## Backend
- **Rust `core/william`:** document model (Markdown + front matter + sidecar JSON for suggestions/comments), suggestion engine (diff/merge), voice profiles (style feature extractor: sentence length distribution, punctuation habits, vocabulary, formality, spelling locale; exemplar store with embeddings), "sounds like you" scorer, rule engine (Vale-style YAML rules), Harper integration (`harper-core`), exports (`docx-rs`, Typst with themes, HTML), edit-learning log.
- **Tables:** `docs(id, path, title, preset, voice_profile_id, updated_at)`, `suggestions(id, doc_id, range, original, replacement, reason, model, status)`, `voice_profiles(id, kind[personal|brand], traits_json, stats_json, updated_at)`, `exemplars(id, profile_id, text, source_ref, embedding)`, `edit_pairs(id, original, edited, context, ts)`, `style_rules(id, rule_yaml, enabled)`.
- **Swift:** editor, rewrite panel, Accessibility bridge, Services provider, Translation adapter.
- **Port from current repo:** `apps/william/src/lib/voice/{analyse, embeddings, profile-jobs}.ts`, `generation/*`, `ingestion/*`, types `voice-profile.ts`.

## Lower-end Macs
- **Tier A:** grammar/rules (Harper) fully local and instant; short rewrites via Apple FM; long drafts via cloud (consent) or "draft overnight".
- **Tier B:** local rewrites and medium drafts.
- **Tier C+:** everything local, including long-form; personal adapter training (later).

## Open source to study
`Automattic/harper` · `vale-cli/vale` · `typst/typst` · `bokuweb/docx-rs` · `krzyzanowskim/STTextView` (licence check) · `ueberdosis/tiptap` / `facebook/lexical` / `TypeCellOS/BlockNote` (for web mini-app editors) · `languagetool-org/languagetool` (LGPL, separate service only) · `ml-explore/mlx-lm` (LoRA, later).

## Tunable by Johnny
Presets, templates, banned words, style rules, sign-offs, voice traits, export themes, which agents may use the personal vs brand voice.

## Risks and open questions
- **Rewrite-in-place reliability** varies by app (some apps don't expose AX text). Fall back to copy/paste with clipboard restore, and tell the user.
- **Voice quality with little data.** Ask for 10+ samples; show traits so users can correct them.
- **Apple Writing Tools overlap:** position William on *your* voice + memory + cross-agent context.
- **Open question:** Markdown as the storage format limits some Word features (complex tables, page layout). Accept that; Typst/docx export covers output.

## Build checklist
- [ ] Editor (TextKit 2) + Markdown model + outline + focus mode
- [ ] Inline AI commands + suggestion mode
- [ ] Harper grammar + rule engine
- [ ] Voice profile ingestion (mail, docs, paste, URL) + traits UI + score
- [ ] Rewrite-anywhere (Services + hotkey + AX replace + fallback)
- [ ] Quick compose window
- [ ] Exports: docx, PDF (Typst), md, HTML
- [ ] Edit-learning loop
- [ ] Integration: Marc drafts use the profile
- [ ] v2: templates, comments, citations, stats, dictation, Google Docs, iOS keyboard
