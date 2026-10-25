# 08: Shipping and business

## Distribution

| Platform | Channel | Why |
|---|---|---|
| **Mac (full suite)** | **Direct download**: Developer ID-signed, hardened runtime, **notarised** DMG; updates via **Sparkle** | The Mac App Store requires the App Sandbox. 11am needs Accessibility (rewrite anywhere, screen context), Full Disk Access (iMessage, Mail data), Apple Events automation (Messages, Keynote), a terminal and arbitrary file access. Apple DTS confirms sandboxed apps can't use the Accessibility APIs this way |
| **Mac App Store (optional, later)** | A sandboxed **"11am Lite"**: Leo + Bolton (user-chosen folders) + William without rewrite-anywhere | Discovery and trust for some buyers. Doubles release work, so only do it if data says it's worth it |
| **iPhone** | App Store + TestFlight | No alternative for most users |

### Release engineering checklist
- [ ] Signing identities: Developer ID Application (Mac), Apple Distribution (iOS).
- [ ] Hardened runtime with only the entitlements you need (`com.apple.security.automation.apple-events`, plus a network client entitlement where relevant; no JIT unless the JS engine needs it, since JavaScriptCore inside WKWebView doesn't).
- [ ] `notarytool submit --wait` + `stapler staple` in CI; verify with `spctl -a -vv`.
- [ ] Sparkle 2 with EdDSA-signed appcast, delta updates, beta channel.
- [ ] Crash reporting opt-in; symbol upload.
- [ ] Model downloads from your CDN or Hugging Face with SHA-256 verification. Never bundle multi-GB models in the DMG.
- [ ] Stage 2 suite bundles (Marc.app etc.) installed or updated by the host app (signed and verified), or shipped in one DMG with an installer step.

---

## Payments and entitlements

### Recommended setup
```
Mac purchase (website) ──► Paddle or Lemon Squeezy (merchant of record: handles GST/VAT worldwide)
iPhone purchase ─────────► StoreKit 2 in-app purchase (Apple)
                 both ───► RevenueCat (or your own tiny service) ──► entitlements per 11am account
11am app (Mac + iPhone) ─► signs in (Sign in with Apple) ──► reads entitlements ──► unlocks agents
```
- **Merchant of record** (Paddle / Lemon Squeezy) means you don't register for GST/VAT in every country yourself.
- **Sign in with Apple** for the 11am account. Low friction and privacy-friendly. Required on iOS if you offer other social logins.
- **Offline grace:** entitlements are cached and signed. Agents keep working offline for 30 days.
- **External purchase links on iOS** are region-dependent and changing (US, EU, Japan and Australia have all had rulings or legislation since 2024). Default to IAP on iOS and check Apple's current guidelines for each storefront.
- Apple **Small Business Program**: 15% commission under US$1M/yr in proceeds. Enrol on day one.

### Pricing structure
Ideas to test, not decisions:

| Option | Shape | Notes |
|---|---|---|
| **A. Subscription** | Core A$X/mo; each agent +A$Y/mo; Founder bundle; Everything bundle | Predictable revenue; matches "team" framing ("hire Marc for A$9/mo") |
| **B. Own it** | One-time purchase per agent (+ paid major upgrades), Core one-time | **Local-first means your marginal cost is near zero.** A real differentiator against subscription fatigue |
| **C. Hybrid** (recommended to test) | One-time "own the apps" + optional subscription for **11am Cloud** (credits for Kimi/Claude, sync relay, Live Activity push, registry updates) | Fair: pay once for software, pay monthly only for things that cost you money |

**Free trial:** 14 days of everything, then Core keeps working at a free or basic level (so the habit survives), and add-ons lock.

### Cloud brain economics
- **BYO key** (Moonshot/OpenRouter/Anthropic/Google): you pay nothing and power users love it.
- **11am Cloud credits:** buy model usage through you (e.g. via OpenRouter on your account) at a markup. Needs metering, abuse limits, and a privacy policy covering the providers. Kimi K3-class pricing is around US$3 in / US$15 out per million tokens (check live), and a heavy research day might use 0.5–2M tokens, so price credits with that in mind.
- **Local-first keeps margins healthy:** most calls never touch the cloud.

---

## Google and Microsoft verification

| Platform | What's needed | Timeline / cost | Notes |
|---|---|---|---|
| **Google (Gmail, Calendar)** | OAuth consent screen verification. Gmail read/modify scopes are **restricted** and need extra review. Apps that store or transmit restricted data via servers may need an annual third-party **security assessment (CASA)** | Weeks to months; assessment fees can apply | A **local-only** client (data never touches your servers) is the easiest case. Document that architecture clearly in the submission. Comply with Google's **API Services User Data Policy incl. Limited Use**: no using Gmail data to train generalised AI models. Personal on-device adapters for the same user need a careful read (check) |
| **Calendar via EventKit** | None | — | Google/Exchange calendars added in macOS System Settings are readable through EventKit with no OAuth, so prefer this for Leo |
| **Microsoft (Outlook/M365 via Graph)** | Entra app registration + **publisher verification**; tenant admin consent for some work accounts | Days to weeks | Many business tenants block unverified apps |
| **Xero** | App partner terms; certification is needed for listing in the Xero marketplace | Weeks | Personal/direct use works earlier |
| **Apple (iMessage access)** | Nothing to apply for. It's local data with user-granted Full Disk Access + Automation | — | Explain it clearly in onboarding; never upload messages |

Plan: ship IMAP/iCloud/Fastmail/Outlook first if Google verification is slow, and dogfood Gmail with your own account in testing mode (limited to test users).

---

## Legal and privacy

- [ ] **Privacy policy** (plain-English first, legal second): what stays local (almost everything), what goes to cloud providers and when (only with consent, per agent), what your servers hold (account, entitlements, optional push tokens, nothing else).
- [ ] **Australian Privacy Act 1988 / APPs**, **GDPR** (EU/UK users), **CCPA** (California). Local-first makes compliance far simpler. You're mostly a software vendor, not a data processor, except for 11am Cloud.
- [ ] **Terms of service / EULA**, including AI output disclaimers (no financial, legal or tax advice; reuse George's `TaxDisclaimer` copy and extend it).
- [ ] **App Store privacy labels** (iOS): accurate and minimal.
- [ ] **AI transparency:** label AI-generated content where you publish it on the user's behalf (some platforms and jurisdictions require it).
- [ ] **Voice cloning / Personal Voice:** only the user's own voice, with explicit consent screens.
- [ ] **Recording laws:** meeting recording consent rules vary (AU states differ; some US states are two-party consent). Leo shows a consent reminder and can send a "this meeting is being transcribed" note.
- [ ] **Trademarks:** don't use "Dynamic Island" in marketing (Apple's mark). Clear the "11am" mark.
- [ ] **Open-source compliance:** `THIRD_PARTY_NOTICES`, no GPL code in the closed app (see [06](./06-open-source-map.md#rules-for-using-open-source-in-11am)).
- [ ] **Model licences:** record each in the registry; avoid non-commercial image models in the commercial product.
- [ ] **Export controls / sanctions:** standard for software with encryption. Answer the App Store encryption questions (HTTPS/standard crypto is usually exempt but must be declared).

---

## Backend (keep it tiny)

You need almost no server, which is a feature. Run what's left serverless (Cloudflare Workers, Fly or Vercel functions):

| Service | Purpose |
|---|---|
| Accounts + entitlements | Sign in with Apple → user id; RevenueCat webhooks → entitlements |
| Licence verification | Signed entitlement tokens for offline use |
| Push relay | APNs for Live Activity updates and urgent notifications (optional) |
| Model registry + agent templates | Static JSON on a CDN, signed |
| 11am Cloud proxy (optional) | Metered model proxy for credits users (no logging of content) |
| Crash/telemetry (opt-in) | Third-party privacy-first tool or self-hosted |

No user content ever lives on your servers, except transiently through the optional cloud proxy.

---

## Go-to-market basics

- **Positioning line:** "A team behind you. Eleven apps that work for you, on your Mac."
- **Wedge:** Core (Leo + Bolton + the notch) is free or cheap and earns the habit. Marc is the first paid add-on almost everyone needs.
- **Content engine:** you, building it in public, with videos made in Cole and posts written in William (dogfooding as marketing).
- **Beta:** 20–50 founders you know (Australian founder communities first), weekly feedback calls, a public changelog.
- **Pricing page:** per-agent cards in the monochrome monogram style ("Hire marc").
- **Proof:** "time saved" metrics from the event log (opt-in, local): "Marc saved you 3 h 20 m this week".

---

## Support and operations

- In-app **Send feedback** (attaches a diagnostics bundle that the user reviews first: logs, versions, tier, no content).
- **Status page** for cloud parts (registry, push relay, credits proxy).
- Docs site with per-agent guides and short videos.
- Release cadence: beta weekly, stable every 2–4 weeks, model registry as needed.
- Each June (WWDC): budget 2–4 weeks to adopt new macOS/iOS APIs and fix betas.
