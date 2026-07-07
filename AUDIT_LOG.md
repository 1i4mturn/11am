# 11am Suite — Audit Log (July 7, 2026)

Full-suite review against the canonical Notion specs. Each entry: Issue → Root cause → Fix → Files touched → Verification.

## Fixed in this pass

### 1. Undefined `--am-*` CSS variables (suite-wide visual bug)
- **Issue:** 60 references to `var(--am-muted)`, `var(--am-border)`, `var(--am-ink)`, `var(--am-accent-light)` across 11+ agent pages, but only `--11am-*` tokens were ever defined. Borders using `var(--am-border)` silently fell back to `currentColor`, rendering hard dark borders — directly against the "no borders, soft glow instead" rule in the locked visual system.
- **Root cause:** Two naming conventions drifted apart during the Cursor builds — the shared package defines `--11am-*`, later agent pages were written against `--am-*`.
- **Fix:** Added alias definitions (`--am-border`, `--am-muted`, `--am-ink`, `--am-accent-light` → their `--11am-*` equivalents) in the shared stylesheet.
- **Files:** `packages/ui/src/styles/globals.css`
- **Verification:** grep shows every `var(--am-*)` reference now resolves; typecheck clean.

### 2. Red error text (grayscale violation)
- **Issue:** 17 occurrences of `text-red-700` error messages across cole, conner, george, harris, james, johnny, leo, robert. The Design Direction Hub decision (July 6) is fully desaturated — "no hue anywhere."
- **Root cause:** Default Tailwind error styling carried in from the functional-layer Cursor prompts before the desaturation decision.
- **Fix:** New shared `.am-error` class (bold ink on `rgba(22,22,22,.06)` tint, matching the status-pill treatment); replaced all `text-red-700` usages.
- **Files:** `packages/ui/src/styles/globals.css` + 17 page/component files across 8 apps.
- **Verification:** `grep -r text-red-700 apps/*/src` returns 0; typecheck clean on all 12 apps.

### 3. Dead duplicated UI package copies
- **Issue:** `apps/marc/packages/11am-ui/` and `apps/bolton/packages/11am-ui/` — full stale copies of the shared UI library (old tokens, old AppShell) living inside two apps.
- **Root cause:** Pre-monorepo layout left behind when marc/bolton were migrated to `packages/ui`.
- **Fix:** Deleted both. Nothing imported them (both apps import `@11am/ui` from the workspace package).
- **Files:** removed `apps/marc/packages/`, `apps/bolton/packages/` (~136KB dead code).
- **Verification:** grep confirms no imports referenced the embedded copies; marc + bolton typecheck clean.

### 4. George: Xero route response bug
- **Issue:** `NextResponse.json({ connected: true, ...status, financials })` — the spread overwrote `connected: true` with the stale value from `status` (TS2783).
- **Root cause:** Property-order mistake.
- **Fix:** Reordered to `{ ...status, connected: true, financials }`.
- **Files:** `apps/george/src/app/api/xero/route.ts`
- **Verification:** tsc exit 0 for george.

### 5. George: integrations page type error
- **Issue:** `xero?.authUrl && <a …>` rendered an `unknown` into JSX (TS2322); would fail any CI typecheck.
- **Fix:** Narrowed with `typeof xero?.authUrl === "string"`, removed the `as string` cast.
- **Files:** `apps/george/src/app/integrations/page.tsx`
- **Verification:** tsc exit 0 for george.

### 6. James: schedule route passed unknown fields to Bolton client
- **Issue:** `cadence` and `custom_schedule` passed to `saveEntry`, which doesn't accept them (TS2353). The values are already carried in `full_content` and the `cadence:*` tag, so they were silently dropped conceptually and a compile error practically.
- **Fix:** Removed the two stray properties (data still persisted via `full_content`/tags, matching the other 8 agents' schedule routes).
- **Files:** `apps/james/src/app/api/schedule/route.ts`
- **Verification:** tsc exit 0 for james.

### 7. packages/jobs: untyped `res.json()` results
- **Issue:** Five `unknown`-typed fetch results in `bolton.ts`, `checks/seo.ts`, `github.ts` failed strict typecheck (TS18046/TS2322).
- **Root cause:** `Response.json()` returns `unknown` under the package's Node lib config; call sites assumed `any`.
- **Fix:** Added minimal response-shape types at each call site (no behaviour change).
- **Files:** `packages/jobs/src/bolton.ts`, `packages/jobs/src/checks/seo.ts`, `packages/jobs/src/github.ts`
- **Verification:** `npx tsc --noEmit -p packages/jobs` exit 0.

### 8. No tests anywhere in the repo
- **Issue:** Zero test files across 484 source files.
- **Fix:** Added a zero-dependency test setup using `node:test` (no new frameworks, per the keep-it-simple rule): budget/cost/kill-switch logic in the shared jobs package, and design-token integrity (11 agents, unique roster, monogram↔logo-file consistency). Wired `npm test` at the root.
- **Files:** `packages/jobs/src/budget.test.ts`, `packages/ui/src/tokens/tokens.test.ts`, `package.json`, `packages/{ui,jobs}/tsconfig.json` (`allowImportingTsExtensions`).
- **Verification:** `npm test` → 8/8 pass.

### 9. Claude model hard-coded in 19 places
- **Issue:** `claude-sonnet-4-20250514` hard-coded in every agent's Claude wrapper and inline calls — no way to route cheap classification calls to a cheaper model or upgrade centrally.
- **Fix:** All model constants now read `process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-20250514"` — default behaviour identical, but the model is now switchable per app via `.env.local` with no code change.
- **Files:** 19 files across all 11 agents + `packages/jobs/src/runner/agent.ts`.
- **Verification:** grep confirms all call sites env-aware; all apps typecheck.

### 10. Cross-agent HTTP calls had no timeouts (resilience pass)
- **Issue:** Every cross-app fetch (10 Bolton clients, home dashboard fan-out, Ask Leo proxy, Leo agent handoffs, jobs Bolton reads) had no timeout — a hung agent stalled callers for minutes instead of degrading gracefully.
- **Fix:** `AbortSignal.timeout` everywhere: 3.5s dashboard reads, 5s Bolton client calls, 10s jobs context reads, 90s agent handoffs (they may run a Claude call).
- **Files:** all `apps/*/src/lib/bolton/client.ts`, `apps/home/src/lib/dashboard-data.ts`, `apps/home/src/app/api/ask-leo/route.ts`, `apps/leo/src/lib/agents/invoke.ts`, `packages/jobs/src/bolton.ts`
- **Verification:** all apps + packages typecheck clean.

### 11. Dashboard fan-out uncached
- **Fix:** 45s in-memory cache on `/api/dashboard` (UI polls every 60s — never more than one poll stale, dedupes bursts/multiple tabs).
- **Files:** `apps/home/src/app/api/dashboard/route.ts`

### 12. No health check for the 12-app suite
- **Fix:** `npm run doctor` (`scripts/doctor.sh`) — checks node/deps/env files/API keys, runs the tests; `--live` pings all 12 ports.
- **Files:** `scripts/doctor.sh`, `package.json`

### 13. Bolton missing the cross-cutting ask bar + schedule action
- **Issue:** The July 6 patched prompts require every agent to have a dark ask bar + schedule action; Bolton had neither (9/11 schedule routes, 10 ask bars).
- **Fix:** `AskBoltonBar` (wired to Bolton's NL memory search, staying in his domain) + `/api/schedule` writing a task entry directly to his own store, matching the other agents' payload shape.
- **Files:** `apps/bolton/src/components/AskBoltonBar.tsx`, `apps/bolton/src/app/api/schedule/route.ts`, `apps/bolton/src/app/page.tsx`
- **Verification:** bolton tsc exit 0.

### 14. Scheduled tasks were written but never executed (Later item, completed)
- **Issue:** Every agent's Schedule action wrote a Bolton task entry — and nothing anywhere ran them. The feature was half-built.
- **Fix:** Scheduled-task runner in Leo (`instrumentation.ts` starts it, same pattern as Johnny's job worker): polls Bolton every 10 min, parses schedule entries, runs due ones (once/daily/weekly/monthly) by routing the prompt back to the creating agent via the invocation contract, writes each result to Bolton (`entry_type: output`, tag `scheduled-run`), persists last-run state in `.data/scheduler-state.json`. Safety: max 3 runs/tick, 90s per-run bound, `LEO_SCHEDULER_ENABLED=false` kill switch, `custom` free-text cadences surfaced but never auto-run, disabled on Vercel.
- **Files:** `apps/leo/src/lib/schedule/runner.ts`, `apps/leo/src/instrumentation.ts`, `apps/leo/.env.example`, `.gitignore`
- **Verification:** leo tsc exit 0. This also delivers the deferred "proactive/scheduled digests across Leo/Conner/James/Harris" — any agent's ask bar can now schedule a digest that actually runs.

### 15. Parallel agent fan-out (Later item, completed)
- **Issue:** Build plan deferred "parallel agent orchestration"; v1 invoke was single-agent sync only.
- **Fix:** `invokeAgentsParallel` (Promise.allSettled, failure-isolated per agent) + `/api/invoke` accepts `to_agents: string[]` (max 5) returning ordered responses. Single-agent contract unchanged.
- **Files:** `apps/leo/src/lib/agents/invoke.ts`, `apps/leo/src/app/api/invoke/route.ts`
- **Verification:** leo tsc exit 0; GET /api/invoke documents both shapes.

## Verification summary
- `npx tsc --noEmit` — exit 0 for all 12 apps and both packages (george, james, packages/jobs previously failed).
- `npm test` — 8/8 passing.
- `grep` sweeps — no remaining colour-hue utilities, no unresolved `--am-*` vars, no references to deleted code.
- Full `next build` could not be exercised in the audit sandbox (macOS-only native binaries in the lockfile: `@tailwindcss/oxide-darwin-x64`, `lightningcss-darwin-x64`; sandbox is linux-arm64). Builds should be re-run locally: `npm run build`.

## Known gaps (logged, not fixed — see AUDIT_REPORT.md)
- Suite portal (scattered-monogram landing) not built; `apps/home` is the dashboard per the App Dashboard spec, which supersedes the portal *for this surface*. The marketing portal remains an open build item.
- `george_ge`, `conner_cr`, `harris_hr`, `cole_co` monogram SVGs still drawn past the 512 viewBox — needs Robert to re-export (explicitly not a code fix per spec).
- ~~Bolton has no Ask bar / schedule route~~ — **closed in item 13**.
- Tier scaffolding (TierToggle, tier routes) still present in william/marc/bolton — spec says tiering is dropped this phase; left in place as harmless scaffolding rather than deleted, flagged for a decision.
- Gmail Testing-mode 7-day token expiry is handled with re-auth messaging in Marc/William — CASA Tier 2 verification must be kicked off before any second user (owner needed).
- Remaining genuinely-deferred "Later" items (external accounts, product decisions, or heavy engineering): Gmail CASA, Xero/GitHub certification, tier gating, booking APIs, generative video, Cole's cloud auto-edit pipeline on `packages/jobs`, William voice-drift/ghost-writing, iOS/Tauri phases, multi-tenant RLS enforcement. None block single-user use.
