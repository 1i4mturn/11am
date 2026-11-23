# 11: Bringing the suite onto brand v2

The plan for moving the Mac sandbox (`sandbox/`, branch `claude/mac-rebuild-plan`) and the iPhone target onto brand guidelines v2, UI kit v1 and the 11am design system. Where this file conflicts with 04 and 09, this file wins. The look in 09 ("printed on vellum", warm paper tone, graphite dark mode, Alte Haas, SF Pro body, red for recording) is retired.

Reference: the canvas "11am suite refresh" (headless Mac, the drop, the puck, the lens, iPhone). Source files: `11amdev/brand` (guidelines, UI kit, `monograms-2026-11/`, `vellum-grain.png`).

## What the audit found

| Area | Today | Brand v2 | Size of the change |
|---|---|---|---|
| Type | Alte Haas Grotesk (display) + SF Pro everywhere (`.font(.system` 1,202 uses in 59 files) | Schibsted Grotesk headings, Instrument Sans reading, Courier Prime labels, Hack code, Biro notes | Large, mostly mechanical |
| Colour | Tunable ink softness, `inkSecondary` (259) and `inkTertiary` (506) faded text, warm paper tone, `Color(red:` (44) | Ink #0a0a0a and paper #ffffff at full strength; recede with vellum, never by fading | Large; needs judgement per screen |
| Surfaces | `VellumSheet` levels 0-3 with hairline edges, lit top edge, `theme.well` (115), `theme.raised` (48) | `sheet`, `note`, `sheet-ink`, `lift`, `lift-hi`, ink panels; no outlines | Medium |
| Shape | `theme.radius` 10.7 (132 uses), `RoundedRectangle` (252) | Square (radius 0). 8 for a menu row, 12 for the drop notice, 36 for the drop, pills and circles | Medium |
| Monograms | Old marks in `Assets.xcassets/Logos` with old codes `mc`, `wm`, `rt`, `co` (69 string uses); rounded-square tiles | New locked SVGs: `mr`, `wi`, `rb`, `ce`; always in circles in interface | Small |
| Icons | SF Symbols (273 uses in 49 files), one per app in `AppSection.symbol` | No icon set. Words on pills; → ← × only; a needed icon is a 1.5px ink line | Large; needs a decision (below) |
| Labels | `SectionLabel`: uppercase, tracked, faded (142 uses) | Courier Prime 12px, lowercase, full ink | Small (one component) |
| Structure | One main window: sidebar + section sheet + agent pane (`RootView`) | Headless: the drop and the puck always there, each app in its own window | Large |
| Notch | Black panel with now / ask / overnight pages | The drop: #000, 36px corners, 12 circles, white notices, live, shelf, open row, ask | Medium (rewrite of `NotchView`) |
| Ask panel | ⌥Space opens a panel (`AppDelegate.openAsk`) | The puck: ink disc with the 11, halo while listening, opens to a note | Medium |
| Grain | Generated random specks (`GrainTexture`) | `vellum-grain.png` tiled at 256px on ink, notes, sheets and lifted paper | Small |
| iPhone | System fonts and SF Symbols throughout `PhoneViews.swift` | Same system; drop as home, puck, island, notes | Medium |

## Phase 0: assets and tokens

1. **Fonts.** Remove `AlteHaasGrotesk*.ttf`. Add as `.ttf` or `.otf` (CoreText can't register woff2, so take the desktop files from Google Fonts or the foundries): Schibsted Grotesk 700, 800, 900; Instrument Sans 400, 500, 600; Courier Prime 400; Hack 400, 700; Biro Script; Reenie Beanie. `FontRegistry` already registers bundled `.ttf`; extend it to `.otf`. Add the same files to the Phone target (`UIAppFonts`). Biro's licence must be confirmed before shipping.
2. **Monograms and marks.** Replace `Assets.xcassets/Logos` with the solid SVGs from `monograms-2026-11` (`leo_le_solid.svg` … `11am_11_solid.svg`), keep template rendering so one file serves ink and paper. Add both wordmarks (solid for under 160px, outline above). Strip the C2PA metadata block first; it is most of each file. Rename codes everywhere: `mc` → `mr`, `wm` → `wi`, `rt` → `rb`, `co` → `ce` (`AgentLogo.name`, `AppSection.monogram`, `NotchView`, JSON fixtures). App icon: the `11am_11_tile.svg`.
3. **Texture.** Add `vellum-grain.png` and replace `GrainTexture` with a tiled image at 256pt. Type and marks carry the tooth as a mask (see the guidelines' `mask-image`); in SwiftUI, `.mask` with the tiled tooth image on text layers. Start with surfaces only and add the type mask if it renders cleanly at Retina.
4. **Tokens.** New `Design/Tokens.swift`, a straight copy of `tokens.json`:
   - colour: `ink` #0a0a0a, `paper` #ffffff, `drop` #000000, `sheet` paper 56% blur 8, `note` paper 82% blur 10, `sheetInk` paper 12% blur 10, `halo` paper 90%
   - radius: 0, row 8, notice 12, drop 36, pill, circle
   - shadow: `lift`, `liftHi`, `liftRow`, `errorBar`, `ruleOpen` (the only outline, 1.5pt inset)
   - spacing: gap 16, pad 24, field 48, hit 44
   - type styles: display 84/900/-0.05em, numeral 160/900, heading 44/800/-0.035em, subheading 26/700/-0.02em, monogram, lead 20/500, body 17/1.55 justified, ui 16, small 15, button 15/600, label 12 Courier lowercase, code 13 Hack, note 22 Biro at -3°
   Nothing outside `Tokens.swift` types a colour, radius or shadow.

## Phase 1: Theme and surfaces

- **Theme.** Remove `paperTone`, `inkSoftness`, `frost`, `clarity`, `cornerRadius`, `displayFace` and `backdrop` from `ThemeValues`; those are now fixed by the brand. Keep `motion` (reduced motion still wins). The Design Lab becomes a read-only token sheet, or is removed.
- **Appearance.** The tokens have two themes, paper and ink. Map the system dark appearance to the ink theme (ink ground, paper text, `sheetInk` vellum), not graphite. Decision needed (below).
- **Faded text.** Replace `inkSecondary` and `inkTertiary` with full-strength ink, and move the hierarchy into size, weight and Courier labels. Where something genuinely needs to sit back, put it under a `sheet`. Do this per app, not by find-and-replace, because each case needs a choice.
- **Surfaces.** Rewrite `Vellum.swift`:
  - `.sheet()`, `.note()`, `.sheetInk()`: tooth texture, token fill, behind-window blur. `NSVisualEffectView` can't set an exact blur radius; use the material closest to 8 to 10pt plus the token fill.
  - `.lift(hi:)`: white paper with the `lift` or `liftHi` shadow, no edge stroke. Fields, menus, cards, dialogs and windows.
  - `.inkPanel()`: solid ink with tooth.
  - Remove the hairline edge stroke and lit top edge; the system has no outlines except `ruleOpen`.
  - `theme.well` → `.lift()`. `theme.raised` (selected row) → `liftRow` with radius 8.
- **Shape.** Every `theme.radius` and literal `RoundedRectangle` goes to a radius token. Cards, notes, fields and windows are square.

## Phase 2: components (`Components.swift`)

| Old | New |
|---|---|
| `AgentLogo`, `Monogram` (rounded tile) | `Agent(code, size, style)`: circle. Styles: ink disc with paper glyph, paper disc with ink glyph, `sheetInk` (resting in the drop), open ring. The 11 centres with its own file. |
| `Wordmark` | `Wordmark(style: .solid / .outline)`, outline above 160pt wide only, never under vellum |
| `SectionLabel` | `Label`: Courier Prime 12, lowercase, full ink |
| `DisplayTitle`, `SectionHeader` | `Heading(.display / .heading / .subheading)`, sentence case. `Opener` for the overprint (ink square with numeral, outlined word in Schibsted Black at 1.5pt, note stepped half a square) |
| Buttons | `Pill(.ink / .open / .paper / .openOnInk)`, sentence case, 44pt minimum (34pt allowed inside the drop and notices) |
| Status text | `Chip(.filled / .open)`: filled for done, open for running or queued |
| Progress bars, `ProgressView` | `ProgressDots(done, of)`, never a smooth bar |
| Text fields | `Field`: lifted white card; `liftHi` on focus; error = `errorBar` + ink chip + one help line |
| Toggles, checkboxes, radios | Circle that fills; dot in a ring; pill toggle that turns ink |
| Menus | Lifted card, selected row lifts again (`liftRow`, radius 8) |
| Tables | No rules between rows; agent column is a circle; times in Hack; status chips |
| Toasts | `Note` led by the agent's circle, newest on top, Courier label `08:02 · marc` |
| Dialogs | `liftHi` card over a `sheet`; safe choice open pill, action ink pill |
| Empty states | Plain line saying what happens next |
| Loading | Wordmark slice glitch or a Hack typing caret; stops under reduced motion |
| Handwritten touch | `HandNote`: Biro 22 at -3°, a few words only |

**Icons.** `AppSection.symbol` goes. Apps are named with words on pills. The 273 SF Symbol uses need a pass app by app: most become words or are removed; → ← × stay. See decision 1 for editor toolbars and media controls.

**Copy.** Labels lowercase, everything else sentence case, no em dashes, errors say what is missing and how to fix it.

## Phase 3: headless structure

1. **The drop becomes home.** Rewrite `NotchView` to the canvas board "A · the drop + the puck":
   - solid #000, one piece with the notch, lower corners 36, inverse flares where it meets the menu bar
   - header: `the drop · 09:18` label and the solid wordmark
   - a row of 12 circles: the eleven agents (`sheetInk` at rest, paper when they have something new) and the 11 listening button with its two rings
   - notices: white cards, 12pt corners, ink and open pills
   - live (agent circle + progress dots), shelf (file chips, drop on an agent's open ring)
   - open row: one pill per app, paper when its window is open
   - ask bar: `sheetInk` pill, `hold fn to talk`
   - states: idle (the notch with the active agent and a countdown), open, listening (the drop stretches and shows the 11 with its halo, the sentence in Schibsted, routing chips)
   `NotchController` keeps its idle / peek / open logic; add `listening`.
2. **The puck.** Replace the ⌥Space ask panel with a borderless, non-activating `NSPanel` that is round (clear background, so clicks outside the disc fall through), draggable, snaps to screen edges, and remembers its spot. 96pt ink disc with the 11 and a count chip. Hold Fn (or ⌥Space) to talk: the halo spreads (`halo` token, 14pt blur), and the puck opens a note with the transcript, routing chips and results (Undo, Send, Edit). Let go to send, Esc to cancel.
3. **Apps open as their own windows.** Replace the single `WindowGroup("11am", id: "main")` with `WindowGroup(id: "app", for: AppSection.self)` and `openWindow(value:)`, so every app (Mail, Calendar, Today…) is its own window. Window chrome: lifted white card with `liftHi`, an ink title bar in Courier (`marc · mail`) and a ×. Remove `Sidebar` and `AgentPane`; the agent shows in the title bar label and in notes. ⌘1…⌘9 open app windows.
4. **Today** is a window with the overprint opener (canvas board "D · overprint").
5. **The lens** (later). A round panel that reads what is under it needs Screen Recording permission and Vision OCR, or the Accessibility API. Prototype after phases 1 to 3 ship.

## Phase 4: iPhone

- Same fonts, monograms, texture and tokens (share `Tokens.swift` through `Shared/`).
- Home is the drop: true black, a 6 × 2 grid of circles (the twelfth is the 11), white notices, an open row of pills, `hold the 11 to talk`.
- Live Activity and Dynamic Island: compact shows the active agent's circle and a countdown; expanded shows the 11 with its halo while listening.
- Lock screen: the puck replaces the torch control (Control Center control / Action button intent), notifications as notes led by monograms.
- Apps as screens with the ink Courier title bar and `pull down for the drop`; the puck small in the corner.
- Exceptions Liam approved on the canvas: notification corners 22, swipe row corners 16, centred lock-screen clock. Add these to the design system as iPhone exceptions.

## Phase 5: checks

- Regenerate the snapshot shots (`ci/sandbox-shots`) for every app in both themes.
- Add a brand lint to CI that fails on: `Color(red:`, `.accentColor`, `.tint(`, `.gray`, `.opacity(` on text, `.uppercased()` on labels, `Image(systemName:` outside an allow-list, literal corner radii, `.font(.system`.
- Accessibility: every target 44pt, focus rings kept, reduced motion stops the halo, the glitch and typing, ink on `note` over ink checked for contrast.

## Decisions for Liam

1. **SF Symbols.** Remove everywhere, or keep a small allow-list for editor toolbars and media transport (play, record) in Video, Audio, Sheets and Docs, drawn as 1.5pt line icons?
2. **Dark mode.** Follow the system into the ink theme, or stay on paper with ink panels only?
3. **Window buttons.** Keep the native traffic lights for accessibility and muscle memory, or the ink title bar with × only?
4. **Recording.** v1 docs allowed red for recording. Brand v2 has no colour: an ink dot that fills and pulses?
5. **Transition.** Keep the old main window behind a setting while the per-app windows land, or switch in one go?

## Suggested order and size

| Phase | Work | Rough size |
|---|---|---|
| 0 | Fonts, monograms, texture, tokens | 1 session |
| 1 | Theme, surfaces, shape | 1 to 2 sessions |
| 2 | Components, then one app as the reference (Mail) | 2 sessions |
| 3 | The drop, the puck, per-app windows | 2 to 3 sessions |
| 2b | Sweep the remaining 20 apps onto the components | 4 to 6 sessions, can run in parallel |
| 4 | iPhone | 2 sessions |
| 5 | Lint, shots, accessibility | 1 session |

## Where it stands

**Decisions (Liam, November 2026).** Icons stay everywhere, drawn in the brand's 1.5pt line where 11am has to make its own (every app has one now; actions keep SF Symbols in ink until their line versions exist). Dark mode follows into the ink theme. Restyle first, then the headless structure. Native traffic lights stay. Recording: an ink dot that fills and pulses (to confirm).

**Shipped in 0.30.0.** Phases 0 to 2 across every app in the current window: fonts, `BrandTokens.swift`, monograms with the new codes (older codes still draw, so saved data keeps working), the 11 tile as the app icon, the tracing-paper tooth, paper and ink themes, full-strength text, square lifted surfaces, pills, Courier chips and labels, lifted fields, circle checkboxes and pill toggles, a Hack caret for loading, ink in place of the accent colour, and the Write and Notes editors in brand type.

**0.31.0.** Line versions of about 80 action icons (close, add, share, undo, search, play, lock and the rest), drawn like the app icons and sized by the font like a symbol; 158 places use them, and anything not yet drawn stays an SF Symbol in ink.

**0.32.0.** Phase 3, the drop and the puck. The drop: true black with 36pt lower corners, `the drop · 09:18` and the solid wordmark, the eleven agents and the 11 as circles (sheet-ink at rest, white with something new), white notices (12pt corners) with an ink pill, a live row counted in dots, an open row of app pills, and the sheet-ink ask bar; asking stretches it to listen (the 11 with its halo, the sentence in Schibsted, routing chips, the answer on white). The puck: a round, draggable, edge-snapping, remembered panel with the 11 on ink and a count chip; hold it or ⌥Space to talk (on-device speech), click to type; a vellum note with the transcript, routing chips and Send, Edit, Copy and Undo. The shelf (files dropped on an agent's ring) is still to come.

**0.33.0.** Phase 3, per-app windows and the shelf. Every app opens as its own window (`AppWindows`): a full-size transparent title bar with the native window buttons (decision 3), an ink bar with `marc · mail` in Courier, and the agent's circle, which opens a note to ask them and see the team's activity (⌘\\); the sidebar and the agent pane are gone from this layout. Windows remember their frames, the open set comes back at launch, ⌘1…⌘9 and an Apps menu open them, and the Dock icon brings back the last one. Decision 5 (transition): the earlier one window with a sidebar stays as a setting (Settings › This Mac › Windows). The shelf: a file dragged near the notch opens the drop with open rings on the agents who can take it (one table, tested on CI): Marc emails it (Mail now sends attachments), George files receipts or opens a spreadsheet, Robert a photo, Cole video or sound, Johnny a terminal, Bolton a PDF, a folder or a note, William and Conner documents, James sources, Leo tasks, and the 11 asks about it in the puck's note. Anything else waits on the shelf as chips you can drag back out.

**0.34.0.** Phase 3 item 4, Today's overprint opener (`Design/Opener.swift`, the guidelines' section opening): on the six-square grid, a two-by-two solid square with the day's number in Schibsted Black at 1.25 squares, the word outlined in Schibsted Black at 0.92 squares with a 1.4pt stroke across the last four squares of the first row, and a note two squares wide stepped half of (square + gap) right and down across both, carrying a Courier label (`monday · solve it`), a Schibsted heading (`Four meetings.`) and a line (what's next, what's due, whether the brief is ready). The word follows the ownership story by the shape of the day: keep it after 5 pm, build it when nothing is left on the calendar, solve it with three or more meetings left, own it otherwise (`OpenerKit`, tested on CI). The word and the note drift at 0.05 and 0.04 of the scroll, still under reduced motion. On the ink theme the square turns paper and the outline white. The square is up to 112pt, smaller in narrow windows.

**Next.** The remaining action icons, PDF print typography, then the iPhone (phase 4) and the brand lint (phase 5).
