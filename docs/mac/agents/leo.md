# leo: chief of staff

> **The one-liner:** Leo turns everything happening across your team and your calendar into one calm plan, then keeps it moving.
> **Package:** Core · **Monogram:** `le` · **App name:** *11am Today* (Leo's app) · **Home of:** the notch, the Ask bar, Approvals, the check-ins

## Role in the team
Leo is the front door and the conductor. He routes your asks to the right specialists, sequences multi-agent work, owns your time (calendar, tasks, meetings), and turns the team's activity into briefs. He doesn't do the specialists' work. He makes sure it happens and that you only see what matters.

## Replaces / enhances
Calendar, Reminders, Fantastical, Sunsama/Motion (daily planning), Granola/Otter (meeting notes), Notification Center noise, part of Spotlight/Raycast ("do" queries), and "Siri for work".

## Use cases
1. **Morning brief (07:00–09:00, configurable):** today's meetings with prep status, what the team did overnight, the three things that matter, approvals waiting.
2. **The 11am check-in:** done / waiting on you / re-planned afternoon. Delivered in the notch, as a notification and on iPhone.
3. **"Prep me for my 2pm":** a prep card pulling Marc (recent threads with attendees), Bolton (last notes, decisions), James (company/person brief), George (numbers if it's investors).
4. **Multi-agent projects:** *"I need an investor deck by next Thursday"* → Leo plans: James (market data), George (financial slides), Conner (narrative), Robert (design), William (copy). It tracks progress with a deadline and nudges as needed.
5. **Meeting capture:** record (system audio + mic, local), transcribe, summarise, extract actions into tasks, log decisions to Bolton, draft follow-ups via Marc.
6. **Protect focus:** "keep 2 hours of deep work daily". Leo proposes moving meetings (drafts via Marc, approval required).
7. **Scheduling assistant:** "find 30 minutes with Sarah next week". Leo finds slots (deterministic solver) and Marc drafts the email with options.
8. **Evening wrap / weekly review:** what got done, what slipped, next week's shape.

## Features

### v1 (MVP)
- **Today:** a timeline of calendar events (EventKit: every account on the Mac), tasks (Reminders sync), live agent jobs, deadlines from other agents.
- **Calendar:** day/week views, create/edit events (approval when others are invited), time-zone aware.
- **Tasks:** lightweight; synced with Apple Reminders lists; due dates, projects, agent-created tasks clearly marked.
- **Ask bar (global ⌥Space):** natural language → router → agent(s). Shows routing live ("→ james + george").
- **Router:** rules + embeddings (`semantic-router` style) + small model fallback; multi-agent plans for complex asks.
- **Briefs:** morning (optional), **11am check-in** (default on), evening wrap (optional).
- **Approvals:** the cross-agent queue (window + notch page + notifications + iPhone).
- **Activity:** the team log with undo and filters per agent.
- **Meeting prep cards:** auto-generated 30 minutes before meetings with external attendees.
- **Notch owner:** Now / Approvals / Shelf / Ask pages; ears; live activities.

### v2
- **Meeting recorder:** Core Audio process taps / ScreenCaptureKit audio + mic; WhisperKit + SpeakerKit (diarisation); notes, actions, decisions; consent reminder.
- **Scheduling assistant** with Marc-drafted proposals.
- **Projects:** multi-agent plans as a lightweight timeline (milestones, owners = agents or you, dependencies).
- **Focus protection rules** and **Focus mode** integration (`SetFocusFilterIntent`).
- **Weekly review** and simple goals (with Conner's OKRs).
- **Voice conversation mode** (hold Fn, talk back and forth).

### Later
- Travel days (time zones, itinerary from Marc emails).
- Delegation to real humans (assign a task to an assistant or contractor via email, track it).
- Location-aware reminders (iPhone).

### Not building
- A team project-management tool (Jira/Asana/Linear).
- Booking pages (link out to Cal.com/Calendly if needed).
- Calendar account administration (macOS handles accounts).
- Habit trackers, gamified productivity, Pomodoro timers (template material at most).

## How the AI is involved

| Feature | Task class | Autonomy | Trigger |
|---|---|---|---|
| Routing | `classify.small` (+ embeddings) | L3 | Every ask |
| Multi-agent planning | `reason.large` (cloud if allowed) / `summarise.medium` | L2 (plan shown, editable) | Complex asks |
| Briefs and check-ins | `summarise.medium` over the event log | L3 (delivered) | Schedule |
| Prep cards | `summarise.medium` + context packs | L3 | 30 min before meetings |
| Meeting notes | `transcribe` + `summarise.medium` | L2 (notes saved), L1 (follow-up emails) | Recording ends |
| Scheduling | LLM extracts constraints → **deterministic slot solver** → Marc drafts | L1 | Ask |
| Focus protection | Rules + solver; LLM writes reschedule notes | L1 | Calendar changes |
| Task extraction | `extract.small` | L2 | Events from other agents |

Principle: **Leo never does arithmetic on time with an LLM.** Slots, durations and time zones are code.

## Works with
- **Gets from everyone:** events (the log), deadlines, commitments, job progress.
- **Gives:** routed tasks, schedules, briefs, prep requests (James, Marc, Bolton, George), follow-up drafts (Marc), study blocks (Harris), recordings (Cole's engine).

## Design and visual identity
- **Pattern:** 12 clock ticks with the hand resting at 11.
- **Motion:** a quarter-turn hand sweep that settles at 11 while routing or briefing.
- **Tone:** calm, short sentences, verbs first. "Moved your 2pm to Thursday. Marc drafted the note."

### Wireframe: Today
```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ le  today · tue 28 oct                          ⌕ Ask the team…           ◐  ⋯  │
├────────────────┬───────────────────────────────────────────────┬─────────────────┤
│ Today          │  11:00 check-in ─────────────────────────────  │ leo             │
│ Week           │  Done        4 replies sent · contract filed   │                 │
│ Tasks       6  │  Waiting     pricing copy (wm) · supplier (jm) │ Next: investor  │
│ Projects    2  │  Afternoon   deep work 13–15 · sync → thu      │ call in 45 min  │
│ Meetings       │                                                │ prep ready ▸    │
│ Approvals   2  │  ─ timeline ─────────────────────────────────  │                 │
│ Activity       │  09:00 ▌Investor call · Sarah Lee   prep ✓     │ Ask leo…        │
│                │  10:30   Contract renewal (bn)                 │                 │
│ + Tune…        │  13:00 ▌Deep work (protected)                  │ ─ activity ─    │
│                │  15:30 ▌Design review · Robert brief           │ 08:12 routed ↩  │
│                │  ◯ jm  researching payroll tools  18/30        │ 08:10 moved  ↩  │
├────────────────┴───────────────────────────────────────────────┴─────────────────┤
│ ⌘K · ⌘J ask leo · ⌘⇧A approvals (2) · ● on-device                                │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Wireframe: prep card
```
╭─ prep · investor call · 09:00 ─────────────────────────────────────╮
│ Sarah Lee · Partner, Northfield Ventures                           │
│ Last contact   12 Oct (✉ "Following up on the deck")               │
│ Open threads   asked for churn by cohort (not yet sent)  → ge      │
│ Their news     closed Fund III, A$120m (jm · 2 sources)            │
│ Your notes     "wants to see 3 months of >10% MoM" (bn · 3 Sep)    │
│ Numbers        MRR A$48.2k · burn A$31k/mo · runway 14.2 mo (ge)   │
│ Suggested      bring cohort chart · ask about follow-on reserves   │
╰────────────────────────────────────────── open one-pager ▸ ───────╯
```

## Usability
- **Shortcuts:** ⌥Space Ask · ⌘⇧A Approvals · ⌘T new task · ⌘N new event · ⌘1 Today · ⌘2 Week.
- **Onboarding:** "Meet your team" (11 cards, monogram + one line each) → connect calendars (EventKit) → pick the check-in time (default 11:00) → choose brief style (bullet / prose / minimal).
- **Empty state:** clock pattern; "Leo's ready. Your first check-in is at 11:00."
- **Trust:** every brief line links to its source event; "why" on every reschedule suggestion.
- **Quiet by default:** only approvals, imminent meetings and the check-in interrupt.

## Notch and iPhone
- **Notch:** owner. Ears show the working agent and the approvals count / next meeting countdown. Live states for recording and long jobs.
- **iPhone:** Today tab (brief + timeline), check-in notification, Live Activity for meetings ("in 12 min" → "recording 12:41") and long jobs, widgets (next meeting, approvals), Action button → Ask Leo, in-person meeting recorder.

## Mac integration
EventKit (calendars, reminders) · UserNotifications (actionable) · App Intents ("Ask Leo", "What's next", "Start meeting notes") · `SetFocusFilterIntent` · Core Audio process taps / ScreenCaptureKit (meeting audio) · AVFoundation (mic) · WhisperKit/SpeakerKit · `SMAppService` · MenuBarExtra · KeyboardShortcuts · NSPanel (notch, Ask bar).
**Permissions:** Calendars, Reminders, Notifications, Microphone + Screen & System Audio Recording (meetings, v2).

## Backend
- **Rust `core/leo`:** router (rules → embeddings → model), planner (task DAG with JSON schema), brief generator (event-log windows), slot solver (interval maths over calendar busy blocks + constraints), project tracker, check-in scheduler.
- **Tables:** `tasks(id, title, notes, due, project_id, source_agent, reminder_id, status)`, `projects(id, title, deadline, plan_json, status)`, `project_steps(id, project_id, agent, task, depends_on, status, job_id)`, `briefs(id, kind, window_start, window_end, content_md, sources)`, `meetings(id, event_id, recording_blob, transcript_id, summary_md, actions_json)`, `routing_examples(id, text, agents, corrected)`.
- **Swift:** EventKit adapter (provides calendars and busy times to Rust via callback), notch UI, Ask bar UI, recording pipeline (v2).
- **Port from current repo:** `apps/leo/src/lib/plan/{daily,meeting,ops}.ts`, `lib/agents/{ask,invoke,contract}.ts`, `lib/schedule/runner.ts`.

## Lower-end Macs
- **Tier A:** routing via rules/embeddings + Apple FM; briefs generated when on AC (or the 11am one from a smaller model with a terser format); meeting notes after the meeting with Whisper small; no live transcription.
- **Tier B:** everything except live meeting transcription (post-meeting only).
- **Tier C+:** live transcription and notes during the meeting.

## Open source to study
`MrKai77/DynamicNotchKit` (notch) · `aurelio-labs/semantic-router` (routing) · Hyprnote and Meetily (meeting notes, licences to check) · `johannesjo/super-productivity` (day planning) · `calcom/cal.com` (slot logic, AGPL: study only) · `fmeringdal/rust-rrule`, `zslayton/cron`, `chronotope/chrono-tz` · `argmaxinc/argmax-oss-swift` (WhisperKit/SpeakerKit).

## Tunable by Johnny
Brief format, sections and time; check-in cadence; routing rules ("anything mentioning invoices → George"); task views (by project, by agent); what counts as "needs you"; prep card fields; focus rules.

## Risks and open questions
- Brief quality on Tier A. Mitigate with templates + structured data and less free text.
- Meeting recording consent and legality vary by region. Show reminders and support a "notes only, no audio kept" mode.
- Router mistakes erode trust. Show routing before execution for multi-agent asks, and learn from corrections.
- **Open question:** should the Today view replace Calendar.app fully? Recommendation: yes for viewing and planning, but leave account management to macOS.

## Build checklist
- [ ] EventKit adapter + calendar/reminder sync into core
- [ ] Today timeline UI
- [ ] Task model + Reminders two-way sync
- [ ] Router v1 + eval (≥ 90% top-1)
- [ ] Ask bar + routing preview
- [ ] Approvals queue (core + UI + notifications)
- [ ] Activity feed with undo
- [ ] Brief generator: morning, 11am, evening
- [ ] Prep cards (Bolton now; Marc and James when available)
- [ ] Notch v1 (pages: Now, Approvals, Shelf, Ask)
- [ ] v2: recorder, scheduling assistant, projects, focus rules, weekly review
