# The team: agent briefs

Each agent is **a tool with a job, an app and a brain**. Not a person. They work on their own inside their autonomy limits, they rely only on each other, and they report through Leo.

| Brief | Monogram | Becomes the app for | Package |
|---|---|---|---|
| [Leo](./leo.md) | le | Today: calendar, tasks, briefs, meetings, the notch, routing | Core |
| [Bolton](./bolton.md) | bn | Files, notes, search, memory, shelf | Core |
| [Marc](./marc.md) | mc | Mail, messages, people | Add-on |
| [William](./william.md) | wm | Documents, rewrite-anywhere, voice | Add-on |
| [James](./james.md) | jm | Browser, deep research | Add-on |
| [Johnny](./johnny.md) | jo | Terminal, automations, Tune, mini-apps, models | Add-on (Tune-lite in Core) |
| [George](./george.md) | ge | Sheets, cash, runway, receipts | Add-on |
| [Conner](./conner.md) | cr | Pipeline, strategy, decks, proposals | Add-on |
| [Robert](./robert.md) | rt | Canvas, brand kit, image tools | Add-on |
| [Cole](./cole.md) | co | Recording, transcript editing, clips | Add-on |
| [Harris](./harris.md) | hr | Learning paths, cards, languages, reading | Add-on |

## How every brief is structured

1. **Role and one-liner**
2. **Replaces / enhances**
3. **Use cases** (concrete scenarios)
4. **Features**: v1 (MVP), v2, Later, **Not building** (anti-scope)
5. **How the AI is involved**: per feature: task class, autonomy level, trigger
6. **Works with**: what it gives to and gets from other agents
7. **Design and visual identity**: monogram, pattern, motion, layout, **wireframes**
8. **Usability**: shortcuts, onboarding, empty states, trust details
9. **Notch and iPhone**
10. **Mac integration**: frameworks and permissions
11. **Backend**: Rust module, data model, Swift side
12. **Lower-end Macs**: tier behaviour
13. **Open source to study**
14. **Tunable by Johnny**: what users can customise
15. **Risks and open questions**
16. **Build checklist**

## Collaboration matrix (who gives what to whom)

Rows give to columns.

| From ↓ / To → | Leo | Bolton | Marc | William | James | Johnny | George | Conner | Robert | Cole | Harris |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Leo** | — | decisions, meeting notes | follow-ups to send, reschedules | doc deadlines | briefing requests | automation schedules | deadlines (BAS) | goals | — | recording requests | study blocks |
| **Bolton** | context packs | — | people memory, attachments | voice samples, docs | prior sources | specs, skills storage | receipts, docs | org history | assets | media library | your notes as material |
| **Marc** | commitments, meeting requests | threads, people, attachments | — | drafts to polish | sender companies to research | — | invoices, bills | leads, deal activity | — | — | — |
| **William** | — | finished docs | drafts in your voice | — | — | — | investor-update copy | proposals, pitch copy | copy for graphics | scripts | writing feedback |
| **James** | meeting briefs | sources, reports | — | citations | — | API docs for connectors | market prices | market research | references, moodboards | references | learning sources |
| **Johnny** | automations | specs | specs | specs | specs | — | specs | specs | mini-app styling | specs | specs |
| **George** | cash alerts | financial facts | invoice chasers | numbers for updates | — | — | — | revenue and pricing data | chart data | — | finance literacy examples |
| **Conner** | priorities, OKRs | strategy decisions | outreach drafts | narratives | research questions | — | forecasts inputs (pipeline) | — | deck briefs | campaign briefs | skill gaps |
| **Robert** | — | brand kit | email signature | brand voice | — | design tokens | chart style | deck themes | — | motion and brand | — |
| **Cole** | meeting recordings | transcripts, media | — | transcripts to articles | — | — | — | marketing assets | stills | — | video lessons |
| **Harris** | learning sessions | cards, highlights | — | — | — | — | — | — | — | — | — |

## Shared to every agent (don't rebuild per agent)

- Ask bar (scoped), agent pane, activity rows with undo, approvals, provenance chips, model badge
- Tune button (Johnny spec editing)
- Context packs from Bolton, memory writes through Bolton's curator
- Policy engine (autonomy, data classes, budgets)
- Notch registration via manifest
- iPhone surface via the shared Rust core and CloudKit sync
