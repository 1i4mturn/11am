# harris: learning

> **The one-liner:** Harris helps you get sharper without the homework vibes. Learning paths built from your goals and your own work, in ten-minute sessions.
> **Package:** Add-on · **Monogram:** `hr` · **App name:** *Harris*

## Role in the team
Harris manages learning: study paths, practice, spaced repetition, languages and reading. What makes him different from Duolingo or Anki is **context**. He knows your goals (Leo, Conner), your work (Bolton), your numbers (George) and your gaps, so lessons use *your* examples, and cards come from things you actually read and saved.

## Replaces / enhances
Anki (flashcards), Duolingo (light language practice), Blinkist (book summaries), Kindle/Books highlights review, course note-taking, "learn X" YouTube rabbit holes, Readwise (highlights resurfacing).

## Use cases
1. **Crash course:** *"I need to understand SaaS metrics before Friday's board meeting."* Harris builds a 4-session path (sources from James, examples from George's real numbers), with a 5-question check at the end. Leo schedules 20-minute blocks.
2. **Cards from your life:** highlight a passage in Bolton or James, or save a definition, and it becomes a flashcard (with the source). Reviews use FSRS scheduling.
3. **French (or any language):** a daily 10-minute session with vocabulary from your interests, listening (TTS), **speaking drills** with transcription feedback (WhisperKit), and conversation practice with a tutor persona. Ports the existing `/french`.
4. **Explain at my level:** select anything in any agent and use "Explain this", tuned to what you already know (ports `/explain`).
5. **Skill gaps:** from your goals and recent work, Harris suggests what to learn next (ports `/skill-gaps`, `/gap-plan`), *gently* and opt-in.
6. **Reading plan:** books and long articles with summaries, discussion questions and highlights that turn into cards.
7. **Learn from your work (opt-in):** "You've looked up VLOOKUP 3 times this month. Want a 5-minute lesson on XLOOKUP and George's 'formula from English'?"
8. **Weekly recap:** what you learned, what's due, streaks *without* guilt mechanics.

## Features

### v1 (MVP)
- **Learning paths:** goal → roadmap (modules, sessions) → lessons generated with sources (James) and your context (Bolton/George); ports `generateLearningPlan`, `generateRoadmap`.
- **Lessons:** a clean reader with "explain this", inline questions and examples; each lesson ≤ 10 minutes.
- **Practice:** quizzes, exercises, short written answers with feedback (ports `generateExercises`).
- **Flashcards:** FSRS scheduling, card types (basic, cloze, reverse, image), cards from highlights in any agent, a review session (keyboard-first).
- **Language mode:** vocabulary, phrases, listening (TTS), speaking drills (WhisperKit with pronunciation hints from transcription mismatch), daily session.
- **Today:** "10 minutes today" (due cards + next lesson step), with notch quick review.
- **Progress:** gentle (minutes, cards known, paths completed); streaks optional and off by default.

### v2
- **Reader:** EPUB/PDF library (Readium), highlights → cards, chapter summaries, discussion questions.
- **Conversation tutor** (voice, in the target language, with corrections).
- **Import courses:** YouTube transcripts, PDFs, slide decks → paths.
- **Learn-from-work suggestions** (opt-in, using the event log, never surveillance-y).
- **Apple Books highlights import** (local Books annotation database, needs Full Disk Access; check feasibility per macOS version).

### Later
- Exam/certification prep mode.
- Shared decks import (Anki .apkg import).
- Apple Watch quick reviews.

### Not building
- A course marketplace or video course hosting.
- Kids' education.
- Leaderboards, social learning, gamified currency.
- Full-language-curriculum competition with Duolingo (Harris is a companion, not a school).

## How the AI is involved

| Feature | Task class | Autonomy | Trigger |
|---|---|---|---|
| Path planning | `reason.large` / `draft.medium` with sources from James | Draft (you edit) | Ask |
| Lesson generation | `draft.medium` grounded in sources (citations shown) | Draft | Path step |
| Card generation | `extract.small` (from highlights/notes) | L1 (suggested cards) → L2 if enabled | Highlight saved |
| Scheduling | **FSRS (deterministic)** | L3 | Reviews |
| Grading answers | `classify.small`/`summarise.medium` with rubric | L3 (feedback) | Answer submitted |
| Speaking feedback | WhisperKit transcript vs target + `summarise.small` hints | L3 | Drill |
| Tutor conversation | `draft.medium` (persona; target-language aware) | — | Session |
| Gap detection | Event-log patterns + `classify.small` | L0 (suggestion, opt-in) | Weekly |

**Hallucination guard:** lessons cite their sources. Factual lessons without a source are labelled "from the model's general knowledge", and a "check this" button sends claims to James.

## Works with
- **James:** sources and readings.
- **Bolton:** your notes and highlights as material; stores cards and progress.
- **Leo:** schedules study blocks; includes "learning" in the evening wrap.
- **George:** finance-literacy lessons with your real numbers (local only).
- **William:** writing practice and feedback.
- **Conner:** business skill gaps.
- **Cole:** your recordings as lesson material.

## Design and visual identity
- **Pattern:** a dotted path with step markers.
- **Motion:** the path fills dot by dot as sessions complete; cards flip with a soft spring.
- **Reading-first typography:** generous size and line height, Alte Haas for lesson titles, SF Pro or New York for body.
- **Tone:** encouraging, never guilt-trippy. "Nice. 8 cards done. That's enough for today."

### Wireframe: today
```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ hr  harris · today                                    ⌕ Ask harris…      ◐  ⋯   │
├───────────────┬──────────────────────────────────────────────────┬───────────────┤
│ Today         │   10 minutes today                               │ harris        │
│ Paths      2  │   ┌────────────────────────────────────────────┐ │               │
│  SaaS metrics │   │ ● ● ● ○ ○   SaaS metrics · session 4/5     │ │ Board meeting │
│  French B1    │   │ "Net revenue retention, with your numbers" │ │ Fri: you're   │
│ Cards     8   │   │                               start ▸  6m  │ │ on track.     │
│ Library       │   └────────────────────────────────────────────┘ │               │
│ Languages     │   ┌────────────────────────────────────────────┐ │ New cards     │
│ Progress      │   │ 8 cards due · 3 min              review ▸  │ │ from 2 notes  │
│ + Tune…       │   └────────────────────────────────────────────┘ │ add? ▸        │
│               │   ┌────────────────────────────────────────────┐ │               │
│               │   │ French · speaking drill · 4 phrases   ▸ 3m │ │               │
│               │   └────────────────────────────────────────────┘ │               │
├───────────────┴──────────────────────────────────────────────────┴───────────────┤
│ ⌘K · ⌘J ask harris · ● on-device                                                 │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Wireframe: notch quick review
```
   ╭────────────────────────────────────────────╮
   │ hr · 8 due                                 │
   │   "NRR"                                    │
   │   space: flip ·  1 again 2 hard 3 good 4 easy │
   ╰────────────────────────────────────────────╯
```

## Usability
- **Shortcuts (reviews):** space flip · 1–4 grade · E edit card · S suspend · ⌘⏎ check answer.
- **Onboarding:** "What do you want to get better at?" (pick or type) → session length (5/10/20 min) → languages (optional) → import highlights (optional).
- **Respect attention:** sessions end with a clear "done"; no notifications except an optional daily nudge at your chosen time.
- **Empty state:** dotted-path pattern; "What do you want to understand better?"

## Notch and iPhone
- **Notch:** quick review (flip cards right in the notch) and "8 cards due" ears (optional).
- **iPhone (primary surface for learning):** daily session, cards, speaking drills, listening during the commute, widgets ("8 due", word of the day: a borderline gimmick, so make it a Johnny template), Lock Screen widget, Watch later.

## Mac integration
Translation framework (on-device) · `AVSpeechSynthesizer` (and Kokoro via mlx-audio on higher tiers) · WhisperKit (speaking drills) · Readium Swift toolkit (EPUB) · PDFKit · App Intents ("Review my cards", "Explain…") · Services ("Make a card from selection") · WidgetKit.
**Permissions:** Microphone (speaking), Speech Recognition (if the system recogniser is used as fallback), Full Disk Access (Books import, optional).

## Backend
- **Rust `core/harris`:** paths (goal, modules, sessions, sources), lessons (Markdown + questions), cards + reviews with **FSRS** (`fsrs-rs`, licence check), language packs (vocab, phrases, audio cache), grading rubrics, gap detector (event-log queries), progress stats.
- **Tables:** `paths(id, goal, plan_json, status, deadline)`, `lessons(id, path_id, order, md, sources_json, done_at)`, `cards(id, deck, front, back, kind, source_ref, created_by)`, `reviews(id, card_id, ts, grade, stability, difficulty, due)`, `language_items(id, lang, text, translation, audio_ref, level)`, `attempts(id, kind, prompt, answer, feedback, score)`.
- **Swift:** reader, review UI, speaking drill (record → transcribe → compare), TTS adapter.
- **Port from current repo:** `apps/harris/src/lib/learning/engine.ts` (plan, roadmap, exercises, explain, gap plan, French help, SRS → FSRS), `lib/hub/store.ts`, `components/LearningHubPanel.tsx`.

## Lower-end Macs
- **Tier A:** cards and FSRS are trivial; TTS via AVSpeech; speaking drills with a small Whisper model; lesson generation via Apple FM (short) or cloud/overnight (paths pre-generated in Night shift).
- **Tier B+:** local lesson generation and tutor chat.

## Open source to study
`ankitects/anki` (AGPL: study card and scheduling UX) · `open-spaced-repetition/fsrs-rs` · `open-spaced-repetition/ts-fsrs` · `readium/swift-toolkit` · `koodo-reader/koodo-reader`, `readest/readest` (AGPL: reader UX study) · `Blaizzy/mlx-audio` / `hexgrad/kokoro` (voices) · `argosopentech/argos-translate` (fallback translation).

## Tunable by Johnny
Session length and composition; card templates; grading strictness; languages and levels; which sources Harris may use; weekly recap format; "learn from work" scope (off by default).

## Risks and open questions
- **Lesson accuracy:** source grounding and "check this" via James.
- **Motivation without gamification:** test gentle progress views with beta users.
- **Pronunciation feedback** from transcription is approximate. Label it honestly and improve later with phoneme-level models.
- **Open question:** is Harris compelling enough as a paid add-on alone? Consider bundling him into the Founder bundle as a sweetener, or into Core with a cards-only lite version.

## Build checklist
- [ ] Paths + lessons (ported generators) with sources
- [ ] Reader with explain-on-select
- [ ] Practice (quizzes, exercises, grading)
- [ ] Cards + FSRS + review UI + cards-from-highlights (Services, Bolton, James)
- [ ] Language mode: vocab, TTS listening, speaking drills
- [ ] Today view + notch quick review
- [ ] iPhone daily session + widgets
- [ ] v2: EPUB reader + highlights, tutor conversation, course import, learn-from-work, Books import
