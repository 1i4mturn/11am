# 09: Direction update (round 2)

Captures the feedback from round two. Where it conflicts with earlier docs, this file wins.

## The narrative, rewritten

**11am is software you own that works with the Mac you have.** It replaces the pile of subscriptions with one set of apps for the work a founder actually does: mail, files, writing, research, money, decks, design, video, learning.

Three promises, in this order:

1. **It doesn't keep costing you.** Most thinking runs on your Mac with Apple's on-device model or a local model, so there's no per-use bill. The cloud (your own Claude key) is optional and capped by you.
2. **It works with your computer, not against it.** It's native and light, it fits an 8 GB MacBook Air, and heavy work waits for the charger, a cool Mac and idle time or the overnight window. It never slows you down while you're working.
3. **It replaces apps, not just adds a chatbot.** Each app does its real job well. The intelligence shows up inside the app as drafts, summaries, search and a prepared brief.

**The team of 11 is how it works, not what we sell.** The agents (Leo, Bolton, Marc…) are the quiet workers inside the apps: monograms, a voice, a "who did this" line in the activity log. Lead with the apps and the promises. The team is the character underneath. In product copy, app names come first (Today, Files, Mail, Write, Research, Money…), and the agent appears as the worker ("Bolton found 3 files").

*If you've written a fuller narrative elsewhere, drop it in here and it replaces this section.*

## The look: printed on vellum

Not clear glass: **frosted vellum.** Translucent paper with a milky tint, a hint of fibre, crisp ink printed on top, and layers you can see through to the blurred desktop.

| Element | Treatment |
|---|---|
| Window base | Real behind-window blur of the desktop (system `NSVisualEffectView`), a faint paper wash, very light grain |
| Sheets (main content, side pane, cards) | Stacked vellum: each layer slightly more opaque than the one below, hairline edge, a lit top edge, a soft shadow that grows with "depth" |
| Paper tone | Pure white ↔ warm vellum (a slider in the Design Lab). Dark mode is smoked vellum: graphite frost with off-white ink |
| Ink | Near-black, never pure grey on grey. Display type in Alte Haas Grotesk, body text in SF Pro |
| The notch | Stays pure black so it merges with the hardware. White ink, dark inner cards |
| Colour | Still monochrome. Red appears only for recording and destructive actions |

The sandbox's **Design Lab** exposes every one of these as a live control so we can lock values together instead of arguing in words.

## Impact on the plan

- **Model strategy for the 8 GB Air:** Apple's on-device model (macOS 26+) is the default local brain. It costs no extra memory because the OS hosts it. Small local servers (Ollama, LM Studio) are optional. Claude with the user's own key handles deep work, behind a monthly cap. Overnight work defaults to local-only.
- **Business model:** prioritise "own it" pricing (see [08 › Pricing structure](./08-shipping-and-business.md#pricing-structure), options B/C). Avoid anything that requires ongoing per-user cloud cost to function.
- **Build order:** the sandbox (`/sandbox`) comes first to lock the look and the core flows (shell, notch, brain routing, overnight, Today, Files). The Rust core from [02](./02-architecture.md) follows once those are settled.
