# 01: Product: vision, principles, suite map

## The one-line pitch

**11am is a team behind you.** Eleven specialists live on your Mac and iPhone. Each one has its own app, all of them share one memory, and they work on their own between check-ins. They're tools, not people, and they're built so a founder or busy operator can do the work of a small company.

### Why "11am"
Lean into the name as a ritual. **At 11am every day, Leo runs the check-in.** By then the morning's email has landed, meetings have happened and the day has a shape. Leo says what's done, what's waiting on you, and re-plans the afternoon. The morning brief and evening wrap are optional; the 11am check-in is the signature. (Users can change the time, but the default is the brand.)

---

## What 11am is, and what it isn't

| 11am is | 11am isn't |
|---|---|
| A suite of real apps (mail, files, browser, docs, sheets, terminal…) with a brain built in | A chatbot with plugins (ChatGPT, Grok, "AI dots") |
| An AI-enhanced Microsoft 365 with the useful 20% of Adobe, for one person | Enterprise software rolled out to a company |
| Local-first: your data and most thinking stay on your Mac | A cloud service you rent your own data back from |
| Opinionated and finite: every app does the jobs a founder actually has | An everything-app with endless settings |
| Agents that work on their own inside clear limits and report back | Agents that act unpredictably or need babysitting |
| Calm: black and white, glass, typography, quiet motion | Gamified, colourful, notification-heavy |

### Who it's for
- **Primary:** solo founders and founders of small teams (1–15 people) who run sales, ops, finance, content and product themselves.
- **Secondary:** busy operators such as consultants, agency owners, creators with a business, and executives with no assistant.
- **Not for (v1):** whole-company rollouts, regulated enterprises needing admin consoles, Windows users.

### Jobs to be done (the real reasons someone pays)
1. "Keep me on top of everything without me having to look at everything." (Leo, Marc)
2. "Find anything I've ever seen, written, saved or been sent." (Bolton)
3. "Do the first 80% of the work, in my voice, so I only review." (William, Conner, Robert, Cole)
4. "Tell me what's true out there, with sources." (James)
5. "Tell me where the money is and where it's going." (George)
6. "Make the software fit how I work, without me coding." (Johnny)
7. "Help me get better at the things I'm bad at." (Harris)

---

## Principles (use these to settle every argument)

1. **The app is the interface, the agent is the engine.** Don't make people chat to get work done. Mail looks like mail, and Marc's intelligence shows up *inside* it as lanes, drafts, reasons and summaries. Chat (the Ask bar) is always available but never required.
2. **Show the work.** Every AI output says where it came from (sources, emails, files), which model made it (on-device or cloud), and what it changed. Provenance chips are everywhere.
3. **Ask before acting outside, act freely inside.** Drafting, sorting, summarising and filing happen automatically. Sending, paying, deleting, posting and booking ask first by default. See [autonomy levels](./03-ai-brain.md#autonomy-levels).
4. **Everything is undoable.** Every action goes in the activity log with an undo where physically possible. Moves keep a journal. Sends have an undo window.
5. **Local by default, cloud by consent.** Data classes (finance, private messages, health) never leave the device unless the user explicitly allows it per agent.
6. **Language for the LLM, logic for code.** LLMs read, write, classify and plan. Arithmetic, scheduling constraints, search ranking and file operations are deterministic code. LLMs never do maths or move files directly.
7. **Finite by design.** Each agent has a "not building" list. New ideas go through the gimmick filter. Cute things become installable Johnny templates.
8. **Calm technology.** Interrupt only for things that need you. Batch everything else into the check-in.
9. **Works on the cheapest supported Mac.** Every feature has a defined low-tier behaviour. If it can't run, it says so plainly and offers cloud or "overnight" mode.
10. **The user owns everything.** Notes are Markdown files. Mail is EML. Sheets export to xlsx and CSV. Memory can be exported as JSON. No lock-in.

---

## The suite map: everything you'd use a computer for

| Computer job | Owner | Replaces (80%) | Enhances (the brain) | Hands off to (the 20%) |
|---|---|---|---|---|
| Email | **Marc** | Mail, Outlook, Gmail web, Superhuman | Triage lanes, drafts in your voice, follow-up tracking, sender memory | Exotic accounts, S/MIME edge cases → Apple Mail |
| Messages | **Marc** | Messages (Mac) for reading/replying; Slack/Telegram triage | Unified per-person timeline, catch-me-up, reply drafts | FaceTime, group admin, stickers → Messages.app |
| Contacts / relationships | **Marc** (people) + **Conner** (deals) | Contacts, light CRM | Relationship memory, last-contact, "who should I reconnect with" | Contacts.app remains the system store |
| Calendar / tasks | **Leo** | Calendar, Reminders, Fantastical, Sunsama | Daily plan, check-ins, prep cards, scheduling assistant | Calendar.app for account admin |
| Meetings | **Leo** (with Cole's audio engine) | Granola/Otter | Local transcription, notes, action items to tasks | Zoom/Meet stay as the call apps |
| Launcher / command | **Ask bar** (Leo routes) | Spotlight/Raycast for "do" queries | Natural language to the right agent | Spotlight still finds apps |
| Files / finding | **Bolton** | Finder for finding and organising, Spotlight for search | Semantic search, auto-tidy, "about this file" | Finder for system ops (eject, permissions, Trash) |
| Notes / knowledge | **Bolton** | Apple Notes, Obsidian, Notion (personal) | Auto-linking, decisions log, memory | — |
| PDF / documents viewing | **Bolton** | Preview | Ask the document, extract, annotate | Preview for signing (or built-in later) |
| Clipboard / shelf | **Bolton** (notch shelf) | Maccy, Yoink, Dropover | Auto-file dropped items to the right agent | — |
| Browsing | **James** | Safari, Chrome (daily use) | Page Q&A, tab summaries, research jobs | Chrome for sites that need Chromium extensions |
| Search / research | **James** | Google, Perplexity, ChatGPT search | Deep research with citations, monitors | — |
| Writing / docs | **William** | Word, Pages, Google Docs (personal) | Voice-matched drafting, suggestion mode, rewrite anywhere | Word for heavy tracked-changes collaboration |
| Spreadsheets | **George** | Excel, Numbers (80% use) | Formulas from English, ask-your-data, clean-up | Excel for VBA/macros, huge models |
| Finance | **George** | Budgeting apps, Xero dashboards, Dext | Runway, forecasts, receipts matched, plain-English P&L | Xero/accountant remain the ledger of record |
| Slides / decks | **Conner** (story) + **Robert** (design) | PowerPoint, Keynote, Pitch | Outline-to-deck, brand themes, investor updates | Keynote for complex animation |
| CRM / pipeline | **Conner** | HubSpot/Pipedrive (solo use) | Auto-built from email/calendar, next-step nudges | Salesforce-scale teams |
| Strategy | **Conner** | Consultants' frameworks, Notion docs | Red-teaming, pricing, GTM | — |
| Design / images | **Robert** | Canva, light Photoshop/Illustrator | Brand kit everywhere, generate and edit, critique | Figma/Photoshop for pro work |
| Video / audio | **Cole** | CapCut, Descript, Loom, Voice Memos | Transcript editing, auto-clips, captions, clean-up | Final Cut/Resolve for pro edits |
| Learning | **Harris** | Anki, Duolingo (light), Blinkist | Paths from your goals, cards from your notes, speaking practice | Courses stay where they are |
| Terminal / scripts | **Johnny** | Terminal, iTerm, Warp | Natural language to commands, explain errors | Full IDEs (Xcode, VS Code, Zed) |
| Automation | **Johnny** | Shortcuts, Automator, Zapier (personal) | Built from a sentence, approvals, run history | Zapier for SaaS-to-SaaS at team scale |
| Customising the apps | **Johnny** | Notion-style database building, settings sprawl | "Tune": describe the change, preview the diff, apply, roll back | — |
| System health | **Johnny** | Activity Monitor/CleanMyMac (light) | "Why is my Mac slow?" explanations | Activity Monitor |

**Deliberately excluded:** passwords (use Apple Passwords), music, photos library management (Photos.app; Bolton can index with permission), maps, gaming, social feeds, video calls.

---

## Packaging (how it's sold)

| Package | Contains | Why |
|---|---|---|
| **11am Core** | Leo, Bolton, the notch, the Ask bar, the brain/model manager, iPhone companion (Today, Capture, Approvals), **Tune-lite** (Johnny's customisation for the apps you own) | Useful on its own: calendar, tasks, files, notes, memory, briefs. Everyone needs it. Hooks the daily habit. |
| **Agents (add-ons)** | Marc, William, James, Johnny (full), George, Conner, Robert, Cole, Harris | Pay for the specialists you need |
| **Bundles** | *Founder* (Marc, William, James, George, Conner) · *Creator* (William, Robert, Cole, James) · *Everything* (all 11) | Simple choices and higher order value |

**Why Tune-lite is in Core:** "make the app fit me" is the core differentiator, so it can't sit behind an add-on. Full Johnny (terminal, automations builder, mini-app studio, coding agent) is the add-on.

Pricing ideas, price testing and licensing mechanics are in [08-shipping-and-business](./08-shipping-and-business.md#pricing-structure).

---

## A founder's day with 11am (the north-star scenario)

**07:40, on iPhone.** Lock-screen widget: *"3 meetings · 2 approvals · runway 14.2 mo."* Overnight, while the Mac was charging, Marc triaged 63 emails (4 need you), James finished the competitor scan you asked for yesterday, and George matched 11 receipts.

**08:15, opens the MacBook.** The notch shows a small `le` and a `2` for two approvals. Hover: *"Marc drafted 3 replies · Investor call in 45 min."* Click: approve two drafts, edit one ("make it warmer") and send.

**08:20.** Leo's prep card for the investor call, built from Marc (last 6 emails with them), Bolton (notes from the last call and the decision log), James (their recent fund announcement) and George (current MRR and burn, as a one-pager). One click shares the one-pager to William for polishing.

**09:00, the call.** The notch shows a recording dot and a timer. Leo transcribes locally. After the call: summary, three action items as tasks, one follow-up email drafted by Marc, a decision ("raise at $X cap") logged to Bolton with the transcript as source.

**10:30.** You drag a supplier contract PDF onto the notch and drop it on `bn`. Bolton files it under *Projects › Supplier*, extracts the term, renewal date and price, and tells Leo about the renewal deadline. George notes the cost.

**11:00, the check-in.** Leo, in the notch and as a notification: *"Done: 4 replies sent, investor notes filed, contract terms logged. Waiting on you: approve the pricing page copy (William), decide on the second supplier (James's comparison is ready). This afternoon: 2 h of deep work protected 13:00–15:00, so I moved the 14:00 sync to Thursday and Marc has drafted the reschedule note."*

**13:00.** In William, you write the pricing page. William suggests edits in suggestion mode. Robert produces the hero image in brand. Johnny, because you asked once, adds a "pricing experiments" view to Conner that shows each price test with George's conversion numbers.

**16:30.** You ask the Ask bar: *"Turn the investor call into an update email to all investors, with this month's numbers."* Leo routes it: Conner writes the narrative, George supplies the numbers, William applies your voice, Marc prepares a send to the "Investors" group. It waits in Approvals.

**18:00, evening wrap** (optional). *"Tomorrow: 2 meetings, 1 deadline (BAS lodgement Friday; George has prepared the worksheet). Harris: 6-minute French review ready if you want it on the train."*

That's the product. Every brief in `agents/` traces back to moments like these.

---

## The gimmick filter

You mentioned that some of your ideas are cute rather than useful. Score every proposed feature from 0 to 2 on each criterion:

| Criterion | 0 | 1 | 2 |
|---|---|---|---|
| **Frequency**: how often would a founder use it? | Rarely | Monthly | Weekly or more |
| **Time saved** per use | Seconds | Minutes | 10+ minutes or a whole task |
| **Replaces something** they pay for or dread | No | Partly | Clearly |
| **Needs AI** to be good (vs plain software) | No | Helps | Impossible without it |
| **Fits an agent's job** (clear owner, no overlap) | No owner | Shared | Clear owner |
| **Low-tier viable** (8–16 GB Mac) | No | With cloud | Yes, locally |
| **Trust-safe**: low risk of embarrassing or harmful mistakes | Risky | Needs approval flow | Safe |

**Total out of 14:**
- **11–14 → Core feature.** Build it in the agent's v1 or v2.
- **7–10 → Later / delight.** Park it in the agent's "Later" list. Revisit after launch data.
- **≤6 → Not in the product.** If it's still charming, ship it as a **Johnny template** (a mini-app or automation users can install from a gallery). Cute ideas live there and never bloat the core.

There's a template for scoring your list in [07-roadmap](./07-roadmap.md#idea-triage-sheet).

---

## Success metrics (for you as the builder)

- **Daily active check-ins:** does the user open the 11am check-in on most workdays? (The habit metric.)
- **Approval rate:** % of agent drafts approved without edits (quality), and % edited (learning signal).
- **Time to find:** median time from Bolton query to opening the right file.
- **Undo rate:** % of autonomous actions undone (should trend below 2%. Higher means autonomy is set too high).
- **Local share:** % of model calls served on-device (privacy and cost).
- **Add-on attach rate:** agents per paying user.
- **Crash-free sessions:** above 99.5%. **Idle battery impact:** shouldn't show in Battery settings as "significant energy".
