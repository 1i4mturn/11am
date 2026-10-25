# robert: design

> **The one-liner:** Robert gives everything you make a considered look. A brand kit every agent uses, quick on-brand graphics, image tools and honest design critique.
> **Package:** Add-on · **Monogram:** `rt` · **App name:** *Robert*

## Role in the team
Robert is taste and visual execution. He keeps your **brand kit** (logo, colours, type, imagery style, voice link to William) and makes sure every visual the team produces uses it: Conner's decks, George's charts, William's PDF exports, Cole's titles, Johnny's mini-apps. He makes graphics, edits images, generates imagery when useful, and critiques designs bluntly. He's also custodian of 11am's own design system.

## Replaces / enhances
Canva (social graphics, simple layouts), light Photoshop (crop, background removal, adjustments, upscale), light Illustrator (simple vector, logo tidy-ups), Pinterest/Are.na (moodboards), brand-guideline PDFs, image generators (Midjourney/DALL·E/Firefly for occasional use).

## Use cases
1. **Brand kit once, used everywhere:** set your logo, palette, fonts and photo style. Decks, PDFs, charts and social posts all follow it automatically.
2. **Social graphics:** *"Announcement graphic for the enterprise launch, LinkedIn and Instagram sizes."* You get 4 on-brand variants per size from templates, with copy from William, editable on the canvas.
3. **Image clean-up:** remove the background from a product photo (Apple Vision subject lifting), straighten, crop to sizes, upscale, colour adjust. Batch it across 40 photos.
4. **Generate when useful:** hero image or illustration in your brand style, local (Tier C+) or cloud, with the model and licence noted.
5. **Critique:** drop in a slide, landing page screenshot or poster and ask "what's wrong with this?" You get specific notes on hierarchy, alignment, contrast and clutter (vision model), with suggested fixes applied as a variant.
6. **Moodboard:** *"References for a calm, editorial fintech look."* James gathers references, Robert curates a board and extracts a palette and type pairings.
7. **Logo concepts and audits** (ported): directions, then a vector tidy-up of the chosen one.
8. **Device mockups:** place screenshots into device frames for the website and decks.

## Features

### v1 (MVP)
- **Brand kit:** logos (SVG/PDF/PNG variants), palette, type (font files or system fonts), spacing scale, imagery style notes, do/don't examples; exported as tokens (JSON) consumed by every agent; brand voice linked to William.
- **Canvas:** artboards (social sizes, slides, A4, custom), shapes, text, images, frames, alignment and distribution, smart guides, layers list, grouping, simple masks, export (PNG/JPG/SVG/PDF), templates.
- **Templates:** social posts, story, banner, quote card, announcement, event, thumbnail; each brand-aware.
- **Image tools:** subject lift / background removal (Vision), crop and resize presets, straighten, adjustments (Core Image: exposure, contrast, tone, B&W, grain), upscale (Core ML model), batch processing.
- **Generate:** text → image and image → variants via the image provider layer (local `mflux` on Tier C+; cloud providers by consent); always labelled.
- **Critique:** a vision model reviews a design with structured feedback and optional auto-fix variants.
- **Ported tools:** brand direction, colour/typography recommendations, brand system doc, moodboard, logo concepts, brand audit, competitor landscape, implementation brief.

### v2
- **Moodboards** with James (references, palette extraction, type pairing).
- **Deck themes** for Conner (layouts, chart styles) and **PDF themes** for William (Typst).
- **Batch variants** (A/B creatives in sizes).
- **Motion hand-off** to Cole (title cards, lower thirds as motion templates).
- **Device mockups.**

### Later
- Text → editable vector (SVG generation).
- Photo layers and non-destructive edits (a Pixelmator-lite).
- iPad with Pencil (PencilKit).

### Not building
- Photoshop-grade compositing, brushes, retouching.
- Figma-grade product design or prototyping.
- Print prepress (CMYK proofing, imposition).
- A stock photo library (link to Unsplash/Pexels APIs at most).

## How the AI is involved

| Feature | Task class | Autonomy | Trigger |
|---|---|---|---|
| Template fill + layout | `draft.medium` → **layout JSON** → deterministic layout engine (constraints) | Variants (L0) | Ask |
| Background removal | Apple Vision (no LLM) | L3 | Command |
| Upscale | Core ML model | L3 | Command |
| Image generation | Image provider (local mflux / cloud) | L0 (variants) | Ask |
| Critique | `vision.large` (local VLM Tier D+, Apple FM image input for light checks, cloud by consent) | L0 | Ask / drop |
| Palette extraction | k-means (code) | L3 | Image added |
| Brand compliance check | Deterministic (colours, fonts, contrast) + `vision.small` | L0 (warnings) | Export |
| Brand direction / logo concepts | `reason.large` + image gen | Draft | Ask |

## Works with
- **Conner:** deck themes and slide polish.
- **William:** copy for graphics; PDF export themes; brand voice link.
- **Cole:** brand in motion, title cards, thumbnails.
- **George:** chart styles.
- **James:** references and competitor visuals.
- **Johnny:** design tokens for mini-apps.
- **Bolton:** asset library (logos, photos, exports).

## Design and visual identity
- **Pattern:** registration and crop marks.
- **Motion:** crosshair snaps to centre when aligning or finishing a variant.
- **The canvas** is neutral (light grey or a checkerboard for transparency); the user's colours live there. 11am's chrome stays monochrome.
- **Tone:** confident and specific. "The headline and logo compete. Drop the logo to 60% size and align it to the baseline grid."

### Wireframe: canvas
```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ rt  Enterprise launch · LinkedIn 1200×627             brand: 11am ▾   export ▾   │
├──────┬───────────────────────────────────────────────────────────┬───────────────┤
│ ▢    │                                                           │ robert        │
│ T    │      ┌─────────────────────────────────────────┐          │ Variants      │
│ ◯    │      │                                         │          │ [1][2][3][4]  │
│ ▣    │      │   Your team, now for teams.             │          │               │
│ ✂    │      │                                         │          │ Critique      │
│ ⌖    │      │   [ product image · subject lifted ]    │          │ ─ headline    │
│ ⇲    │      │                              11am ▪     │          │   strong      │
│      │      └─────────────────────────────────────────┘          │ ─ logo too    │
│ ──   │                                                           │   close to    │
│layers│   Sizes: LinkedIn ✓ · Instagram 1080² ✓ · Story ✓         │   edge (8px)  │
│      │                                                           │ fix ▸         │
├──────┴───────────────────────────────────────────────────────────┴───────────────┤
│ ⌘K · ⌘J ask robert · ● on-device · image: mflux (local)                          │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Wireframe: brand kit
```
╭─ brand kit · 11am ───────────────────────────────────────────────────────╮
│ Logo      [11am wordmark] [monogram] [mono light] [mono dark]            │
│ Palette   ■ #0A0A0A ink   □ #FFFFFF paper   ▒ glass   (accent: none)      │
│ Type      Alte Haas Grotesk (display) · SF Pro (text)                    │
│ Imagery   monochrome, high contrast, grain 6%, no stock smiles           │
│ Voice     → william: "calm, short, Australian spelling"                  │
│ Used by   decks (cr) · PDFs (wm) · charts (ge) · titles (co) · mini-apps │
╰──────────────────────────────────────────────── export tokens.json ▸ ───╯
```

## Usability
- **Shortcuts:** standard design-tool keys (V select, T text, R rect, O ellipse, ⌘G group, ⌘⇧H flip, ⌥ drag duplicate, ⌘; guides) · ⌘J ask · ⌘⇧C critique · ⌘E export.
- **Onboarding:** "Do you have a brand?" Upload the logo and website URL; Robert extracts palette and fonts (James fetches) and proposes a kit. Otherwise run brand direction to create one.
- **Variants, not replacements:** AI always produces variants alongside your design, never overwriting it.
- **Licence labels** on generated images (model, licence, commercial-use status).
- **Empty state:** crop-marks pattern; "Start from a template or drop an image."

## Notch and iPhone
- **Notch:** "4 variants ready", generation progress, drop target ("rt edit image").
- **iPhone:** capture references (camera, screenshots), quick crops/background removal, approve variants, **Continuity Camera** straight into the Mac canvas.

## Mac integration
Core Image · Vision (`VNGenerateForegroundInstanceMaskRequest` subject lifting, saliency for smart crops) · Core ML (upscalers) · Metal (canvas rendering when needed) · Core Graphics / SwiftUI `Canvas` + `ImageRenderer` (render/export) · ColorSync · Core Text (font handling; user-installed fonts) · Continuity Camera (`NSMenuItem.importFromDeviceIdentifier`) · Image Playground / ImageCreator API (Apple's on-device image generation, check availability and style limits) · Quick Look · App Intents ("Make a graphic for…", "Remove background").
**Permissions:** Photos (optional import), Camera (iPhone).

## Backend
- **Rust `core/robert`:** design document model (scene graph JSON: artboards, nodes, styles, constraints), brand kit store + tokens export, layout engine (constraint-based placement for templates; shared with Conner's deck renderer), template registry, asset library index, generation job queue (provider adapters: local mflux helper process, cloud APIs), compliance checker (palette distance, font usage, WCAG contrast), palette extraction.
- **Rendering:** v1 in Swift (Core Graphics/SwiftUI Canvas) for speed of development; v2+ consider Rust `vello` for a portable, GPU-accelerated renderer.
- **Tables:** `brand_kits(id, name, tokens_json, assets_json, voice_profile_id)`, `designs(id, path, kind, artboards_json, updated_at)`, `templates(id, kind, sizes, spec_json)`, `assets(id, blob_ref, kind, tags, source, licence)`, `generations(id, prompt, provider, model, licence, outputs_json, cost)`, `critiques(id, design_id, notes_json, model)`.
- **Port from current repo:** `apps/robert/src/lib/design/engine.ts` (all `run*` functions), `components/BrandSystemDisplay.tsx`, `lib/images/openai.ts` (as one cloud provider).

## Lower-end Macs
- **Tier A/B:** canvas, templates, Vision tools, Core Image adjustments, exports: all local and fast. Image generation: cloud (consent) or Apple Image Playground where suitable; **no local diffusion under ~24 GB**. Critique: Apple FM image input (light) or cloud.
- **Tier C:** local generation possible but slow (quantised FLUX-class models via mflux).
- **Tier D+:** local generation practical; local VLM critique.

## Open source to study
`GraphiteEditor/Graphite` · `penpot/penpot` · `excalidraw/excalidraw` · `linebender/vello`, `kurbo`, `resvg` · `filipstrand/mflux` · `facebookresearch/sam2` · `xinntao/Real-ESRGAN` · `lokesh/color-thief` · `danielgatis/rembg` (Vision is better natively) · `comfyanonymous/ComfyUI` (GPL; separate process for power users) · `tldraw/tldraw` (custom licence: reference only).

## Tunable by Johnny
Templates and sizes; brand rules (which colours on which backgrounds, logo clear-space); export presets (naming, formats, folders); critique checklist; which image providers are allowed.

## Risks and open questions
- **Canvas scope creep:** v1 is a layout tool, not Illustrator. Hold the line.
- **Image model licences** (several FLUX variants are non-commercial). Record licences in the registry and default to commercially safe models.
- **Brand extraction accuracy** from websites. Always show and confirm.
- **Open question:** Swift vs Rust renderer. Recommendation: Swift first; extract to vello only when performance or cross-platform needs justify it.

## Build checklist
- [ ] Brand kit model + UI + tokens export consumed by William/Conner/George
- [ ] Canvas v1 (artboards, shapes, text, images, guides, layers, export)
- [ ] Templates (social sizes) + layout engine
- [ ] Vision tools (subject lift, smart crop) + Core Image adjustments + upscale + batch
- [ ] Image provider layer (cloud first, mflux helper for Tier C+)
- [ ] Critique (vision) + fix variants
- [ ] Port brand direction / logo concepts / audit / landscape tools
- [ ] Compliance checker on export
- [ ] v2: moodboards, deck/PDF themes, batch variants, motion hand-off, device mockups
