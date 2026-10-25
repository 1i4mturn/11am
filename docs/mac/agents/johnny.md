# johnny: build, terminal, Tune, automations

> **The one-liner:** Johnny makes the software fit you. Describe the change and he builds it, whether that's a view, an automation, a mini-app or a script, safely and reversibly.
> **Package:** Add-on (**Tune-lite is in Core**) · **Monogram:** `jo` · **App name:** *Johnny*

## Role in the team
Johnny is the builder. For everyone, he's the engine behind **Tune**: change any 11am app in plain English. For power users, he's a terminal with a brain, an automation builder, a mini-app studio, a model manager and a coding agent. He's the one agent that edits the other agents' surfaces, through specs and never through their code (see [malleable apps](../02-architecture.md#malleable-apps-how-johnny-edits-apps)).

## Replaces / enhances
Terminal, iTerm2, Warp; Shortcuts/Automator; Zapier/Make (personal automations); small internal-tool builders (Retool-lite, Airtable interfaces); Activity Monitor and CleanMyMac (light "Mac health"); and settings sprawl in every app.

## Use cases
1. **Tune (any user):** in Marc, *"Add a column for when I last replied, and a view of just investors."* Johnny shows a spec diff and live preview, you apply it, and you can undo it any time.
2. **Automation:** *"Every Friday at 4pm, export George's P&L as a PDF and email it to my accountant."* Johnny builds trigger → steps → approval on the send, and schedules it with Leo.
3. **Mini-app:** *"I need a tracker for my kombucha batches: start date, pH readings, a chart."* Johnny generates a small app that lives in Bolton's sidebar, styled like 11am, storing data in the core.
4. **Terminal with a brain:** *"find all PDFs over 50 MB in Downloads and move them to the external drive"* becomes a command shown with a dry run, run after confirmation, and recorded in history. Errors get an "explain" and a "fix it".
5. **Connect a new service:** *"Connect to our Shopify store"*. Johnny reads the API docs (via James), generates a connector (an MCP server definition + auth) for your approval, and the other agents can use it.
6. **Coding agent (developers):** run tasks on a repo in a sandbox, run tests, open PRs to GitHub. This is the existing `packages/jobs` Johnny, ported.
7. **Mac health:** "why is my Mac slow?" explains memory pressure, the heavy process, the full disk and login items, with fixes you approve.
8. **Model manager:** download, benchmark and switch local models, and add a custom endpoint (e.g. your home Mac Studio running Kimi via exo).

## Features

### v1 (MVP)
- **Tune** (Core, in every app's sidebar and Ask bar): natural language → validated spec diff → side-by-side preview → apply → version history → revert; "try for 7 days"; safe mode.
- **Spec studio** (Johnny app): browse each agent's spec, history, diffs, authors; edit manually (JSON with schema autocomplete) for power users.
- **Terminal:** libghostty (or SwiftTerm) tabs and splits; **AI command bar** (natural language → command with explanation, dry-run where possible); explain output; fix the last error; command safety classifier; history search.
- **Automations:** triggers (time, app events, file events, email events, calendar events, webhooks later), steps (any tool, agent asks, conditions, loops over items, approvals), run history with logs, retries, enable/disable.
- **Mini-apps:** generated HTML/JS (with 11am CSS tokens and web components), running in a sandboxed WKWebView with a capability bridge; permissions prompt at install; place in any agent's sidebar or the notch.
- **Model manager** (shared with Settings): recommended models, downloads, benchmarks, custom providers.
- **Sandbox:** Seatbelt profiles for scripts and commands Johnny generates (no network or home directory unless granted).

### v2
- **Coding agent:** repo tasks (local or GitHub), plan → edit → test in sandbox (Apple Containerization VMs) → diff review → commit/PR; budgets; job monitor (port `packages/jobs`).
- **Connector generator:** OpenAPI/docs → MCP server definition + OAuth/API key flow → tested against the live API in a sandbox → registered.
- **Scripts:** JS (JavaScriptCore) or WASM custom tools with typed inputs/outputs.
- **Mac health:** CPU/memory/disk/battery/thermal, login items, big caches, with explanations and approved fixes.
- **Shortcuts bridge:** run and create Apple Shortcuts (`shortcuts` CLI / App Intents) from automations.
- **Template gallery:** install specs, automations and mini-apps made by you (and later the community). **This is where cute ideas live.**

### Later
- Community gallery with sharing and reviews.
- Developer mode: Johnny edits a local checkout of 11am's own source and builds it (for you and technical founders only).
- Webhook triggers via a relay (needs the tiny backend).

### Not building
- A full IDE (open in Xcode/VS Code/Zed with one click).
- CI/CD or hosting platform.
- A team automation platform (Zapier for companies).
- Anything that lets specs or automations raise their own autonomy level.

## How the AI is involved

| Feature | Task class | Autonomy | Trigger |
|---|---|---|---|
| Spec diffs (Tune) | `code.large` with JSON Schema-constrained output; validator rejects invalid diffs | **L1** (preview + apply) | Ask |
| Automation building | `code.large` → automation JSON; dry-run simulation | **L1** | Ask |
| Mini-app generation | `code.large` (HTML/JS), static checks (CSP, no remote code) | **L1** (install prompt) | Ask |
| Command generation | `code.large`/`classify.small`; **safety classifier = deterministic denylist + model** | **L1** for anything not on the allowlist | Ask |
| Explain/fix errors | `summarise.medium` | L0 | Command fails |
| Coding agent | `code.large` (local coder or cloud) | L1 per diff / PR | Ask |
| Connector generation | `code.large` + James docs | L1 | Ask |
| Mac health | Metrics (code) + `summarise.medium` | L0 → L1 for fixes | Ask / alerts |

**Command safety rules:** always confirm `rm -rf`, `sudo`, `curl … | sh`, writes outside the working folder, network uploads, `defaults write` to system domains, `launchctl`, disk utilities. Never run commands sourced from emails or web pages without showing them. Budgets per job (port `budget.ts` and its tests).

## Works with
- **Every agent:** Johnny edits their specs (views, fields, automations, instructions).
- **Leo:** schedules automations; Johnny's runs show in briefs.
- **Robert:** design tokens and component styling for mini-apps.
- **James:** API docs and research for connectors.
- **Bolton:** stores skills, specs, scripts, run logs.

## Design and visual identity
- **Pattern:** bracket corners `⌜ ⌟` and faint scanlines.
- **Motion:** block cursor blinks, then fills progress blocks `▓▓▓░░`.
- **Terminal theme:** monochrome by default (black glass, white text). ANSI colours map to greyscale weights, with a "signal colours" option, because red errors carry meaning in terminals.
- **Tone:** direct and technical, but always explains what it'll do before doing it.

### Wireframe: Tune in another app (Marc)
```
╭─ Tune marc ───────────────────────────────────────────────────────────────╮
│ "add a column showing when I last replied, and a view of just investors"  │
│ ───────────────────────────────────────────────────────────────────────── │
│ johnny will:                                                              │
│  + add field  "Last replied" (from sent mail, per thread)                 │
│  + add view   "Investors" = people where tag:investor, sorted by last     │
│                contact                                                    │
│ ─ preview ─────────────────────────────────── before │ after ────────────│
│  Needs you 4                                         │ Needs you 4        │
│  FYI 12                                              │ FYI 12             │
│                                                      │ Investors 7   new  │
│ [Apply] [Try for 7 days] [Edit spec] [Cancel]     ● on-device · qwen3.6   │
╰───────────────────────────────────────────────────────────────────────────╯
```

### Wireframe: Johnny app (terminal + automations)
```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ jo  johnny                                            ⌕ Ask johnny…      ◐  ⋯   │
├───────────────┬──────────────────────────────────────────────────┬───────────────┤
│ Terminal      │ ~/Downloads ❯ ⌘K "pdfs over 50MB → /Volumes/Ext" │ johnny        │
│  zsh · 1      │ ┌ proposed ───────────────────────────────────┐  │               │
│  zsh · 2      │ │ find . -name '*.pdf' -size +50M \           │  │ 6 files,      │
│ Automations 4 │ │   -exec mv -n {} /Volumes/Ext/ \;           │  │ 1.8 GB.       │
│  Fri P&L ✓    │ │ dry run: 6 files · 1.8 GB · no overwrites   │  │ -n prevents   │
│  Receipts ✓   │ │ [Run ⏎]  [Edit]  [Cancel]                   │  │ overwriting.  │
│ Mini-apps   2 │ └─────────────────────────────────────────────┘  │               │
│  Kombucha     │                                                  │ ─ runs ─      │
│ Specs         │                                                  │ Fri P&L  ✓ 4m │
│ Models        │                                                  │ Receipts ✓ 2h │
│ Mac health    │                                                  │               │
│ + New…        │                                                  │               │
├───────────────┴──────────────────────────────────────────────────┴───────────────┤
│ ⌘K command · ⌘J ask johnny · sandbox: seatbelt · ● on-device                     │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Usability
- **Shortcuts:** ⌘K in terminal for the AI command bar · ⌘E explain selection · ⌘⇧F fix last error · ⌘T new terminal tab · ⌘D split.
- **Tune is everywhere** ("+ Tune…" at the bottom of every sidebar; "tune:" prefix in any Ask bar).
- **Every change has a plain-English summary first**, then the technical diff for those who want it.
- **Rollback is never more than two clicks away** (history per agent; safe mode at launch).
- **Empty state:** brackets pattern; "Tell Johnny what you wish this app did."

## Notch and iPhone
- **Notch:** automation and build progress; approvals for commands and runs; "Automation failed: fix?" peek.
- **iPhone:** approve runs, trigger automations manually, view run history and failures, approve spec changes made on the Mac.

## Mac integration
libghostty (C API, Metal rendering) or SwiftTerm · PTY (`portable-pty`) · Seatbelt sandbox profiles (as Codex CLI uses on macOS) · **Apple Containerization** (Linux micro-VMs, macOS 26) · JavaScriptCore · WKWebView (mini-apps, `WKScriptMessageHandlerWithReply` for the capability bridge) · `shortcuts` CLI + App Intents · gitoxide (spec versions) · Keychain (connector secrets) · IOKit/`host_statistics` and `ProcessInfo` (Mac health) · Accessibility (UI automation steps, used carefully).
**Permissions:** none by default; Accessibility/Automation only for automations that need them (prompted per automation).

## Backend
- **Rust `core/johnny` + `core/specs`:** spec schemas per agent (JSON Schema), validator, diff/patch, git-backed store (gix), try-mode timers, safe-mode loader; automation engine (trigger registry, step executor, conditions, idempotency keys, retries, run logs); mini-app registry (manifest, permissions, assets); command safety classifier; PTY manager; sandbox manager (Seatbelt profiles, Containerization jobs); connector generator (OpenAPI parsing → MCP tool defs); coding job runner (queue, budget, events, GitHub client: port of `packages/jobs`).
- **Tables:** `specs` (see core), `automations(id, name, trigger_json, steps_json, enabled, autonomy_cap)`, `automation_runs(id, automation_id, started, finished, status, log_ref)`, `miniapps(id, name, manifest_json, permissions, placement, version)`, `commands_history(id, cwd, text, generated, approved, exit_code, ts)`, `connectors(id, name, kind, spec_json, auth_ref)`.
- **Swift:** terminal views, Tune sheet (preview renders the real agent UI with the candidate spec), spec studio, mini-app host, model manager UI.
- **Port from current repo:** `packages/jobs/src/*` (queue, budget + tests, events, sandbox, github, push, checks), `apps/johnny/src/lib/{review, jobs}.ts`.

## Lower-end Macs
- **Tier A:** Tune with Apple FM/small models for simple changes (add a view or field); complex diffs, mini-apps and code via cloud (consent) or queued overnight; Seatbelt instead of VMs.
- **Tier B:** local Tune for most changes; mini-apps local but slower.
- **Tier C+:** local coding with Qwen 3.6 35B-A3B-class coders; Containerization sandboxes.

## Open source to study
`ghostty-org/ghostty` (libghostty) · `migueldeicaza/SwiftTerm` · `wavetermdev/waveterm` · `wez/wezterm` (`portable-pty`) · `atuinsh/atuin` · `openai/codex` (Seatbelt sandbox and approval modes) · `aaif-goose/goose` · `All-Hands-AI/OpenHands` · `Aider-AI/aider` · `sst/opencode` · `apple/containerization` · `activepieces/activepieces` · `huginn/huginn` · `Hammerspoon/hammerspoon` · `exelban/stats` · `GitoxideLabs/gitoxide` · `tldr-pages/tldr`.

## Tunable by Johnny (himself)
Command allowlist; sandbox defaults; terminal theme; automation notification rules; which agents' specs Tune may touch (all by default).

## Risks and open questions
- **Spec system scope creep:** start with a small vocabulary (views, fields, filters, actions, instructions) and grow it from real requests.
- **Bad automations** (loops, spam). Rate limits per automation, approval on external actions, and auto-disable after repeated failures.
- **Mini-app security:** strict CSP, no remote scripts, capability prompts, data scoped to the mini-app unless granted.
- **libghostty API stability** (not yet stable). Keep a SwiftTerm fallback.
- **Open question:** does Tune-lite in Core cannibalise the Johnny add-on? No: Tune edits existing apps, while Johnny adds new capabilities (terminal, automations, mini-apps, code).

## Build checklist
- [ ] Spec schema v1 for Leo, Bolton, Marc (views, fields, filters, actions, instructions)
- [ ] Spec renderer in each agent UI
- [ ] git-backed spec store + history + revert + safe mode + try mode
- [ ] Tune flow (ask → diff → preview → apply) + eval set
- [ ] Terminal (libghostty/SwiftTerm + PTY) + AI command bar + safety classifier
- [ ] Automations engine + builder + run history
- [ ] Mini-app host + capability bridge + permissions + gallery v0
- [ ] Model manager UI
- [ ] Seatbelt sandbox
- [ ] v2: coding agent (port `packages/jobs`), connector generator, scripts, Mac health, Shortcuts bridge, Containerization
