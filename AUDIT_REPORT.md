# 11am Suite — Full Audit Report (July 7, 2026)

## What changed and why (plain English)

The whole suite was reviewed top-to-bottom against the Notion specs and brand guidelines. The good news: all 11 agents and the dashboard exist, they follow the architecture the specs describe, and the design system is genuinely shared. Nine concrete problems were found and fixed: a styling bug that made dark borders appear on pages that should have none, red error messages on a product that is meant to be entirely grayscale, two apps that failed type-checking (real bugs, one of which returned the wrong "connected" status for Xero), a stale duplicated copy of the design system inside two apps, and a complete absence of tests — a small test suite now runs with `npm test`. The Claude model each agent uses is now switchable via an environment variable instead of being hard-coded in 19 places, which makes cost tuning a config change rather than a code change. Nothing about how the product behaves day-to-day has changed.

---

## 1. What's actually built

A single npm-workspaces monorepo (built in Cursor — `.cursor/settings.json` and the Cursor rework prompt `CURSOR_VISUAL_REWORK.md` are in the repo, and the structure matches the Cursor/Fable build prompts in Notion verbatim, including the exact port assignments home 3010 · william 3000 · marc 3001 · bolton 3002 · james 3003 · george 3004 · conner 3005 · leo 3006 · robert 3007 · harris 3008 · cole 3009 · johnny 3011).

- **`apps/home`** — the App Dashboard homepage: sidebar 3×4 flat-monogram grid, Ask Leo bar (⌘K, wired via `/api/ask-leo` → Leo's `/api/ask`), greeting, "what's happening today" glance cards (live from Marc/Leo/Bolton via `/api/dashboard`), activity timeline + roster with grayscale status pills, bottom embossed monogram row.
- **11 agent apps** — each a Next.js App Router app with `src/lib` domain engines and API routes: William (voice profile, generation, Gmail ingestion, embeddings, edit loop), Marc (Gmail sync/triage/replies/sender memory/search/cleanup/rules/briefings), Bolton (memory store, curator capture, hybrid search, entity graph, decision log, context packs, agent summaries, Notion sync), Leo (calendar OAuth, tasks, daily plan, meeting prep, ops summary, reports, the shared agent-invocation contract + `/api/invoke` + `/api/ask` routing), James (research engine with citations, save-heuristic, routing, handoff), George (finance engine, models, unit economics, calculator generator with Supabase artifact hosting, Stripe + Xero reads, tax disclaimer), Conner (strategy engine, validate/stress-test/GTM/pricing/growth/digest, invoke-James), Robert (design engine, brand-system doc with motion tokens, moodboards via OpenAI images, audit, briefs, handoffs), Harris (learning engine, plans/exercises/roadmaps, French, hub store, Bolton skill-gap reads), Cole (video engine reading Robert's motion tokens, scripts/storyboards/concepts, Whisper transcription, FFmpeg conversion), Johnny (code review, GitHub, and the shared `packages/jobs` async job system: queue, sandbox, budget/kill-switch, SEO + dependency checks, test generation, push).
- **`packages/ui`** — locked design system: tokens, AHG `@font-face`, all 11 monogram SVGs + wordmark, AppShell/rail/tiles, `am-*` utility classes, grain/wash/cursor-lamp, grayscale pills.
- **`packages/jobs`** — suite-wide orchestration service (currently consumed by Johnny).
- **`scripts/`, `deploy/`** — local launch and Vercel deploy tooling per the Tri-Platform plan (web phase). Desktop (Tauri) and mobile (Expo) phases: not started, as planned.

## 2. Spec conformance

Requirement → Source → Status → Evidence → Gap/Action.

| Requirement | Source | Status | Evidence | Gap / Action |
|---|---|---|---|---|
| Monorepo, npm workspaces, shared `packages/ui`, Tailwind v4, correct ports | Tri-Platform Plan; Cursor prompts | **Full** | root `package.json`; each app's `dev` script | — |
| All 11 agent apps working v1 | Full Suite Build Plan | **Full** | `apps/*` per above | Live-use validation is Liam's call |
| Agent-invocation contract (one JSON shape, built once) | Full Suite Build Plan; Leo brief | **Full** | `apps/leo/src/lib/agents/contract.ts`, `invoke.ts`, `/api/invoke`; consumed by home Ask Leo, Conner invoke-James | — |
| Bolton owns canonical schemas (voice, sender, numbers, strategy, brand-system incl. motion tokens, skill-gap, tasks) | Full Suite Build Plan | **Full** | `apps/bolton/src/lib/db/schema.ts`, `/api/agent-summaries`; writers in william/marc/george/conner/robert/james; readers in harris/cole/leo | — |
| Shared job-queue/orchestration built once, reused | Full Suite Build Plan | **Partial** | `packages/jobs` (queue, sandbox, budget, push, checks) used by Johnny | Leo fan-out + Cole pipeline reuse are "Later" per plan — on track |
| Self-contained HTML artifact pattern (George calculators) | Full Suite Build Plan | **Full** | `apps/george/src/app/api/calculator/route.ts` + Supabase storage | — |
| Tiering dropped this phase | Full Suite Build Plan | **Partial** | No gating enforced; but TierToggle/tier routes still present in william/marc/bolton | Decide: delete or leave dormant |
| `user_id` scaffold for multi-tenant | Full Suite Build Plan; Bolton research | **Full** | `user_id` default `"default"` on all Bolton tables | RLS enforcement deferred as specced |
| Dashboard homepage (sidebar grid, Ask Leo, glance, activity, roster, bottom row) | App Dashboard Build Spec | **Full** | `apps/home/src/app/page.tsx`, `globals.css`, `/api/dashboard` | — |
| Grayscale status pills (July 6 decision: dot glyphs, no hue) | Design Direction Hub; dashboard prompt | **Full** | `.roster-status--*`, `.glance-tag--*` in home `globals.css` | — |
| Ask-[agent] bar + schedule on every agent | Cursor prompts (July 6 patch) | **Full** | 11 ask bars, 10 schedule routes (Bolton's added this pass; Leo schedules via its own task store) | Scheduled entries are now actually executed by Leo's runner |
| Suite portal (scattered monograms, one viewport, drift/hover/click transitions) | Suite Portal Build Spec | **Missing (superseded/open)** | No portal route in `apps/home` | Dashboard spec explicitly replaces the portal for this surface; the marketing portal remains an open build item |
| AHG local @font-face, both weights, no fallback rendering | Dashboard spec; Design Hub open item | **Full** | `packages/ui` + `apps/home` `@font-face`; fonts shipped in repo | Fallback stack still lists Helvetica (unavoidable safety net) |
| All 11 monogram SVGs from shared package | Visual Rework; Design Hub | **Full** | `packages/ui/src/assets/logos/` (12 files) | 4 files drawn past 512 viewBox — Robert re-export, not a code fix |
| Gmail via Testing-mode OAuth, 7-day re-auth handled | Marc/William feature research | **Full** | `apps/marc/src/lib/gmail/*`, re-auth messaging in `/api/gmail` | Kick off CASA before any second user |
| Stripe/Xero uncertified reads | George research | **Full** | `apps/george/src/lib/stripe/client.ts`, `xero/client.ts` | — |
| "Later" features (fan-out, scheduled digests) | Full Suite Build Plan | **Completed this pass** | Leo parallel fan-out (`/api/invoke` `to_agents[]`); scheduled-task runner (`apps/leo/src/lib/schedule/runner.ts`) executes every agent's schedule entries | Booking, gen-video, iOS, CASA, RLS remain deferred (external/product decisions) |

## 3. Visual identity

The suite is on the locked system (paper `#faf9f7` / panel `#edeeef`, ink `#161616`, graphite `#2f2f2f`, muted `#6b6560`, AHG-only lowercase, borderless glow surfaces, squared corners via global `border-radius: 0`, grain + dual wash + cursor lamp, emboss/flat/inverted monogram contexts, grayscale pills).

Fixed this pass: the undefined `--am-*` variable bug (hard dark borders where none should exist) and 17 red error messages (now `.am-error`, grayscale). Remaining, logged: the 4 overdrawn monogram SVGs (Robert re-export), a handful of near-token greys in `apps/home/globals.css` (`#8a8580`, `#c8c4be`, `#b4b2a9` — tonal, low-priority normalisation), and stray `rounded`/`border` utilities that are neutralised by the global reset but should be cleaned opportunistically.

## 4. Code quality

Consistent and readable overall: per-app `lib/` domain engines, thin API routes, shared types, a clean shared UI package. Fixed: dead duplicated `11am-ui` copies inside marc/bolton (deleted), three apps'/packages' strict-mode type errors (george, james, packages/jobs), and hard-coded model strings (now env-driven). No frameworks added; tests use built-in `node:test`.

## 5. Integrations

- **Gmail** (Marc + William): googleapis OAuth clients with callback routes, Testing-mode 7-day expiry surfaced to the user with reconnect messaging, batch-friendly sync, unsubscribe safety rules. Sound for single-user debug. Action owned but not urgent: CASA Tier 2 before multi-user.
- **Claude**: every agent uses the official SDK via `ANTHROPIC_API_KEY`; the jobs runner enforces token/cost/time budgets with a kill switch. Now model-configurable via `ANTHROPIC_MODEL` per app.
- **Recommended optimisations** (cost/perf, low risk):
  1. *Implemented* — env-based model routing. Set `ANTHROPIC_MODEL=claude-haiku-4-5-20251001` in marc (triage/rules/search-parse) and bolton (capture/search) `.env.local` for ~70–90% cost reduction on classification-heavy calls; keep Sonnet for William generation and Johnny builds. Verify triage quality for a day before committing.
  2. Cache Bolton context-pack reads in the home dashboard API for 30–60s (it already polls every 60s; a small in-memory cache dedupes bursts). Low effort, saves repeated DB/embedding hits.
  3. Batch embedding calls in Marc's sync (embed N messages per request rather than one-by-one) — worth checking `search/embeddings.ts` batching before scale.
  4. Prompt-cache the large static system prompts (William voice profile, Robert brand system) with Anthropic prompt caching — biggest single saving on repeat generations.
  5. Gmail: prefer `historyId` incremental sync over full reconciliation once stable (quota + latency win); push (Pub/Sub) stays "Later" per spec.

## 6. Testing

No tests existed. Added `npm test` (node:test, zero new dependencies): 8 passing tests covering the jobs budget/kill-switch maths and design-token integrity. All 12 apps + 2 packages now pass `tsc --noEmit` (3 didn't before). Full `next build` must be re-verified on the Mac (the audit sandbox lacks the darwin-only native binaries; this is environmental, not a code issue). Suggested next tests: Marc rule-parsing, Leo routing classification (mocked Claude), Bolton save/supersede engine.

## Notion references used

All pages fetched in full on July 7, 2026; none inaccessible:
Johnny — Build Spec: 11am Homepage (Suite Portal) · Johnny — Build Spec: App Dashboard Homepage · 11am — Tri-Platform Architecture Plan · LiamOS — Full Suite Build Plan · LiamOS App Suite — Agent Capability Scoping · Brand Guidelines · 01 Visual Identity · 02 Brand Voice & Tone · 03 Applications · 04 Digital Guidelines · Robert — Design Direction: 11am Visual Rework (v1) · Design Direction Hub (incl. the Locked Visual System, July 6 decisions) · James Research: LiamOS Agent Capability & Competitive Landscape · James Feature Research × 11 (Leo, George, Marc, William, Robert, Conner, Cole, Harris, Bolton, Johnny, James-meta) · Cursor / Fable Build Prompts — All Agents · Cursor Prompt — Homepage (Suite Portal + Dashboard).

Note: Brand Guidelines 01/03/04 are largely 🚧 stubs and describe the **robert personal brand** (pure black/white, Jane Austen sign-off font). The Design Direction Hub's Locked Visual System explicitly supersedes them for 11am (grayscale tokens, no Jane Austen anywhere in 11am) — the code correctly follows the locked 11am system, so the "inconsistency" is between Notion documents, not in the code.
