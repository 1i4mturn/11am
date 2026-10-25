# 04: Design system: monochrome, glass, the notch

## Design principles

1. **Black, white and glass.** Monochrome content on solid surfaces; translucency for the navigation and control layer only. The colour in a user's content (photos, their brand, charts they choose) is the only colour on screen.
2. **Typography does the work.** Hierarchy comes from size, weight and space, never from colour or boxes.
3. **One thing at a time.** Each screen has one primary action. Secondary actions stay out of the way until needed (hover, ⌘K).
4. **The AI is felt, not seen.** No chat bubbles everywhere and no sparkle icons. Intelligence shows up as structure (lanes, summaries, drafts) and as a quiet agent pane. When an agent is working, the motion signature shows it.
5. **Show provenance.** Source chips, model badges and "why" reasons are part of the visual language, not footnotes.
6. **Calm motion.** Springs, not bounces. Things settle, they don't pop. Respect Reduce Motion.
7. **Same skeleton everywhere.** Every agent app shares the same three-zone layout, Ask bar, Activity drawer and Approvals. Learn one and you know all eleven.

---

## Colour

### Tokens (source of truth: `design/tokens.json` → generated Swift + CSS)

| Token | Light | Dark | Use |
|---|---|---|---|
| `ink` | `#0A0A0A` | `#F5F5F5` | Primary text, icons |
| `ink.secondary` | `#3A3A3C` (≈70%) | `#C7C7CC` | Secondary text |
| `ink.tertiary` | `#6E6E73` | `#8E8E93` | Meta, timestamps |
| `ink.quaternary` | `#AEAEB2` | `#48484A` | Placeholders, disabled |
| `paper` | `#FFFFFF` | `#000000` | Content canvas (docs, mail reader, sheets) |
| `paper.raised` | `#FAFAFA` | `#0E0E0F` | Cards on canvas |
| `paper.sunken` | `#F2F2F2` | `#161618` | Wells, inputs, code |
| `line` | `rgba(0,0,0,0.08)` | `rgba(255,255,255,0.10)` | Hairlines (0.5 pt on Retina) |
| `line.strong` | `rgba(0,0,0,0.16)` | `rgba(255,255,255,0.20)` | Selected outlines, focus rings (plus system focus ring) |
| `glass.*` | System Liquid Glass (`.regular`, `.clear`) | System | Sidebars, toolbars, panels, notch, Ask bar |
| `invert` | `#0A0A0A` bg / `#FFFFFF` fg | `#F5F5F5` bg / `#000000` fg | Primary buttons, selected chips (inverted pills) |
| `signal.destructive` | System red | System red | **Only** destructive actions and errors (accessibility and safety) |
| `signal.attention` | — | — | No colour: use weight, an ink dot and motion |

**On the existing palette:** the current web suite uses papery `#faf9f7`, panel `#edeeef` and graphite `#2f2f2f`. Keep "paper" as an optional **Warm** appearance (Settings › Appearance › Paper: Pure / Warm). Pure black-and-white is the default.

**Charts:** monochrome via line weight, dash patterns, fill density and direct labelling (see the dataviz rules in George's brief). Users can switch on a single accent if they want.

### Liquid Glass rules
- Use **system** glass: SwiftUI `.glassEffect(.regular, in: shape)`, `GlassEffectContainer` for grouped elements that morph, `.glassEffectID` for transitions. AppKit: `NSGlassEffectView`. Don't fake it with blur, because the system version adapts to content, Accessibility settings and future OS changes.
- **Glass for chrome, never for long-form content.** Reading surfaces (email body, document, sheet) are solid `paper`.
- **Tint glass with ink at 0–6% only.** No coloured tints.
- **Reduce Transparency** (`NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`) automatically swaps glass for solid `paper.raised` with a hairline. Test every screen this way.
- **Increase Contrast** thickens lines to `line.strong` and darkens `ink.tertiary`.

---

## Typography

| Role | Font | Size / weight (macOS pt) | Notes |
|---|---|---|---|
| Display (agent names, big numbers, report titles) | **Alte Haas Grotesk Bold** | 28–56 | The 11am signature. Lowercase agent names ("marc"). **Check the font licence for app embedding** before shipping |
| Title | SF Pro Display Semibold | 20–22 | Window titles, section heads |
| Headline | SF Pro Text Semibold | 13–15 | List item titles |
| Body | **SF Pro Text** Regular | 13 (default), Dynamic Type aware | All UI and reading text: legibility, accessibility, localisation |
| Reading (William, reports) | SF Pro Text or New York (user choice) | 15–17, line height 1.5 | Long-form comfort |
| Meta | SF Pro Text | 11 | Timestamps, chips |
| Numbers | SF Pro with **tabular figures** (`.monospacedDigit()`) | — | George, timers, progress |
| Mono | SF Mono | 12–13 | Johnny, code, IDs |

Rules: max 3 sizes per screen; no all-caps except tiny meta labels with tracking (+6%); headings in sentence case; agent names always lowercase in display type, title case in body text.

---

## Iconography and monograms

- **Monograms:** the existing two-letter monograms (`le`, `bn`, `mc`, `wm`, `jm`, `jo`, `ge`, `cr`, `rt`, `co`, `hr`) are the agent identity. Convert the SVGs (`packages/ui/src/assets/logos/`) to **template-rendered vector assets** (PDF/SVG in the asset catalogue) so they tint with `ink`.
- **App icons (macOS 26+ layered format, Icon Composer):** a glass rounded-square, black in dark and white in light, with the white/black monogram centred and the agent's **signature pattern** etched faintly into the glass layer. Supports Clear and Tinted modes. The suite reads as a family in the Dock, like Microsoft 365 or Adobe, but monochrome.
- **UI icons:** SF Symbols only, `.regular` weight, monochrome. Use custom symbols only for agent monograms.

---

## Agent signatures (identity without colour)

Each agent is told apart by **monogram + pattern + motion**, never by hue.

| Agent | Pattern (etched into glass, icon, empty states, 3–6% opacity) | Motion signature (working state) | Haptic (trackpad, optional) |
|---|---|---|---|
| **leo** | 12 clock ticks; the hand rests at 11 | Hand sweeps a quarter turn, settles at 11 | Single soft tap |
| **bolton** | Stacked horizontal strata (archive layers) | Thin cards slide and stack | Two soft taps |
| **marc** | Fine chevrons, like envelope folds | Rows sort into lanes | Soft tap |
| **william** | Ruled lines, a margin rule | Text "inks in" (blur to sharp, 120 ms per line) | — |
| **james** | Dot grid with a lens aperture | A scan line passes across source chips | — |
| **johnny** | Bracket corners `⌜ ⌟` and scanlines | Block cursor blinks, then fills progress blocks | Click-like tap on completion |
| **george** | Graph-paper grid | Digits tumble to the new value | — |
| **conner** | Diagonal vectors / arrows | Cards slide one stage to the right | — |
| **robert** | Registration and crop marks | Crosshair snaps to centre | Alignment tap (system snapping) |
| **cole** | Film perforations / frame lines | Playhead scrubs | — |
| **harris** | Dotted path with step markers | Path fills dot by dot | — |

Patterns appear only in: app icons, the agent's sidebar header, empty states, the notch when that agent is live, and onboarding. Never behind content.

---

## Layout: the shared skeleton

```
┌───────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●   mc  marc                    ⌕ Search or ask marc…          ◐  ⋯      │ ← glass toolbar
├──────────────┬──────────────────────────────────────────┬─────────────────────┤
│ SIDEBAR      │ CANVAS (solid paper)                     │ AGENT PANE (glass)  │
│ (glass)      │                                          │  ⌄ collapsible ⌘\   │
│              │                                          │                     │
│ Views        │  The real app: list, doc, grid, canvas   │  What marc sees     │
│  Needs you 4 │                                          │  Suggested actions  │
│  FYI      12 │                                          │  Why / sources      │
│  Later    31 │                                          │  Ask marc…          │
│              │                                          │                     │
│ Saved views  │                                          │  ─ activity ─       │
│  Investors   │                                          │  09:12 drafted ↩    │
│ + Tune…      │                                          │  09:10 filed   ↩    │
├──────────────┴──────────────────────────────────────────┴─────────────────────┤
│  ⌘K command  ·  ⌘J ask agent  ·  ⌘⇧A approvals (2)  ·  ● on-device           │ ← status strip
└───────────────────────────────────────────────────────────────────────────────┘
```
- **Sidebar (glass):** navigation and saved views. The "+ Tune…" entry at the bottom always opens Johnny's spec editor for that app.
- **Canvas (solid):** the app's real work surface.
- **Agent pane (glass, collapsible ⌘\\):** context for the current selection, suggestions, reasons, sources, scoped Ask, and that agent's recent activity with undo.
- **Status strip:** shortcuts, approvals count, the model badge (● on-device / ○ cloud · provider).
- **Minimum window:** 900×600. Below 1100 pt wide the agent pane becomes an overlay.

---

## Core components

| Component | Description |
|---|---|
| **Ask bar** | Glass capsule. Global (⌥Space) or scoped in-app (⌘J). Shows routing as it types ("→ james"). Voice by holding Fn |
| **Brief card** | Leo's check-in block: Done / Waiting on you / Next. Each line links to its source |
| **Approval card** | Agent monogram, action summary, full preview (diff for edits, rendered email for sends), risk label, *Approve / Edit / Reject / Always allow…* |
| **Activity row** | Time · monogram · verb · object · undo ↩ · "why" disclosure |
| **Source chip** | Inverted micro-pill: icon + short title ("✉ Sarah, 12 Oct"). Hover previews, click opens |
| **Model badge** | `● on-device · qwen3.6` or `○ cloud · kimi-k3`. Always visible on AI output |
| **Reason line** | One-line "because…" under AI decisions ("Needs you · she asked a direct question") |
| **Suggestion diff** | Inline strike/insert with Accept ⏎ / Reject ⌫. Monochrome: strike-through for deletions, underline + bold for insertions |
| **Thinking shimmer** | A soft luminance sweep across the placeholder (monochrome), with the agent's motion signature in the pane header |
| **Empty state** | Pattern at 4%, one sentence, one action ("Point bolton at a folder") |
| **Metric tile** | Big Alte Haas number, label, sparkline, delta in words ("up 4% vs last month") |
| **Command palette** | ⌘K: every action in every app, plus "ask…" fallback |
| **Toast** | Bottom-centre glass capsule, 4 s, includes undo |

---

## Motion

- Default spring: `.spring(response: 0.35, dampingFraction: 0.85)`; notch: `response 0.42, damping 0.78` (a touch of life, matching Dynamic Island feel).
- Durations: micro 120 ms, standard 250 ms, panel 350 ms.
- **Reduce Motion:** crossfades only; motion signatures become a static monogram with an ellipsis.
- Never animate text reflow in reading surfaces.

---

## The notch ("the 11")

A system-wide surface hanging from the camera housing. It's Leo's home, and every agent can surface live state through it.

### Geometry
- Detect the notch: on the built-in display, `NSScreen.safeAreaInsets.top > 0`. The notch rect is the gap between `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`.
- The window is a borderless, non-activating `NSPanel` positioned over the notch, at a level above the menu bar. `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`. Transparent outside the visible shape. `ignoresMouseEvents` is toggled by hover state so clicks pass through the empty areas.
- **Macs without a notch / external displays:** a floating black pill at top-centre (DynamicNotchKit's fallback approach), user-toggleable per display. Hidden in full-screen apps by default (option to keep it).

### States
```
1. IDLE: matches the hardware notch exactly (pure black, invisible).
   Optional "ears" either side (only when something is live):
        ┌──────────┐
   le ◜ │  notch   │ ◝ 2        ← left: working agent monogram (motion signature)
        └──────────┘              right: approvals count or "12m" to next meeting

2. PEEK: cursor enters a zone ~12 pt around the notch (or a 300 ms dwell):
   ╭────────────────────────────────────────╮
   │ marc drafted 3 replies · call in 12m   │   ~380×56, one line, no focus steal
   ╰────────────────────────────────────────╯

3. OPEN: click, or move the cursor into the peek:
   ╭──────────────────────────────────────────────────────────────╮
   │  Now      Approvals 2      Shelf      Ask                    │  ~640×360
   │──────────────────────────────────────────────────────────────│
   │  09:30  Investor call · Sarah Lee        prep ready  ▸        │
   │  ─────────────────────────────────────────────────────────── │
   │  jm  researching "AU payroll tools"   ▓▓▓▓▓▓░░░  18/30       │
   │  ge  receipts matched 11                          ↩          │
   │  ─────────────────────────────────────────────────────────── │
   │  ⌕ Ask the team…                                   hold fn 🎙 │
   ╰──────────────────────────────────────────────────────────────╯

4. LIVE: a long job or a recording becomes a live activity:
        ┌──────────┐
   ◯jm  │  notch   │  18/30       (progress ring + count)
   ● rec│  notch   │  12:41  ■    (Cole/Leo recording: red dot is the only colour, plus stop)

5. DROP: drag a file near the top of the screen and the notch opens as the Shelf:
   ╭──────────────────────────────────────────────╮
   │  Drop on an agent                             │
   │   bn file it   ge receipt   wm edit   jm read │
   │   ─────────────────────────────────────────── │
   │   Shelf: contract.pdf  logo.png  notes.txt   │
   ╰──────────────────────────────────────────────╯

6. VOICE: hold Fn (configurable): waveform in the notch, release to send to Leo.
```

### Behaviour rules
- **Never steal focus** unless the user clicks into Ask or Approvals text fields.
- **Collapse** 400 ms after the cursor leaves, unless typing or dragging.
- **Priority** of what shows in ears and peek: recording > imminent meeting (< 5 min) > approvals > live jobs > check-in ready.
- **Quiet hours / Focus:** ears hide. Only recording and meeting indicators stay.
- **Pages** are extensible: agents register notch pages through their manifest (`surfaces = ["notch.approvals"]`). Johnny can add a mini-app page later.
- **Trademark:** "Dynamic Island" is Apple's term. Call it **the notch** or **the 11** in product copy.

### Build references
- **DynamicNotchKit** (MIT): a Swift package for notch windows with a fallback for Macs without a notch. A good base or reference.
- **boring.notch**, **Atoll** (GPL-3.0): study the UX (shelf, HUD replacement, media, terminal, agent sessions), but **don't copy code into a closed-source app**.

---

## Accessibility (non-negotiable)

- VoiceOver labels on every control. The notch announces state changes politely, and only for user-relevant events.
- Full keyboard operation: every app, the notch (⌃⌥N opens it), Approvals, the Ask bar.
- Dynamic Type / text size respected in body and reading text.
- Contrast: `ink.tertiary` on `paper` is at least 4.5:1 (check both modes). Glass text is always `ink`, never tertiary.
- Never use colour alone, which the monochrome palette makes natural. Destructive actions keep system red **plus** a label.
- Reduce Transparency and Reduce Motion are fully supported (see above).

---

## Mockups

- **[Design canvas](https://claude.ai/artifact/WG7JfdUvy8fdtykjd8v3sE)** (details in [mockups/](./mockups/README.md)): the interactive notch (every state), the identity sheet, iPhone, and a main screen for each agent in light and dark.
- Each agent brief also contains wireframes for its key screens.
