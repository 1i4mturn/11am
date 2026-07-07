# Cursor Prompt — 11am Visual Rework

## Context

You are working on the 11am Next.js monorepo at `~/Projects/11am`.

**Stack:**
- Next.js 16 App Router, npm workspaces
- `apps/home` — suite portal at localhost:3010
- `apps/william`, `apps/marc`, `apps/bolton` — individual agents at 3000–3002
- `packages/ui` — shared design tokens, components, CSS
- Tailwind v4, Alte Haas Grotesk (TTF, loaded via `@font-face` in `packages/ui/src/styles/globals.css`)

**Key files:**
- `packages/ui/src/tokens/index.ts` — all design tokens and agent configs
- `packages/ui/src/styles/globals.css` — grain stack CSS, font-face, utility classes
- `packages/ui/src/styles/theme.css` — Tailwind v4 inline theme
- `apps/home/src/app/page.tsx` — homepage (suite portal), ~600 lines, `'use client'`
- `apps/home/src/app/globals.css` — full grain/motion CSS ported from prototype
- `packages/ui/src/components/AppShell.tsx` — shared header shell
- `apps/william/src/`, `apps/marc/src/`, `apps/bolton/src/` — individual app pages

**Design system (Robert v5 — do not deviate):**
- Colours: `#ffffff` base, `#faf9f7` warm bg, `#161616` titles, `#2f2f2f` graphite copy, `#6b6560` muted, `#e8e4dc` border
- Zero colour on the homepage — everything greyscale/tonal
- Emboss recipe: `drop-shadow(0 2px 0 rgba(255,255,255,0.88)) drop-shadow(0 -1.6px 1.8px rgba(118,108,98,0.46))`
- Grain stack: `bg-grain-coarse`, `bg-grain-fine`, `bg-grain-speckle`, `fg-grain`, `fg-speckle`, `grit` — all `mix-blend-mode: multiply` — already in `globals.css`, do not rebuild
- Type: Alte Haas Grotesk Bold for all display/headings (lowercase), AHG Regular for body
- Type classes: `am-title`, `am-copy`, `am-label`, `am-detail-title`, `am-detail-copy`, `am-detail-meta` — use these everywhere, never bare Tailwind strings like `text-sm font-medium`

---

## What already works (do not break)

- Physics engine in `apps/home/src/app/page.tsx`: drift, sway, edge steering, avoidCentreLogo elliptical repulsion, O(n²) inter-agent collision avoidance via `requestAnimationFrame`
- Cursor wash: 5-layer radial gradient following mouse position
- `detail-mode`: body class toggle — logo animates top-left, selected agent top-right, floating agents fade out
- All 11 agent SVG monograms are at `packages/ui/src/assets/logos/` and `apps/home/public/logos/`
- `scripts/launch.sh` starts all four apps and opens Chrome at localhost:3010

---

## Task 1 — Homepage motion: replace RAF with MotionOne

The current physics engine uses a raw `requestAnimationFrame` loop in `apps/home/src/app/page.tsx`. Replace this with **MotionOne** (`motion` npm package).

Install: `npm install motion -w @11am/home`

**Keep the same behaviour, just re-implement with MotionOne:**
- Slow independent positional drift per icon: ±1.5–2.5vw amplitude, 12–20s loop, each icon offset/desynced
- Soft edge steering as icons approach safe-area boundary or logo exclusion zone (soft ellipse: ~22% vw wide, ~30% vh tall)
- Light inter-icon collision avoidance — nudge trajectories apart gently, never a visible snap
- No rotation, no scale, no opacity flicker in idle state — positional drift only

**Hover state:**
- On cursor proximity within ~8vw of an icon, increase emboss contrast: darker offset shadow + brighter highlight — reads as the icon lifting toward the surface, not glowing
- On direct hover, fade in `name · role` label below icon: lowercase, AHG Bold, 8px, letter-spacing 0.2em, graphite `#2f2f2f`, fade over ~150ms, no slide or scale

**Click → detail transition (already partially working — refine with MotionOne):**
- Logo animates from centre to top-left over ~400–500ms
- Clicked icon animates from scatter position to top-right
- Other 10 icons fade to opacity 0 over ~200–300ms
- Detail content fades/slides up from below, ~80–120ms delay after logo starts moving
- Total transition: 400–600ms. Deliberate, not instant, never sluggish

**Reverse (detail → home):**
- Detail content fades out first
- Logo returns to centre, active icon fades back to scatter position
- Other 10 icons fade back in

---

## Task 2 — Cursor wash z-index fix

The cursor wash (5-layer radial gradient following mouse) must sit **beneath** the grain layer. Grain stays constant on top — only the light shifts underneath.

In `apps/home/src/app/globals.css`, confirm z-index ordering:
1. Base surface (`#faf9f7`)
2. Cursor wash layer
3. Grain stack (coarse, fine, speckle, fg-grain, fg-speckle, grit)
4. Agent icons and logo
5. Detail panel content

Fix if the cursor wash is currently above grain.

---

## Task 3 — App pages visual lift (William, Marc, Bolton)

For each of `apps/william`, `apps/marc`, `apps/bolton`:

1. **Replace all ad-hoc Tailwind type strings** (`text-sm font-medium`, `text-lg font-bold`, etc.) with the correct `am-*` class from `packages/ui/src/styles/globals.css`. Audit every `.tsx` file in `src/`.

2. **Cards:** replace flat `rounded-lg` / `rounded-xl` cards with the emboss treatment — subtle inset shadow, no hard borders unless there's a functional reason. Use soft shadow separation instead: `box-shadow: inset 0 1px 0 rgba(255,255,255,0.8), 0 1px 3px rgba(118,108,98,0.18)`.

3. **Buttons:** add emboss treatment and a pressed/active state:
   ```css
   /* rest */
   box-shadow: 0 2px 0 rgba(255,255,255,0.88), 0 -1px 2px rgba(118,108,98,0.3);
   /* active/pressed */
   box-shadow: inset 0 1px 2px rgba(118,108,98,0.25);
   ```
   No flat `hover:opacity-90`. No colour on hover.

4. **Editorial spacing:** increase vertical breathing room — minimum 32px between content sections, 48px on larger breakpoints. Content should not read as a CRUD panel.

5. **Bolton specifically:** heaviest lift — it is currently the most bare. Apply grain pass to cards: add `bg-grain-fine` class to card wrappers so they don't read as flat.

6. **AppShell header:** confirm `bg-surface/90 backdrop-blur-sm` reads correctly against the grain surface. Logo fixed size across breakpoints, no scaling jumps.

---

## Task 4 — William → Robert handoff panel

In `apps/william`, find the section that renders the Robert handoff output (currently a raw `<pre>` JSON block).

Replace with a structured card layout. Treat each field as a labelled entry using bracket-style labels:

```
[ copy ]         Long-form copy goes here...

[ platform ]     Instagram

[ format ]       Carousel

[ tone notes ]   Warm but direct. No em dashes.

[ visual direction ]  Editorial, no stock. Teller-esque.
```

- Labels: AHG Bold, 8px, letter-spacing 0.2em, muted `#6b6560`, uppercase
- Values: AHG Regular, 14px, graphite `#2f2f2f`
- Card: emboss treatment (see Task 3), `#faf9f7` background, generous internal padding (24px)
- No `<pre>`, no monospace font, no raw JSON visible to the user

---

## What NOT to do

- No colour — everything stays greyscale/tonal
- No hard-edged spotlight for cursor wash — must be soft, layered, multiple offset radials
- No icons snapping to grid or animating in sync
- No flat frosted-glass / translucent box UI
- No gradients without grain on top
- No uppercase for body copy (display headings lowercase is intentional)
- No icon-library icons — the monograms are the icon system
- No new npm dependencies beyond MotionOne (already specified above)
- Do not touch `packages/ui/src/tokens/index.ts` or the grain CSS classes
- Do not change port assignments (home: 3010, william: 3000, marc: 3001, bolton: 3002)

---

## References

- Robert — Design Direction brief: https://app.notion.com/p/394601c841da8157959dd0e81f13836d
- Johnny — Build Spec (homepage detail): https://app.notion.com/p/394601c841da81298b1cd37784eebde5
- Design Direction Hub: https://app.notion.com/p/391601c841da81b4bca5ed8aab3900ee

## Acceptance criteria

- [ ] MotionOne drives all homepage animation (no raw RAF loop remaining)
- [ ] Cursor wash sits beneath grain layer at all times
- [ ] Hover proximity lift works on all 11 icons, name/role label fades in on direct hover
- [ ] Click → detail transition completes in 400–600ms, reverse works cleanly
- [ ] No `text-sm font-medium` or similar bare Tailwind type strings in any app page
- [ ] Cards and buttons have emboss treatment, no flat borders
- [ ] Bolton cards have grain pass applied
- [ ] William handoff panel renders as structured bracket-label card, not raw JSON
- [ ] `npm run build` passes for all four apps with no errors
