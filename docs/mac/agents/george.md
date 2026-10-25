# george: finance and sheets

> **The one-liner:** George knows where the money is, where it's going and what happens next, and he does your spreadsheets without the spreadsheet pain.
> **Package:** Add-on · **Monogram:** `ge` · **App name:** *George*

## Role in the team
George is the numbers. He reads your accounting (Xero), payments (Stripe), bank exports and receipts; keeps a live picture of cash, burn and runway; models scenarios; and gives you a spreadsheet that understands English. **George never does arithmetic with an LLM.** Models write formulas or SQL, and deterministic engines compute. Finance data is **local-only by default**.

## Replaces / enhances
Excel and Numbers (the 80% of use: lists, budgets, models, quick analysis), budgeting apps, Xero dashboards (read-side), Dext/Hubdoc (receipt capture and matching), cash-flow forecasting tools (Float, Fathom-lite), pricing calculators.

## Use cases
1. **"How much runway do I have?"** Cash (Xero/bank) ÷ average net burn (last 3 months), with the assumptions shown and a "what if" slider.
2. **Receipt in, done:** drop a receipt on the notch or snap it on iPhone. George extracts vendor, date, amount and GST, matches it to the bank transaction, and attaches it in Xero (approval required for the write).
3. **Monthly close brief:** "Revenue up 6%, mostly two new annual plans; software costs crept up A$340 (3 new tools); burn steady." Each line links to transactions.
4. **Scenario modelling:** "What if I hire two engineers in March at A$140k?" You get a new runway and a cash curve, side by side with the base case.
5. **Spreadsheet with English:** "add a column with GST-exclusive amounts", "which customers churned last quarter?", "clean up these dates". Formulas are generated and explained; queries run in DuckDB.
6. **Subscriptions audit:** "You're paying for 3 note-taking apps and 2 transcription tools." Duplicates found from transactions.
7. **BAS/GST helper (AU):** quarterly worksheet from Xero data, with the deadline in Leo's calendar and a disclaimer: George prepares, your accountant or you lodge.
8. **Invoice chasing:** overdue invoices → Marc drafts polite chasers (approval).
9. **Pricing and unit economics:** CAC, LTV, payback, margin per plan (port the existing calculators), shared with Conner.

## Features

### v1 (MVP)
- **Sheets:** IronCalc engine (formulas, multiple sheets, xlsx import/export), a native grid (virtualised, keyboard-first, fill handle, freeze panes, number formats with tabular figures), charts (Swift Charts, monochrome styles), CSV import with type detection.
- **AI in sheets:** formula from English (and explain any formula), clean column (dates, names, currencies), fill/transform by example, **"ask your data"** (LLM → SQL → DuckDB over the sheet → result + the query shown).
- **Finance dashboard:** cash, monthly burn, runway, revenue, top expense categories, upcoming bills. Sources: **Xero** (OAuth), **Stripe** (API key), bank **CSV/OFX/QIF** imports.
- **Transactions:** unified list, categorisation (rules + small model + your corrections), search, splits.
- **Receipts:** capture (notch drop, iPhone scan, Marc attachments), OCR + extraction, matching to transactions, attach to Xero (approval).
- **Models and calculators:** runway, pricing, unit economics, break-even, loan/repayments, GST (port the existing George calculators and models).
- **Tax disclaimer** on anything tax-related (reuse `TaxDisclaimer`).

### v2
- **Forecasting:** 12-month cash forecast (deterministic: recurring items + seasonality via ETS/MSTL from `augurs` + pipeline from Conner), scenarios, alerts ("runway below 6 months").
- **Bank feeds:** Australia via CDR intermediaries (e.g. Basiq), US via Plaid, UK/EU via GoCardless Bank Account Data, all through accredited providers (costs and accreditation via them).
- **Subscriptions detection** and duplicate-tool audit.
- **Invoice tracking + chasers** (with Marc); quote → invoice hand-off from Conner to Xero.
- **BAS/GST worksheet** (AU); generic VAT/sales-tax summaries elsewhere.
- **Multi-currency** (FX rates from a free source with dates shown).
- **Investor-update numbers pack** for Conner/William.

### Later
- Personal finance view (net worth, investments) separated from business.
- Apple **FinanceKit** on iPhone (Apple Card/Cash/Wallet transactions, in regions where available).
- Board-pack financial slides (with Conner and Robert).

### Not building
- A general ledger or accounting software (Xero/MYOB/QuickBooks remain the ledger of record, which avoids the compliance burden).
- Tax lodgement, payroll, invoicing engine (use Xero; George prepares and reads).
- Trading or investment advice.
- Excel VBA/macros compatibility.

## How the AI is involved

| Feature | Task class | Autonomy | Trigger |
|---|---|---|---|
| Receipt extraction | Vision OCR + `extract.small` (JSON schema) | L2 (stored), **L1 (write to Xero)** | Capture |
| Transaction matching | Deterministic (amount/date/vendor fuzzy match) + `classify.small` tie-breaks | L2 | New receipt/transaction |
| Categorisation | Rules → `classify.small` with your corrections | L2 | New transaction |
| Formula/SQL generation | `code.large` (local coder on Tier C+) | Suggestion (shown before applying) | Ask |
| Narratives (monthly brief) | `summarise.medium` over computed figures (**numbers injected, never generated**) | L3 | Month end / ask |
| Forecasting | **Deterministic models**; LLM explains drivers | L3 | Daily |
| Anomaly alerts | Deterministic thresholds + `summarise.small` | L2 | Daily |
| Chasers | Marc `draft.medium` | **L1** | Overdue invoice |

**Data class:** `finance` is local-only unless the user explicitly enables cloud for George, and even then only aggregated figures are sent where possible.

## Works with
- **Conner:** pricing, pipeline → revenue forecast, unit economics, investor numbers.
- **Marc:** invoices and bills in email, chasers.
- **Bolton:** receipts, contracts with costs, financial facts as memories.
- **Leo:** deadlines (BAS, invoices due, renewals), cash alerts in briefs.
- **William:** numbers for investor updates (as data, never paraphrased).
- **Robert:** chart styles for decks.
- **Harris:** finance-literacy lessons using your own numbers as examples.

## Design and visual identity
- **Pattern:** graph-paper grid.
- **Motion:** digits tumble to new values; charts draw left to right once.
- **Numbers:** Alte Haas for hero figures; SF Pro tabular figures everywhere else; negative numbers in brackets plus a minus sign (no red needed); deltas in words ("up 6%").
- **Charts (monochrome):** line weight for primary vs comparison series, dashed for forecast, hatched fills for categories, direct labels instead of legends.

### Wireframe: dashboard
```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ ge  george · oct 2026                                  ⌕ Ask george…      ◐  ⋯  │
├───────────────┬──────────────────────────────────────────────────┬───────────────┤
│ Dashboard     │   Cash              Burn / mo        Runway      │ george        │
│ Sheets        │   A$412,800         A$29,100         14.2 mo     │               │
│ Transactions  │   ▁▂▃▄▅▅▆▆▇▇▇█      ▅▅▆▅▅▆▅▆▅▅▅▅    down 0.3   │ Oct so far:   │
│ Receipts   3  │ ─────────────────────────────────────────────────│ revenue +6%   │
│ Forecast      │   Cash, 12 months                                │ (2 annual     │
│ Models        │   ───────────╮                                   │ plans).       │
│ Calculators   │               ╲________  base                    │ Software +A$  │
│ Integrations  │                ╲- - - -  hire 2 in Mar           │ 340 (3 new).  │
│ + Tune…       │ ─────────────────────────────────────────────────│               │
│               │   Upcoming   BAS due 28 Nov · AWS A$1,240 3 Nov  │ ⚠ 3 receipts  │
│               │   Top costs  Payroll 61% · Software 14% · …      │ unmatched ▸   │
├───────────────┴──────────────────────────────────────────────────┴───────────────┤
│ ⌘K · ⌘J ask george · Xero ✓ synced 6m ago · ● on-device (finance stays local)    │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Wireframe: sheet with ask
```
┌───────────────────────────────────────────────────────────────────────────┐
│ ge  Customers 2026.xlsx              ⌕ "which customers churned in Q3?"   │
├────┬────────────┬──────────┬────────────┬─────────────┬──────────────────┤
│    │ A Customer │ B Plan   │ C Start    │ D End       │ E MRR            │
│ 1  │ Acme       │ Annual   │ 2025-03-14 │             │ 1,200.00         │
│ 2  │ Brightly   │ Monthly  │ 2025-11-02 │ 2026-08-30  │ 89.00            │
│ …  │            │          │            │             │                  │
├────┴────────────┴──────────┴────────────┴─────────────┴──────────────────┤
│ Answer: 7 customers churned in Q3 (A$1,904 MRR).  ▸ show query            │
│ SELECT Customer, MRR FROM sheet WHERE "End" BETWEEN '2026-07-01' AND …    │
│ [Insert as new sheet] [Chart it] [Copy]                ● on-device        │
└───────────────────────────────────────────────────────────────────────────┘
```

## Usability
- **Shortcuts:** standard spreadsheet keys (Excel-compatible where sensible) · ⌘J ask · ⌘= formula from English · ⌘⇧E explain formula · ⌘R refresh integrations.
- **Onboarding:** connect Xero and/or Stripe, or import a bank CSV → George shows "here's what I see" (cash, burn, runway) within a minute → confirm categories (10 quick corrections) → choose the alert thresholds.
- **Show your working:** every figure has a "how was this calculated?" disclosure (formula, query or transactions).
- **Disclaimers:** tax and financial outputs carry a short, non-annoying note with a link to more.
- **Empty state:** graph-paper pattern; "Connect Xero or drop a bank export to get your runway."

## Notch and iPhone
- **Notch:** "Receipt filed ✓", "Payment due tomorrow: A$4,200", runway alert peek; drop target "ge receipt".
- **iPhone:** cash/burn/runway widget, snap receipts (VisionKit scanner), approve categorisations and Xero writes, monthly brief.

## Mac integration
Swift Charts · Vision (`VNRecognizeTextRequest`, document segmentation) · VisionKit (iPhone scanner) · Quick Look (xlsx/csv previews) · `ASWebAuthenticationSession` (Xero OAuth) · Keychain · App Intents ("What's my runway?", "Add receipt") · FinanceKit (iPhone, where available).
**Permissions:** none beyond integrations; Camera on iPhone for scanning.

## Backend
- **Rust `core/george`:** IronCalc workbook integration (load/save xlsx, recalc, formula parsing), DuckDB (`duckdb-rs`) for "ask your data" and analytics, importers (CSV with dialect sniffing, OFX/QIF parsers, `calamine` for xls/xlsx/ods), Xero client (OAuth2, rate limits, webhooks later), Stripe client, categorisation rules engine, receipt matcher, forecasting (`augurs` ETS/MSTL + recurring detection), scenario engine, alert evaluator, exports (`rust_xlsxwriter`, Typst for PDF reports).
- **Tables:** `accounts_fin(id, source, name, currency)`, `transactions(id, account_id, date, amount, currency, description, counterparty, category, source_ref, receipt_id, data_class='finance')`, `receipts(id, blob_ref, vendor, date, amount, tax, currency, extracted_json, match_status, xero_ref)`, `categories`, `cat_rules`, `forecasts(id, as_of, horizon, series_json, assumptions_json)`, `scenarios(id, name, changes_json)`, `alerts(id, kind, threshold, enabled)`, `models(id, kind, inputs_json, outputs_json)`.
- **Swift:** grid view (high-performance, AppKit `NSTableView`-style virtualisation or a custom Metal grid later), charts, receipt capture UI.
- **Port from current repo:** `apps/george/src/lib/{finance/engine.ts, finance/tax.ts, models, import/spreadsheet.ts, xero/client.ts, stripe/client.ts}`, `components/TaxDisclaimer.tsx`, the unit-economics and calculators pages.

## Lower-end Macs
George is the most low-tier-friendly agent: engines are deterministic and light. **Tier A:** OCR via Vision, extraction via Apple FM/small model, formulas via a small model with templates (cloud for complex asks only with consent, since finance is local-only by default, so complex asks queue overnight). **Tier B+:** everything local.

## Open source to study
`ironcalc/IronCalc` · `tafia/calamine` · `jmcnamara/rust_xlsxwriter` · `duckdb/duckdb` · `pola-rs/polars` · `grafana/augurs` · `actualbudget/actual` (rules, UX) · `firefly-iii/firefly-iii` (AGPL: rules engine study) · `beancount/fava` · `dream-num/univer` (sheet mini-apps).

## Tunable by Johnny
Dashboard tiles; categories and rules; alert thresholds; forecast assumptions; report templates (monthly brief, investor pack); custom calculators as mini-apps.

## Risks and open questions
- **Bank feed access in AU** requires going through CDR intermediaries (cost, terms). Start with Xero (which already has feeds) + CSV.
- **Spreadsheet expectations:** users will try Excel-grade models. Be clear: "George handles everyday sheets; open in Excel for heavy models." Use xlsx round-trip fidelity tests.
- **Accuracy and liability:** disclaimers, show-your-working, never fabricate numbers (the injection-of-computed-numbers rule).
- **Open question:** the grid in SwiftUI vs AppKit. Recommendation: AppKit-backed virtualised grid for performance, wrapped for SwiftUI.

## Build checklist
- [ ] IronCalc integration + xlsx round-trip tests
- [ ] Native grid UI + formats + charts
- [ ] Formula from English + explain formula
- [ ] DuckDB "ask your data" (query shown)
- [ ] Importers: CSV/OFX/QIF
- [ ] Xero + Stripe connectors
- [ ] Transactions + categorisation rules + corrections
- [ ] Receipts: capture, OCR, extraction, matching, Xero attach (approval)
- [ ] Dashboard (cash, burn, runway) with "how calculated"
- [ ] Port calculators and models
- [ ] v2: forecasting + scenarios + alerts, bank feeds, subscriptions audit, BAS worksheet, chasers, FX
