# conner: business building

> **The one-liner:** Conner decides what's worth building and helps you sell it. Pipeline, strategy, pitch decks and proposals, grounded in your real numbers and conversations.
> **Package:** Add-on · **Monogram:** `cr` · **App name:** *Conner*

## Role in the team
Conner is the commercial brain. He keeps a lightweight pipeline built automatically from your email and calendar, runs strategy work (validation, stress tests, pricing, go-to-market), and turns stories into decks and proposals with William's words, George's numbers and Robert's design. He challenges your plans as a red-teamer, not a cheerleader.

## Replaces / enhances
HubSpot/Pipedrive/Attio (for one person's pipeline), PowerPoint/Keynote/Pitch/Gamma (decks), proposal tools (PandaDoc/Proposify-lite), Notion strategy docs, consultants' frameworks (Lean Canvas, SWOT, positioning), OKR tools (light).

## Use cases
1. **Pipeline that builds itself:** Marc spots "interested in a pilot for 20 seats" and asks "add Brightly as a lead?" Conner creates the deal, logs every email and meeting automatically, and suggests next steps ("send pilot proposal; no reply in 5 days").
2. **"What should I focus on this quarter?"** A strategy review using George's numbers, the pipeline, your goals and James's market notes, ending with 3 priorities and the reasons.
3. **Stress-test an idea:** *"Usage-based pricing for the enterprise tier?"* Conner red-teams it (risks, assumptions, what would have to be true, cheapest experiment). This ports the existing `/stress-test` and `/validate`.
4. **Pitch deck:** *"Seed deck, 12 slides, for Northfield next Thursday."* Story outline (Conner) → copy (William) → numbers and charts (George) → design (Robert's brand theme) → export to PDF/Keynote/PPTX. Leo tracks the deadline.
5. **Proposal or quote:** from a deal → scope, pricing (George), terms → a beautiful PDF (Typst) → sent via Marc (approval) → won → quote handed to George/Xero for invoicing.
6. **Investor update (monthly):** metrics (George), wins and asks (Conner), in your voice (William), sent via Marc.
7. **Experiments log:** hypothesis → metric → result → decision (to Bolton).
8. **Weekly business digest** (ports `/digest`): pipeline movement, revenue, experiments, risks.

## Features

### v1 (MVP)
- **Pipeline (CRM-lite):** organisations and people (shared entities with Marc/Bolton), deals with stages (customisable), value, close date, next step; **auto-activity** from Marc (emails) and Leo (meetings); lead suggestions from email (approval to add); board and list views; "stale deal" nudges.
- **Strategy workspace:** structured documents for Lean Canvas, positioning, ICP, SWOT, pricing strategy, GTM plan; each generated as a first draft, then edited by you; **red-team** button on any plan; decisions logged to Bolton.
- **Strategy tools** (ported): idea validation, stress test, GTM planning, growth strategy, pricing strategy, weekly digest.
- **Decks:** outline → slide specs → rendered slides (layouts from Robert's theme: title, statement, bullets, chart, image, quote, team, ask); edit text inline; reorder; speaker notes; export **PDF** (v1), **Keynote** (via AppleScript export) and **PPTX** (generated OOXML).
- **Proposals and quotes:** templates (Typst), line items with George pricing, terms snippets, export PDF, send via Marc.

### v2
- **Experiments tracker** with results and decisions.
- **OKRs / goals** shared with Leo's weekly review.
- **Investor CRM** (a pipeline type) + monthly updates.
- **Quote → invoice** hand-off to George/Xero.
- **E-signature hand-off** (send a PDF for signing through a provider such as DocuSign, or macOS PDF signing).
- **Competitor tracker** (with James watches).

### Later
- Market sizing helper (TAM/SAM/SOM with sourced inputs from James).
- Board packs (Conner + George + Robert).
- Partnership/referral tracking.

### Not building
- Marketing automation, sequences or cold outreach at scale.
- Team CRM features (territories, quotas, forecasts by rep).
- A slide editor at Keynote's level (animation, morph). Export to Keynote for that.
- Website or landing-page builder.

## How the AI is involved

| Feature | Task class | Autonomy | Trigger |
|---|---|---|---|
| Lead detection | `classify.small` (from Marc) | **L1** (add lead?) or L2 if enabled | New mail |
| Activity logging | Deterministic linking (entity match) | L3 | Mail/meeting events |
| Next-step suggestions | `summarise.medium` over deal history | L0 | Daily |
| Strategy drafts | `reason.large` (cloud recommended with consent; local 35B on Tier C+) | Draft | Ask |
| Red-team | `reason.large` with an adversarial prompt pack | Draft | Button |
| Deck outline | `reason.large`/`draft.medium` → **slide spec JSON** | Draft | Ask |
| Slide rendering | Deterministic layout engine (Robert themes) | — | Spec change |
| Proposal assembly | `draft.medium` + George numbers (injected) | Draft → **L1 send** | Ask |

## Works with
- **James:** market and competitor research.
- **George:** pricing, unit economics, revenue data, forecasts (pipeline feeds George's forecast).
- **William:** narratives, copy, voice.
- **Robert:** deck themes, layouts, visuals.
- **Marc:** leads, deal emails, sending proposals.
- **Leo:** goals, deadlines, meeting prep for deals.
- **Bolton:** strategy decisions, org history.

## Design and visual identity
- **Pattern:** diagonal vectors and arrows (direction).
- **Motion:** deal cards slide one stage to the right; slides assemble from outline lines.
- **Tone:** commercial, candid. "This plan depends on a 4% conversion rate you haven't seen yet."

### Wireframe: pipeline
```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ cr  conner · pipeline                                 ⌕ Ask conner…      ◐  ⋯   │
├───────────────┬──────────────────────────────────────────────────┬───────────────┤
│ Pipeline      │ Lead (5)     Talking (3)   Proposal (2)  Won (4) │ conner        │
│ People        │ ┌─────────┐  ┌─────────┐   ┌─────────┐           │               │
│ Strategy      │ │Brightly │  │Acme     │   │Northwind│           │ Pipeline A$86k│
│ Decks         │ │A$12k    │  │A$30k    │   │A$18k    │           │ weighted A$31k│
│ Proposals     │ │from ✉   │  │mtg Thu  │   │sent 6d ⚠│           │               │
│ Experiments   │ └─────────┘  └─────────┘   └─────────┘           │ Nudge:        │
│ Digest        │ ┌─────────┐                                      │ Northwind:    │
│ + Tune…       │ │Kite Co  │                                      │ follow up?    │
│               │ │A$6k     │                                      │ draft ready ▸ │
│               │ └─────────┘                                      │               │
├───────────────┴──────────────────────────────────────────────────┴───────────────┤
│ ⌘K · ⌘J ask conner · ● on-device                                                 │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Wireframe: deck builder
```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ cr  Seed deck · Northfield · due Thu                theme: 11am mono ▾  export ▾ │
├───────────────┬──────────────────────────────────────────────────┬───────────────┤
│ 1 Title       │ ┌──────────────────────────────────────────────┐ │ conner        │
│ 2 Problem     │ │                                              │ │ Story check:  │
│ 3 Insight     │ │   Founders run five jobs at once.            │ │ ✓ problem     │
│ 4 Product   ◀ │ │   11am gives them a team.                    │ │ ✓ traction    │
│ 5 Traction    │ │                                              │ │ ⚠ "why now"   │
│ 6 Market      │ │   [ product screenshot · robert ]            │ │   is weak     │
│ 7 Model       │ │                                              │ │               │
│ 8 Team        │ └──────────────────────────────────────────────┘ │ numbers: ge ✓ │
│ 9 Ask         │  notes: keep to 40 seconds…                      │ copy: wm ✓    │
│ + slide       │                                                  │ red-team ▸    │
└───────────────┴──────────────────────────────────────────────────┴───────────────┘
```

## Usability
- **Shortcuts:** ⌘N new deal · ⌘⇧N new deck · ←/→ move deal stage · ⌘⇧T red-team · ⌘E export.
- **Onboarding:** "What do you sell, and to whom?" (3 questions) → Conner drafts positioning + ICP → scans the last 90 days of email (via Marc) to suggest existing deals → you confirm.
- **Candour controls:** "how blunt?" slider for red-teaming.
- **Empty state:** arrows pattern; "Tell Conner what you're building."

## Notch and iPhone
- **Notch:** "New lead from email: add?" peek; deck-export progress.
- **iPhone:** pipeline glance and nudges, log a call by voice ("call with Acme went well, wants pricing for 50 seats") → deal updated + Marc follow-up draft, review decks.

## Mac integration
Contacts · EventKit · Keynote via AppleScript (open a generated .key or export) · PDFKit · Quick Look (deck previews) · App Intents ("Add lead", "Pipeline status") · Share extension (share a LinkedIn profile URL → lead with a James brief).
**Permissions:** Automation (Keynote), only when exporting to Keynote.

## Backend
- **Rust `core/conner`:** deals and stages, activity linker (entity resolution from Marc/Leo events), nudge rules, strategy documents (structured JSON + Markdown), tool prompt packs (validate, stress test, GTM, growth, pricing, digest), slide spec model, **deck renderer contract** (spec → layout boxes, shared with Robert's layout engine), PPTX writer (OOXML zip: slides, layouts, text, images, simple charts as images), Typst proposal templates.
- **Tables:** `deals(id, org_id, title, stage, value, currency, close_date, next_step, source_ref)`, `deal_activities(id, deal_id, kind, ref, ts)`, `stages(id, pipeline, name, order, probability)`, `strategy_docs(id, kind, title, json, md, updated_at)`, `experiments(id, hypothesis, metric, result, decision, status)`, `decks(id, title, theme_id, slides_json, deadline)`, `proposals(id, deal_id, template, line_items_json, status, pdf_ref)`.
- **Swift:** board UI, deck editor (SwiftUI-rendered slides; `ImageRenderer` → PDF), proposal preview.
- **Port from current repo:** `apps/conner/src/lib/strategy/engine.ts` (all `run*` functions → tools), `invokeJamesResearch`, handoff logic.

## Lower-end Macs
- **Tier A/B:** pipeline, linking, decks rendering and exports are all local and light; strategy and red-team quality depends on model size, so recommend cloud (consent) or overnight runs; deck outlines with a medium model are fine on B.
- **Tier C+:** local strategy work with a 35B-class model.

## Open source to study
`twentyhq/twenty` (AGPL: CRM data model study) · `marp-team/marp`, `slidevjs/slidev`, `hakimel/reveal.js` (deck pipelines) · `scanny/python-pptx` (OOXML reference) · `typst/typst` · `documenso/documenso` (AGPL: signing flow study) · `makeplane/plane` (AGPL).

## Tunable by Johnny
Pipeline stages and fields; deal views; nudge rules; strategy frameworks (add your own); deck templates and slide layouts; proposal templates and terms snippets; digest contents.

## Risks and open questions
- **Auto-CRM false positives.** Default to asking ("add as lead?") and learn from answers.
- **PPTX fidelity:** keep layouts simple and test in PowerPoint and Keynote; PDF is the primary export.
- **Strategy quality locally:** set expectations, offer cloud, show reasoning and assumptions explicitly.
- **Open question:** should decks live in Conner or Robert? Recommendation: Conner owns the deck (story, structure, deadline); Robert owns the theme and visual polish.

## Build checklist
- [ ] Deals/stages/activities model + board/list UI
- [ ] Auto-activity linking from Marc and Leo
- [ ] Lead detection hand-off + approval
- [ ] Nudges
- [ ] Strategy workspace + ported tools + red-team
- [ ] Slide spec + renderer (Robert themes) + editor
- [ ] Exports: PDF, Keynote, PPTX
- [ ] Proposals (Typst) + send via Marc
- [ ] Weekly digest
- [ ] v2: experiments, OKRs, investor CRM/updates, quote → invoice, e-sign, competitor tracker
