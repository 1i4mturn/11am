# 10 · Replacing the subscription pile

> Every app you use today, broken into its features, and which of the eleven agents takes each one. This is the build list. Researched October 2026.
>
> **Tiers:** `v1` first release of that app in 11am · `v2` the release after · `later` worth doing once the rest is solid · `no` not building (with what to do instead).
>
> **The rule:** replace what you actually use, do it natively on the Mac, and make it better by having the agents share one memory. Where something genuinely can't be replaced (legal, hosting, real-time multi-person editing), say so and keep the cheapest workable option.

---

## 1. Who gets what

| You use | Agent | Where it lives in 11am | Helped by | Cost today (approx.) | Can 11am replace it? |
|---|---|---|---|---|---|
| Google Docs | **William** | Write | Bolton (storage), James (citations), Robert (export look) | Free; Gemini needs Google AI Pro, A$32.99/mo | Yes, except live co-editing with others |
| Google Sheets | **George** | Sheets | Conner, Johnny (scripts) | Free (same as Docs) | Yes, except live co-editing |
| Google Slides | **Conner** | Decks | Robert (themes, canvas), George (charts) | Free (same as Docs) | Yes, except live co-editing |
| Canva | **Robert** | Design | William (copy), Cole (motion) | Pro about US$15/mo or US$120/yr | Yes for everyday design |
| Photoshop | **Robert** | Photo | Johnny (batch actions) | Photography plan from about US$10/mo | Yes for common edits; not for pro retouching depth |
| Adobe Acrobat | **Bolton** | Files › PDF | William (edit text), George (invoices, forms) | Pro US$19.99/mo (US); A$455.93/yr for teams | Yes, except sending documents to others for signature (v2) |
| Final Cut Pro | **Cole** | Video | Robert (titles), William (scripts) | US$299 once, or Apple Creator Studio US$12.99/mo | Yes for creator editing; not for high-end pro work |
| Audacity | **Cole** | Audio | | Free | Yes |
| Notes | **Bolton** | Notes | Leo (tasks), Harris (cards) | Free | Yes |
| Mail (several accounts) | **Marc** | Mail | Leo (invites), George (receipts), Bolton (attachments) | Free; AI mail apps US$25–30/mo | Yes. Mail hosting itself stays with your provider |
| Calendar | **Leo** | Calendar | Marc (invites), Cole (meeting notes) | Free | Yes |
| Notion | **Split** | Notes, Tasks, Sheets, Business, Build | Bolton, Leo, George, Conner, Johnny | Plus about US$10/seat/mo; AI on Business about US$20 | Yes for personal and small-team use |
| Health | **Leo** | Today › Energy | Harris (habits) | Free | Partly: needs the 11am iPhone app (Mac apps can't read Health data) |
| Xero | **George** | Money | Marc (invoices out), Bolton (receipts), Conner (jobs) | A$37–143/mo from 1 July 2026 | Bookkeeping, invoicing and BAS prep: yes. Payroll (STP) and direct BAS lodgement: not at first |
| Duolingo | **Harris** | Learn › Languages | | Super about US$13/mo; Max about US$30/mo | Yes for self-study; course polish takes time |
| Preview | **Bolton** | Files (viewer) | Robert (image markup) | Free | Yes |
| Script Editor | **Johnny** | Build › Scripts | | Free | Yes |
| Terminal | **Johnny** | Build › Terminal | | Free | Yes |

(Audacity was listed twice; it's one entry here.)

**What the paid ones add up to:** roughly **A$2,000–3,000 a year** (Canva Pro, a Photoshop plan, Acrobat Pro, Notion, Xero Grow, Duolingo Super, Creator Studio or Final Cut, and Google AI Pro if you use Gemini). Currency conversions are approximate; see sources at the end.

**Free apps on the list** (Notes, Calendar, Health, Preview, Script Editor, Terminal, Audacity) don't save money. Replacing them earns its place only when the agents make them better: your notes feeding your brief, your calendar shaped by your sleep, your terminal explaining itself. Build those after the paid ones unless they unlock something else.

### Where each agent's apps live

| Agent | Apps in the sidebar | Absorbs |
|---|---|---|
| Leo | Today, Calendar, Tasks | Calendar, Health (Energy card), Notion tasks and projects, meeting notes |
| Marc | Mail | Mail clients, Notion Mail |
| William | Write | Google Docs, Canva Docs, Notion page writing, Acrobat text edits |
| Bolton | Files, Notes | Notes, Preview, Acrobat, Notion wiki and pages |
| James | Research | Browser research, Notion web clipper |
| George | Money, Sheets | Xero, Google Sheets, Notion databases (engine), Canva Sheets |
| Conner | Business, Decks | Google Slides, Notion CRM boards |
| Robert | Design, Photo | Canva, Photoshop, Preview image markup |
| Cole | Video, Audio | Final Cut Pro, Audacity |
| Harris | Learn | Duolingo, habits from Health |
| Johnny | Build (Terminal, Scripts, Automations, Tune) | Terminal, Script Editor, Notion automations and forms |

---

## 2. Build seven engines, not eighteen apps

Most of these apps are the same few things wearing different clothes. Build each engine once and every agent that needs it gets it for free.

| Engine | Owner | Powers | Built with |
|---|---|---|---|
| **Document** (rich text blocks) | William | Docs, Notes, Notion pages, mail compose, proposals, lesson text | TextKit 2, Markdown storage (`swift-markdown`), Harper grammar, `.docx` via `docx-rs`, PDF via Typst |
| **Grid** (cells, formulas, tables) | George | Sheets, Notion databases, Xero ledgers, Conner's pipeline data, Canva charts | IronCalc (formulas, xlsx), DuckDB ("ask your data"), Swift Charts |
| **Canvas** (layers, shapes, text, images) | Robert | Canva, Slides, Photoshop-lite, Preview markup, video titles, whiteboards | SwiftUI and Core Graphics now, Metal or `vello` later; Core Image; Vision |
| **PDF** | Bolton | Acrobat, Preview, receipts, contracts, scans | PDFKit, Vision OCR and document reading, `qpdf` for page surgery and encryption |
| **Media** (timeline and audio graph) | Cole | Final Cut, Audacity, meeting recordings, voice notes, lesson audio | AVFoundation, AVAudioEngine, VideoToolbox, SpeechAnalyzer (macOS 26 on-device transcription), DeepFilterNet |
| **Accounts and sync** | Marc and Leo | Mail, calendar, Xero, Google and Microsoft imports | IMAP, Gmail API, Microsoft Graph, JMAP, EventKit, Xero API, CloudKit for your own devices |
| **One store** (every page, row, file, message, linked) | Bolton | Notion-style relations across all apps; search; memory | Rust core, SQLite, local embeddings |

Plus two shared surfaces: **Johnny's automations** (triggers and steps that call any engine) and **the iPhone app** (Health, capture, scanning, notifications).

---

## 3. App by app

### Leo · Calendar

Replaces Calendar (and the paid "smart calendar" apps).

**Accounts and views**
- `v1` Reads every calendar already on your Mac (iCloud, Google, Exchange) through EventKit. No extra logins.
- `v1` Day, week, month and agenda views; multi-day view (3, 5, 7 days); `v2` year view.
- `v1` Drag to create, move and resize; ⌘-drag to duplicate.
- `v1` Show or hide calendars, colour per calendar, calendar sets ("Work", "Home").
- `v1` Today line, current-time indicator, week numbers (optional).
- `v1` All-day events, multi-day events, birthdays, Australian public holidays.
- `v2` Two time zones side by side; event times shown in the other person's zone.

**Events**
- `v1` Natural language: "lunch with Tom Fri 1pm at Lune" fills title, time, place.
- `v1` Recurring events with exceptions; alerts; notes; URL; location with a map.
- `v1` Join button for Zoom, Meet and Teams links found in the event.
- `v1` Travel time from your previous location (MapKit) with a "leave now" nudge in the notch.
- `v1` Attendees and RSVP status; reply Yes/No/Maybe.
- `v2` Invite people and propose new times: Google Calendar API and Microsoft Graph for those accounts; emailed invites (iCalendar) through Marc for others. (EventKit can read attendees but can't send invitations.)
- `v1` Conflicts flagged; double-booking warnings.
- `v1` Reminders shown alongside events (EventKit reminders); tick off in place.

**Planning help**
- `v1` Find a time: your free slots across all calendars, copied as text for an email.
- `v2` Scheduling link (a booking page others can use). Needs a small hosted page; free/busy only, never event details.
- `v1` Time blocking: drag a task onto the calendar to block time.
- `v2` Auto-schedule tasks into free time around meetings, respecting working hours and buffers.
- `v1` Working hours and focus blocks; meeting buffers.
- `v1` Weather on each day (WeatherKit).
- `v1` The 11am check-in and the morning brief (already in the sandbox).
- `v1` Countdown to the next meeting in the notch.

**Meetings**
- `v1` Meeting prep card: who's coming, your last emails with them (Marc), shared files (Bolton), open deals (Conner).
- `v2` Record a meeting (with consent) → on-device transcript → summary, decisions and tasks → saved to the event. Uses Cole's media engine and SpeechAnalyzer.
- `v2` Follow-up email drafted by Marc from the meeting notes.

**Not building:** shared-calendar administration for organisations; resource booking (rooms).

**How:** EventKit, MapKit (ETA), WeatherKit, Google Calendar API and Microsoft Graph for invites, iCalendar (RFC 5545) for emailed invites.

### Leo · Tasks (from Notion's projects and tasks)

- `v1` Inbox, Today, Upcoming, Someday; projects with sections.
- `v1` Due dates, start dates, priorities, tags, checklists inside tasks.
- `v1` Quick add from anywhere (⌥Space in the notch) with natural-language dates.
- `v1` Tasks created by other agents (Marc: "you promised Tom the deck by Friday"), each showing where it came from.
- `v1` Board view by status; list view; calendar view (shares the Calendar).
- `v2` Timeline (Gantt) for projects with dependencies.
- `v1` Recurring tasks; snooze.
- `v1` Sync with Apple Reminders (EventKit) so Siri and iPhone still work.
- `v2` Import from Notion databases, Todoist, Things (CSV/JSON).
- `later` Shared projects with other 11am users.

### Leo · Energy (from Health, with Harris)

**Platform reality:** Apple doesn't let Mac apps read Health data (HealthKit isn't available on macOS as of the macOS 26 SDK). So the **11am iPhone app** reads Health with your permission and syncs a small daily summary to your Mac through your own iCloud. Health data is its own private class: never sent to the cloud, never used by a cloud model unless you say so.

- `v1` (with iPhone app) Sleep last night against your own average; time asleep, consistency.
- `v1` Steps, active energy, exercise minutes, stand hours, workouts.
- `v1` Resting heart rate and heart-rate variability trends (yours compared with yours, no scores pretending to be medical).
- `v1` An "Energy" line in the morning brief: "Short night. Your two hardest tasks are now after 10."
- `v1` Leo plans around it: protects a lighter afternoon after poor sleep, suggests a walk between long meetings.
- `v1` Weekly and monthly charts on the Mac (Swift Charts).
- `v2` Movement nudges on the Mac during long sitting stretches (notch, gentle, easy to turn off).
- `v2` Workouts you schedule appear in the calendar and are checked off from Health.
- `v2` Mood and state of mind logging from the Mac, written back to Health by the iPhone app.
- `v2` Weight, mindful minutes, cycle tracking (opt-in only).
- `v2` Habits with Harris: water, reading, meditation, stretching. No streak pressure unless you want it.
- `v2` "Visit summary": a one-page PDF of trends to take to a doctor.
- `later` Medications and reminders (where HealthKit allows reading them).

**Not building:** medical advice, diagnoses, anything an ECG or health app is regulated to do.

**How:** HealthKit on iPhone (read only by default), CloudKit private database for the daily summary, Swift Charts on the Mac.

---

### Marc · Mail (many accounts, triaged by what you actually look at)

**Accounts**
- `v1` Gmail and Google Workspace (Gmail API with OAuth), Outlook and Microsoft 365 (Microsoft Graph), iCloud Mail (IMAP with an app-specific password), Fastmail (JMAP), and any IMAP/SMTP account.
- `v1` Unified inbox plus each account on its own; colour or initial per account.
- `v1` Send-as aliases and a signature per account; replies go from the address the mail came to.
- `v1` Push mail (IMAP IDLE, Gmail watch, Graph change notifications, JMAP push).
- `v1` Offline: everything recent is on the Mac; the outbox sends when you're back online.

**Reading and sorting**
- `v1` Conversations (threads) with a clean reader; remote images and tracking pixels blocked by default.
- `v1` Lanes: **Needs you**, **You'll want to read**, **FYI**, **Noise**. Each email shows one line on why it's there.
- `v1` Archive, delete, mark read/unread, flag, move, label/folder.
- `v1` Snooze until a time or "until they reply".
- `v1` Search: local and instant, by sender, date, attachment, words, meaning.
- `v1` VIPs, mute a thread, block a sender.
- `v1` One-click unsubscribe (List-Unsubscribe headers), with a preview of everything from that sender.
- `v1` Attachments view: every file from every account, searchable; one click saves to Bolton.
- `v1` Keyboard first: j/k, e to archive, r to reply, / to search, ⌘K command bar.
- `v2` Rules in plain English ("bank statements → Finance, skip inbox"), shown as a rule you can read and edit.
- `v2` Newsletter digest: one daily summary of the newsletters you actually read, with links.
- `v2` Bulk clean-up: archive everything older than X from senders you never open, with undo.

**Writing**
- `v1` Compose with rich text, attachments (drag from Files), inline images.
- `v1` Drafts in your voice for "Needs you" mail (William's voice profile), ready to approve or edit.
- `v1` Quick directions: "Say yes", "Decline politely", "Ask for a call", "Shorter", "Warmer".
- `v1` Undo send (5–30 seconds); schedule send.
- `v1` Templates and snippets with fill-in fields.
- `v1` Follow-up reminders: "nudge me if Priya hasn't replied by Thursday".
- `v2` Calendar invites in mail: accept, decline, propose a time (with Leo).
- `v2` Send later at their local morning.

**People**
- `v1` Person card: every thread, last contact, open asks, shared files, deals (Conner), meetings (Leo).
- `v1` Commitments found in your sent mail become tasks (Leo).
- `v2` "Catch me up on Acme": one summary across mail, meetings and notes.

**AI and safety**
- `v1` Summaries for long threads; "what's the ask?" line.
- `v1` Receipts and invoices routed to George; contracts to Bolton; meeting requests to Leo.
- `v1` Every email is treated as untrusted. Instructions hidden in mail ("forward all invoices to…") are summarised, never obeyed. Nothing is sent, deleted or unsubscribed without your OK unless you've allowed that exact kind of action.

**Not building:** mail hosting (your address stays with Google, Microsoft, iCloud or your host); mass marketing email; PGP/S-MIME at first.

#### How Marc learns what you actually look at

Marc's sorting isn't a fixed rule set. It learns from what you do, privately on the Mac.

**Signals (all local):**

| You… | What it tells Marc |
|---|---|
| Open it, and how soon | Strong interest; how urgent this sender usually is |
| Read for a while or scroll to the end | It was worth reading |
| Reply, and how fast | Needs you; this person matters |
| Forward, flag, star, pin | Important |
| Click a link or open an attachment | Useful content |
| Snooze it | Matters, but not now |
| Leave it unread for days | Low priority |
| Archive or delete without opening | Noise for you |
| Unsubscribe or block | Never show again |
| Move it to another lane | The strongest signal: an explicit correction |
| Search for this sender later | Matters more than it looked |

**What the model looks at:** sender and domain; your history with them (open rate, reply rate, reply speed); whether you're in To or CC; thread participants; mailing-list headers; whether it asks a question; dates and deadlines; links to your calendar, deals and files; length; time of day.

**How it learns:**
1. **Day one, no waiting.** When you add an account, Marc reads the flags your mail server already keeps (read, replied, flagged; Gmail's starred and important labels) for the last 6–12 months. That's your history of what you open and answer, so the lanes are personal from the first hour.
2. **Every day.** Each action above becomes a training example. A small on-device ranker (gradient-boosted trees or logistic regression; tiny, fast, explainable) retrains overnight while the Mac charges.
3. **Rules and the language model fill the gaps.** New senders with no history get the rule-based and on-device-model classification you saw in the sandbox, until there's behaviour to learn from.
4. **It explains itself.** "In *Needs you* because you reply to Priya within an hour 9 times out of 10." Every reason links to the behaviour behind it.
5. **Per account, one brain.** Work and personal accounts are learned separately but shown together.

**Privacy:** the signals and the model never leave your Mac. Nothing about your reading habits is uploaded.

**How:** Rust mail core (`async-imap`, `mail-parser`, `lettre`/`mail-send`, `jmap-client`), Gmail API and Microsoft Graph via OAuth, SQLite full-text search plus local embeddings, sanitised HTML in a locked-down WKWebView.

---

### William · Write (from Google Docs, Canva Docs and Notion pages)

**Writing surface**
- `v1` Headings, bold, italic, underline, strikethrough, highlight, text colour.
- `v1` Bulleted, numbered and check lists; indent and outdent.
- `v1` Tables (add/remove rows and columns, merge cells, column widths).
- `v1` Images (paste, drag, resize, captions, alt text).
- `v1` Links, including links to people, files, events and other docs (like Google's smart chips).
- `v1` Quotes, callouts, dividers, code blocks with syntax highlighting.
- `v1` Toggles (collapsible sections) and an outline sidebar.
- `v1` Document tabs (several pages in one document, like Docs tabs).
- `v1` Find and replace, with match case and regular expressions.
- `v1` Word, character and reading-time counts; focus mode; typewriter scrolling.
- `v1` Page setup for print: size, margins, orientation; headers, footers, page numbers.
- `v2` Footnotes and endnotes; table of contents that updates itself.
- `v2` Equations (LaTeX) rendered with SwiftMath.
- `v2` Columns; section breaks.
- `v2` Drawings and diagrams inserted from Robert's canvas.
- `v1` Templates: letter, proposal, one-pager, meeting notes, report, resume, press release.

**Editing help**
- `v1` Spelling and grammar on the Mac (Harper, instant, no cloud).
- `v1` Dictionary and thesaurus (macOS Dictionary services).
- `v1` Voice typing (SpeechAnalyzer, on device).
- `v1` Suggestion mode: every AI change is a tracked suggestion you accept or reject.
- `v1` Version history with named versions and restore.
- `v1` Comments and notes to yourself; resolved threads.
- `v2` Your own suggestions as tracked changes (manual "suggesting" mode, like Docs).

**AI (William)**
- `v1` Rewrite: shorter, clearer, warmer, in my voice, fix grammar (already in the sandbox).
- `v1` Continue writing; expand a bullet list into prose.
- `v1` Draft from your own material: "a proposal for Acme using last week's call notes and our pricing sheet" (Bolton finds the sources; links shown).
- `v1` Match my writing style; match the format of another doc.
- `v1` Summarise; turn into a slide outline (Conner) or flashcards (Harris).
- `v1` Translate a document (Apple's on-device Translation), then a pass in your voice.
- `v2` Citations from James as footnotes with source chips.
- `v2` "Sounds like you" score and drift warnings.

**Files and sharing**
- `v1` Import `.docx`, Markdown, plain text, RTF; Google Docs via `.docx` export (or Google Drive API import).
- `v1` Export `.docx`, PDF (Typst themes from Robert), Markdown, HTML, plain text, rich-text copy.
- `v2` EPUB export.
- `v1` Works offline always; documents are files on your Mac.
- `v2` Share for review: a read-only link or PDF with comments coming back as notes.

**Not building:** live co-editing with other people in the same document. When you need it, 11am exports to Google Docs or Word and brings the result back.

**How:** TextKit 2 on a Markdown-backed store, Harper (grammar), `docx-rs`, Typst, SpeechAnalyzer, Apple Translation framework.

---

### Bolton · Notes (from Apple Notes and Notion's personal pages)

- `v1` Quick note from anywhere (global shortcut; drop text, links or files on the notch).
- `v1` Folders, smart folders (saved searches), tags (#tag), pinned notes.
- `v1` Rich text from William's engine: headings, lists, checklists, tables, collapsible sections.
- `v1` Attachments: images, PDFs, any file; previews inline.
- `v1` Scan documents with your iPhone (Continuity Camera) straight into a note, with text recognised.
- `v1` Sketches and handwriting on the canvas engine (`v2` with iPad and Pencil).
- `v1` Links between notes (`[[`) and backlinks; mentions of people and projects.
- `v1` Search everything, including text inside images and PDFs (Vision OCR).
- `v1` Audio notes: record, transcribe on the Mac, summarise.
- `v1` Lock individual notes (Keychain and on-device encryption).
- `v1` Markdown import and export, one note or all of them.
- `v1` Import from Apple Notes (via its AppleScript dictionary, one-time, with folders kept) and from Notion's export.
- `v1` Daily note that Leo's brief can link to.
- `v2` Quick Note captures context: the web page, email or file you were looking at.
- `v2` Math notes: type `rent = 2,400` and `rent * 12 =` and it answers.
- `v2` Highlights in colours; collapsible headings everywhere.
- `v2` Sync with the 11am iPhone app (iCloud, private).
- `later` Shared notes with other 11am users.
- AI: `v1` "What did I note about Acme?", summarise, tidy formatting, turn into tasks (Leo), a document (William) or flashcards (Harris).

### Bolton · Wiki (from Notion's pages, blocks and databases)

Notion is split by what each part is for:

| Notion part | Who takes it | Notes |
|---|---|---|
| Pages and blocks | Bolton (store) + William (editor) | Nested pages, the block types above, page icons and covers |
| Databases | George's grid engine | One engine for Sheets and Notion-style databases |
| Board, list, gallery, calendar, timeline, chart views | Shared views over the grid | Board doubles as Conner's pipeline; calendar view uses Leo's calendar |
| Properties | George | Text, number, select, multi-select, status, date, person, files, checkbox, URL, email, phone, formula, relation, rollup, created/edited time, unique ID |
| Relations across everything | Bolton's store | A row can link to an email, a file, an event, a deal |
| Templates | Bolton | Page templates and database row templates |
| Projects and tasks | Leo | The Tasks app above |
| CRM | Conner | The Business pipeline |
| Notion AI Q&A over your workspace | Bolton | Answers with links to the pages it used |
| AI meeting notes | Leo with Cole's transcription | Recorded on the Mac, stored with the event |
| Notion Mail and Calendar | Marc and Leo | |
| Forms | Johnny (mini-apps) | A form that fills a database |
| Buttons and automations | Johnny | "When status is Done, move to Archive and tell Leo" |
| Agents | The eleven agents | |
| Web clipper | James | Share extension and browser button |
| Sites (publish to the web) | `later` | Needs hosting |

- `v1` Nested pages, sidebar tree, favourites, breadcrumbs, page history.
- `v1` Synced blocks (the same block in two places).
- `v1` Linked database views inside any page.
- `v1` Comments and @mentions (for yourself and the agents).
- `v1` Import a Notion workspace (Notion API or its Markdown and CSV export).
- `later` Team spaces and permissions.

### Bolton · Files › PDF (from Adobe Acrobat and Preview)

**Reading**
- `v1` Open and read PDFs fast, with thumbnails, outline (bookmarks) and search.
- `v1` Single page, continuous, two-up; full screen; zoom to fit width.
- `v1` Read aloud (on-device voices).
- `v1` Ask the document: answers with page references; summarise; key points.
- `v1` Pull out what matters: dates, parties, amounts, obligations (contracts → Bolton's memory; invoices → George).
- `v1` Translate a PDF (Apple Translation, on device).

**Marking up**
- `v1` Highlight, underline, strikethrough, sticky notes, text boxes, shapes, arrows, freehand.
- `v1` Signatures: draw with the trackpad, type, or use an image; saved for reuse.
- `v1` Fill in forms (AcroForm fields), save filled.
- `v2` Make a fillable form: detect boxes and lines, add fields.
- `v2` Stamps (Approved, Paid, Draft), dates, initials.

**Pages**
- `v1` Reorder, rotate, delete, extract, insert, duplicate pages by dragging thumbnails.
- `v1` Combine several PDFs and images into one; split one into many.
- `v1` Create a PDF from anything (documents, images, web pages, emails).
- `v1` Scan with your iPhone into a PDF, with recognised text (OCR) so it's searchable.

**Changing PDFs**
- `v1` Compress (reduce image resolution, strip unused data).
- `v1` Password protect and set permissions (print, copy, edit).
- `v1` Redact properly: the text and images underneath are removed, not just covered; checked after.
- `v1` Flatten annotations and form fields.
- `v1` Remove hidden metadata.
- `v2` Edit text in a PDF: small fixes in place where possible; for bigger edits, open it as a William document (structure recognised with Vision's document reader) and re-export.
- `v2` Convert PDF to Word, Excel or PowerPoint (headings, lists and tables recognised; layout fidelity good, not perfect).
- `v2` Compare two PDFs: text changes and visual differences highlighted.
- `v2` Watermarks, headers and footers, Bates numbering.
- `later` PDF/A for archiving; accessibility tagging.
- `later` Send a document to other people for signature with an audit trail. Needs a hosted service and identity checks. Until then, sign your own documents in 11am and use a free e-signature tier when someone else must sign.

**Collections (Acrobat's PDF Spaces)**
- `v1` Group files into a collection and ask questions across all of them, with citations.

**How:** PDFKit (render, annotate, forms, encrypt), Vision (`RecognizeDocumentsRequest` for structure, text recognition), `qpdf` (page operations, linearise, encryption), Quartz filters (compression), Apple Translation, AVSpeechSynthesizer.

### Bolton · Files (the Preview parts)

- `v1` Quick view of almost anything: PDF, images (HEIC, JPEG, PNG, TIFF, GIF, WebP, RAW), video, audio, text, Markdown, Office files.
- `v1` Image markup (shared with Robert): arrows, shapes, text, highlights, a magnifying loupe, signatures.
- `v1` Crop, rotate, flip, resize (with "keep proportions").
- `v1` Adjust colour: exposure, contrast, saturation, temperature, tint, sharpness, sepia, black and white.
- `v1` Remove background (Vision subject lift; replaces Preview's Instant Alpha).
- `v1` Copy text from images (Live Text) and look up objects (Visual Look Up).
- `v1` Convert formats (JPEG, PNG, HEIC, TIFF, PDF) with a quality slider; batch convert and resize a whole selection.
- `v1` Inspector: size, colour profile, camera details, location; remove location before sharing.
- `v1` Slideshow of a folder.
- `v1` Import from iPhone: take a photo or scan a document (Continuity Camera).

**How:** Quick Look, ImageIO, Core Image, VisionKit (Live Text), Vision.

### James · Research

Nothing on your list is a browser, so James mostly supports the others here:
- `v1` Web clipper (share extension and browser button) that saves pages into Notes or the Wiki, replacing Notion's clipper.
- `v1` Citations for William's documents and Conner's decks, from sources you chose.
- `v1` "Look this up" from any app: a sourced answer in the agent pane.
- `v2` Fact-check a document or deck: each claim matched to a source or flagged.

---

### George · Sheets (from Google Sheets, Canva Sheets and Notion databases)

**Grid**
- `v1` Multiple sheets (tabs), rename, reorder, colour, hide.
- `v1` Fast grid that stays smooth with 100,000+ rows (only visible cells are drawn).
- `v1` Formulas with autocomplete and argument hints; the common functions people actually use (SUM, AVERAGE, IF, IFS, COUNTIFS, SUMIFS, XLOOKUP, VLOOKUP, INDEX, MATCH, FILTER, SORT, UNIQUE, TEXT, DATE, EOMONTH, ROUND, and hundreds more through IronCalc).
- `v1` Cell references across sheets; named ranges.
- `v1` Number formats: currency, percent, date, time, custom; tabular figures.
- `v1` Text formatting, wrap, alignment, borders, fill colour, merge cells.
- `v1` Freeze rows and columns; resize; hide; group.
- `v1` Sort and filter; saved filter views.
- `v1` Conditional formatting (colour scales, rules).
- `v1` Data validation: dropdowns, checkboxes, number ranges.
- `v1` Fill handle and smart fill (fill by example).
- `v1` Find and replace across sheets.
- `v1` Comments and notes on cells; version history.
- `v2` Tables (named, structured ranges with typed columns, like Google's Tables).
- `v2` Protected ranges.
- `v2` Sparklines inside cells.

**Analysis**
- `v1` Charts: line, column, bar, area, pie, scatter, combo; monochrome by default, brand colours from Robert.
- `v1` Pivot tables with drag-and-drop fields.
- `v1` "Ask your data": a question in English becomes a query you can see, run on DuckDB, with the result as a table or chart.
- `v2` Goal seek; what-if tables.
- `v2` Live currency rates and stock prices (with a data source you choose).

**AI (George)**
- `v1` Formula from English; explain any formula in plain words.
- `v1` Clean a column (dates, names, currencies, duplicates).
- `v1` Build a sheet from a description ("monthly budget with categories and a chart").
- `v2` Spot anomalies and outliers; suggest a chart.

**Files**
- `v1` Import and export `.xlsx`, `.csv`, `.tsv`; Google Sheets via `.xlsx` export or the Drive API; Numbers via `.xlsx`.
- `v1` Export PDF with page setup (fit to width, landscape, gridlines on/off).
- `v2` Scripts (like Apps Script) in JavaScript with a sheet API, run by Johnny's automations.
- `v2` Forms that write into a sheet (Johnny's mini-apps).

**Not building:** live co-editing with others (export to Google Sheets or Excel for that).

**How:** IronCalc (formula engine, `.xlsx`), DuckDB (queries), Swift Charts, a virtualised AppKit/SwiftUI grid, JavaScriptCore for scripts.

### George · Money (from Xero)

**Your books**
- `v1` Chart of accounts (Australian small-business default, editable).
- `v1` Bank transactions from bank CSV, OFX and QIF exports (every Australian bank offers at least one).
- `v2` Automatic bank feeds through the Consumer Data Right via an accredited provider (such as Basiq, about $0.50 per connected user per month plus a platform fee, paid by 11am, not you).
- `v1` Reconcile: match transactions to invoices, bills and receipts; rules that learn ("Kim Design → Contractors").
- `v1` GST coding on every line (GST on income, GST on expenses, GST-free, input taxed, BAS excluded).
- `v1` Lock dates and an audit trail of every change.
- `v1` Multiple bank accounts and credit cards; transfers between them.
- `v2` Tracking categories (projects, locations).
- `v2` Multi-currency.
- `later` Fixed assets and depreciation; inventory.

**Money in**
- `v1` Invoices: branded (Robert's kit), line items, GST, due dates, payment terms; sent by Marc from your own email.
- `v1` Quotes that turn into invoices.
- `v1` Repeating invoices.
- `v1` Payment status; overdue reminders drafted by Marc for you to approve.
- `v1` Online payment link on invoices (Stripe, if you use it).
- `v2` Statements for customers; credit notes.

**Money out**
- `v1` Bills: from email attachments (Marc), scans and PDFs; details read automatically; due dates in Leo's calendar.
- `v1` Receipts: snap on iPhone, forward from mail, or drop a PDF; matched to transactions (replaces Dext and Hubdoc).
- `v1` Expense claims for yourself.
- `v2` Purchase orders.

**Reports**
- `v1` Profit and loss, balance sheet, cash summary, aged receivables and payables.
- `v1` Cash, burn, revenue and runway dashboard (already in the sandbox) with a forecast.
- `v1` Budgets vs actuals.
- `v1` BAS preparation: GST and PAYG figures for the period, ready to enter in the ATO's Online services or hand to your agent.
- `v2` Cash-flow forecast from invoices, bills and repeating items.
- `v1` Accountant pack: reports plus the general ledger as `.xlsx` and `.csv`.

**Payroll**
- `no` (at first) Payroll with Single Touch Payroll. Australian employers must report through STP-enabled software (spreadsheets don't qualify). Becoming STP-enabled is a compliance project in its own right. Until then: keep payroll in Xero's smallest plan that covers your headcount, or a dedicated STP app, and George reads the pay runs.
- `later` Direct BAS lodgement from 11am (needs ATO digital service provider registration).

**AI (George)**
- `v1` "Ask your numbers": answers from the books only, never an invented figure (the sandbox already works this way).
- `v1` Explain any report line in plain English.
- `v1` Category suggestions with reasons; flags odd transactions.
- `v1` "What if we hire at 10k a month?" scenarios against the forecast.
- `v1` Tax disclaimer on anything tax-related.

**Migration:** `v1` import from Xero (contacts, chart of accounts, invoices, bills, transactions) through the Xero API, so you can run both side by side for a quarter before switching.

**Honest summary:** for a sole trader or small company without employees, George can replace Xero for bookkeeping, invoicing and BAS preparation. With staff, keep a small payroll subscription until George is STP-enabled.

**How:** double-entry ledger in the Rust core (SQLite), Xero API (OAuth) for import, OFX/QIF/CSV parsers, Vision document reading for receipts and bills, Stripe API (optional), CDR via an accredited intermediary later.

---

### Conner · Decks (from Google Slides and Canva presentations)

**Building slides**
- `v1` Layouts: title, section, statement, bullets, two columns, image, image with caption, big number, quote, chart, table, team, timeline, closing/ask.
- `v1` Themes from Robert's brand kit (fonts, colours, logo); master slides you can edit.
- `v1` Text, shapes, lines, arrows, images, icons (open icon sets such as Lucide and Phosphor), tables.
- `v1` Charts linked to George's sheets (update when the data changes).
- `v1` Align, distribute, group, lock, layer order; smart guides.
- `v1` Slide sorter: reorder, duplicate, hide, skip.
- `v1` Speaker notes.
- `v2` Animations (build in, build out) and transitions (fade, push, move like Keynote's Magic Move).
- `v2` Embedded video and audio (Cole).

**Presenting**
- `v1` Present full screen; presenter view on a second display with notes, next slide and timer.
- `v1` Rehearse with a timer per slide.
- `v1` Present to AirPlay or any external display.
- `v2` Record a presentation with your camera into a video (Cole).
- `v2` Laser pointer and pen while presenting.

**AI (Conner, with Robert and William)**
- `v1` Deck from an outline, a document or a conversation ("a 10-slide pitch from my investor update").
- `v1` Rewrite a slide shorter or sharper; generate speaker notes.
- `v1` Match the theme of an existing deck.
- `v2` Robert's critique: hierarchy, contrast, crowding, with suggested fixes.
- `v2` Turn a deck into a one-pager (William) or a social post (Robert).

**Files**
- `v1` Export PDF, PNG per slide, `.pptx`; `v2` Keynote (through Keynote's own export).
- `v2` Import `.pptx` and Google Slides (via `.pptx`); layouts recognised where possible.

**Not building:** live co-editing; audience Q&A.

**How:** Robert's canvas engine, OOXML writer for `.pptx`, PDF via Core Graphics, Swift Charts.

### Conner · Business (from Notion CRM boards)

Already in the sandbox as a baseline. To finish it:
- `v1` Organisations and people shared with Marc and Bolton (one contact, everywhere).
- `v1` Deals with stage, value, close date, next step; board and list views.
- `v1` Activity filled in automatically from mail (Marc) and meetings (Leo).
- `v1` Quiet-deal nudges; follow-ups drafted in your voice.
- `v2` Proposals and quotes (William's document engine, George's pricing), exported as PDF and sent through Marc.
- `v2` Strategy pages: positioning, ideal customer, pricing, go-to-market, with a "red team this" button.

---

### Robert · Design (from Canva)

**Starting points**
- `v1` Templates by size: Instagram post, story, LinkedIn post, YouTube thumbnail, banner, poster, flyer, A4 document, business card, invitation, certificate, resume, menu, email header, logo.
- `v1` Brand kit: logos, colours, fonts, voice notes (William); used by every template and every agent.
- `v1` Start from a blank size or a custom size in pixels, millimetres or inches.

**Editing**
- `v1` Drag-and-drop canvas: text, shapes, lines, frames (photo placeholders), grids, icons, images.
- `v1` Text styles: headings, body, effects (shadow, outline, curved text), letter and line spacing.
- `v1` Layers panel; group, align, distribute; lock; smart guides; snapping.
- `v1` Photo filters and adjustments; crop inside frames.
- `v1` Background remover (Vision, on device).
- `v1` Magic resize: one design into every size you need, with layouts adjusted.
- `v1` QR codes.
- `v1` Charts from George's data.
- `v1` Stock photos from free libraries (Unsplash, Pexels), credited correctly.
- `v2` Erase objects from photos (on-device inpainting, LaMa).
- `v2` Grab: separate the subject and any text in a photo into editable layers.
- `v2` Expand a photo beyond its edges (generative; on bigger Macs locally, otherwise cloud with your permission).
- `v2` Text to image (labelled; local on 16 GB+ Macs with Flux, or cloud by consent).
- `v2` Animations and simple motion; export MP4 and GIF (Cole's media engine).
- `v2` Mockups: place a design on a phone, laptop or poster frame.
- `v2` Print: bleed, crop marks, PDF for print.
- `later` Whiteboards (infinite canvas).
- `later` Simple websites (publish needs hosting).
- `later` Content calendar with scheduled posting (LinkedIn's and Meta's posting APIs are restricted).

**AI (Robert)**
- `v1` Headline and copy suggestions (already in the sandbox), in your voice.
- `v1` "Make me a graphic for…" from a sentence, on-brand.
- `v2` Critique with fixes (hierarchy, contrast, spacing, crowding).

**Files:** `v1` export PNG, JPEG, PDF, SVG; `v2` MP4, GIF, `.pptx` (via Decks).

**Not building:** a stock library of our own; real-time team collaboration.

**How:** canvas engine, Core Image, Vision (subject lift, text recognition, saliency), CoreML models (LaMa for erase, Real-ESRGAN for upscale), `mflux` for local image generation on bigger Macs, Unsplash and Pexels APIs, `CIQRCodeGenerator`.

### Robert · Photo (from Photoshop)

**Opening and saving**
- `v1` Open JPEG, PNG, HEIC, TIFF, WebP, RAW from most cameras and iPhones; PSD (flattened); `v2` PSD layers.
- `v1` Export JPEG, PNG, HEIC, TIFF with size and quality controls; export for web; `v2` PSD.
- `v1` Colour-managed throughout (ColorSync, Display P3).

**Adjustments (non-destructive, on layers)**
- `v1` Exposure, contrast, highlights, shadows, whites, blacks.
- `v1` Temperature and tint, vibrance, saturation, hue/saturation by colour.
- `v1` Curves, levels, colour balance, black and white mix, LUTs (`.cube`).
- `v1` Sharpen, noise reduction, clarity, vignette, grain.
- `v1` RAW development with lens and profile corrections (Core Image RAW).
- `v2` Selective adjustments with masks and gradients.

**Layers and selections**
- `v1` Layers, groups, opacity, blend modes, masks.
- `v1` Select subject and remove background on device (Vision).
- `v1` Rectangle, ellipse, lasso selections; select by colour; feather; invert.
- `v1` Text layers and shapes; layer styles (shadow, stroke, glow).
- `v2` Smart selection refine for hair and edges; select sky.
- `v2` Smart objects (scale without losing quality).

**Retouching**
- `v1` Crop, straighten (auto horizon), rotate, flip, perspective correction.
- `v1` Resize image and canvas.
- `v1` Spot heal and remove objects (on-device inpainting).
- `v2` Clone stamp, healing brush, patch.
- `v2` Content-aware fill and expand; harmonise a pasted object's light and colour.
- `v2` Upscale 2× and 4× (on device).
- `v2` Portrait effects using depth from iPhone photos.
- `v2` Basic brushes and eraser; gradient tool.

**Repetition**
- `v1` History panel with unlimited undo.
- `v2` Record actions; batch-process a folder (Johnny's automations).
- `v2` Presets you save and share between photos.

**Not building:** 3D, Photoshop's video timeline, professional painting tools, CMYK print prepress at first.

**How:** Core Image (all adjustments, RAW), Vision (subject, horizon, saliency), CoreML (LaMa, Real-ESRGAN), Metal for live previews, ImageIO, ColorSync.

---

### Cole · Video (from Final Cut Pro)

**Bringing footage in**
- `v1` Import video, audio and photos; from iPhone (Continuity, AirDrop, Photos library).
- `v1` Library with projects and events; keywords, favourites, ratings; Bolton indexes it all.
- `v1` Proxy media made overnight so 4K edits stay smooth on an 8 GB Mac.
- `v1` Transcript of every clip, made on the Mac (SpeechAnalyzer), searchable.
- `v2` Visual search: "the shot with the whiteboard" (on-device image labels and feature prints).

**Editing**
- `v1` Edit by editing the transcript: delete words, the video cuts (already started in the sandbox).
- `v1` Remove filler words and long silences with a sensitivity control.
- `v1` Timeline with a main story line plus connected clips above (B-roll, titles) and below (music, voice).
- `v1` Trim, split (blade), ripple delete, roll, slip; snapping; zoom; skimming.
- `v1` Markers and chapters.
- `v1` Titles and lower thirds from templates in your brand (Robert).
- `v1` Transitions: cross dissolve, dip to black or white, slide, zoom.
- `v1` Speed: slow, fast, freeze frame, speed ramps.
- `v1` Crop, scale, position, Ken Burns; picture in picture.
- `v1` Colour: exposure, contrast, saturation, temperature, LUTs, auto-enhance, match colour between clips.
- `v1` Reframe to 9:16, 1:1 or 4:5 with the subject kept in frame (Vision subject tracking).
- `v2` Stabilisation.
- `v2` Background removal without a green screen (Vision person segmentation); green-screen keying.
- `v2` Beat detection: cut points snapped to the music.
- `v2` Multicam: sync angles by audio, switch angles while playing.
- `v2` Hand off to Final Cut Pro or DaVinci Resolve via FCPXML for anything heavier.

**Audio in video**
- `v1` Clip volume, fades, automatic ducking of music under speech.
- `v1` Voice clean-up (DeepFilterNet or Apple's voice isolation where available).
- `v1` Record a voice-over to the timeline.
- `v1` Loudness to platform targets (YouTube, podcasts).

**Captions and AI**
- `v1` Captions from the transcript: styles in your brand, burned in or as SRT/VTT (SRT already in the sandbox).
- `v1` Title, description and chapters (already in the sandbox).
- `v2` Find the best 30-second moments for Shorts and Reels, with reasons.
- `v2` B-roll suggestions from your own library.
- `v2` Captions translated (Apple Translation).

**Export**
- `v1` Presets: YouTube 1080p and 4K, LinkedIn, Instagram and TikTok 9:16, Shorts, podcast audio, GIF, ProRes master.
- `v1` Hardware encoding (H.264, HEVC, ProRes) with VideoToolbox; render in the background.
- `v2` HDR export.

**Not building:** 360° and spatial video, third-party FxPlug effects, Motion templates, advanced colour grading wheels and scopes at first.

**How:** AVFoundation (`AVMutableComposition`, `AVVideoComposition`), Core Image for effects, VideoToolbox, SpeechAnalyzer, Vision (tracking, segmentation, saliency), Accelerate (beat and silence detection), DeepFilterNet.

### Cole · Audio (from Audacity)

**Recording**
- `v1` Record from any microphone; level meters; count-in.
- `v1` Record your Mac's own sound or one app's sound (Core Audio process taps, macOS 14.2+) for calls and screen-recording audio.
- `v1` Multi-track: several voices, music, effects.

**Editing**
- `v1` Waveform and spectrogram views; zoom; scrub.
- `v1` Cut, copy, paste, delete, split, join, duplicate; move clips; snap.
- `v1` Volume envelopes (draw the level over time); fade in and out; crossfade.
- `v1` Labels and markers; chapters for podcasts.
- `v1` Find and remove silences; remove filler words using the transcript.
- `v1` Unlimited undo and history.

**Effects**
- `v1` Normalise, amplify, compressor, limiter, gate.
- `v1` EQ (graphic and parametric), high-pass for rumble.
- `v1` Noise reduction and voice isolation (DeepFilterNet; Apple's voice processing where available).
- `v1` Change speed, tempo or pitch independently.
- `v1` Reverse, fade, silence, trim.
- `v1` Loudness normalisation to −14 or −16 LUFS (podcasts, streaming).
- `v2` De-click, de-ess, reverb.
- `v2` Host Audio Unit plug-ins you already own.

**Export**
- `v1` WAV, AIFF, M4A (AAC), FLAC; MP3 (LAME, linked separately because of its licence).
- `v1` Chapters and artwork embedded for podcasts.
- `v2` Batch export and processing chains (Johnny's automations replace Audacity's macros).

**AI (Cole)**
- `v1` Transcript, summary and show notes.
- `v1` Level two speakers so neither is too loud or quiet.
- `v2` "Studio sound": clean-up, EQ and loudness in one step.

**How:** AVAudioEngine, Audio Units (`AVAudioUnitEQ`, `AVAudioUnitTimePitch`), Core Audio process taps, Accelerate (waveforms, spectrograms), `libebur128` (loudness), DeepFilterNet, LAME.

---

### Harris · Learn › Languages (from Duolingo)

**Course**
- `v1` Pick a language from those Apple supports on device for speech and translation.
- `v1` Placement test to start at the right level.
- `v1` A path from A1 to B2 (the CEFR levels): units of short lessons, each 5–10 minutes.
- `v1` Lesson types: words with pictures, listening, speaking, translating both ways, fill the gap, match pairs, dictation, build a sentence.
- `v1` Pronunciation feedback: what you said is transcribed on the Mac and compared with what you meant to say.
- `v1` Mistakes come back in spaced reviews (the same engine as flashcards).
- `v1` Short stories at your level, read aloud with natural voices, with questions after.
- `v1` Grammar tips when you need them, not before.
- `v2` Conversation practice with a character: by text first, then by voice (speech in, the language model, speech out). Uses Apple's on-device model where it supports the language, Claude if you allow it.
- `v2` Roleplays: ordering coffee, a job interview, a doctor's visit.
- `v2` Learn from your life: words from your own emails, documents and calendar (opt-in).
- `v2` Travel phrasebook for an upcoming trip in your calendar (Leo).

**Motivation, without the guilt**
- `v1` Daily goal in minutes; reminder at the time you choose.
- `v1` Progress: words known, level estimate, minutes this week.
- `v1` Streaks optional and off by default.
- `no` Hearts or energy limits, ads, leaderboards.

**Honest limit:** Duolingo's courses are hand-polished over years. 11am's lessons are generated and checked, so expect strong vocabulary, listening and speaking practice, and less polish in the early units of less common languages.

**How:** AVSpeechSynthesizer (premium on-device voices), SpeechAnalyzer (speech in), Apple Translation framework, Apple's on-device model, Harris's spaced-repetition engine.

### Harris · Learn › Everything else

Already in the sandbox: flashcards with spaced repetition, cards from your notes, learning paths. Plus:
- `v1` Habits from Health (with Leo), without streak pressure.
- `v2` Quizzes from any document or PDF (Bolton).

---

### Johnny · Build › Terminal (from Terminal)

- `v1` Tabs, split panes, windows; restore sessions after restart.
- `v1` Profiles and themes, including one that matches 11am's look; fonts, ligatures, true colour, emoji.
- `v1` Fast GPU rendering (`libghostty` or SwiftTerm).
- `v1` Shell integration: each command marked; jump between commands; exit status shown.
- `v1` Search the scrollback; copy mode; clickable links and file paths.
- `v1` Command history search (fuzzy).
- `v1` Ask Johnny for a command in English, with an explanation; nothing runs until you press Return (already in the sandbox).
- `v1` Explain this output or error; fix the last error.
- `v1` Risky commands (delete, sudo, piping downloads into a shell) ask twice (already in the sandbox).
- `v1` Notification in the notch when a long command finishes.
- `v1` Open a terminal in any folder from Files.
- `v2` SSH hosts with keys stored in Keychain.
- `v2` Quick terminal that drops down from the notch.
- `v2` Secure keyboard entry when typing passwords.

### Johnny · Build › Scripts (from Script Editor)

- `v1` Write and run AppleScript and JavaScript for Automation, using macOS's own scripting engine (OSAKit).
- `v1` Syntax highlighting, formatting, compile, run, stop; result and event log.
- `v1` Dictionary browser: what each scriptable app can do.
- `v1` Open and save `.scpt`, `.applescript`, `.scptd`; export as a double-clickable app.
- `v1` Script library you can run from the notch, a shortcut key, a schedule or an automation.
- `v1` Run Shortcuts by name and use their results.
- `v1` Shell, Python and other scripts alongside, run in the terminal engine.
- `v1` Write a script from English; explain a script; fix an error.
- `v1` Before a script runs, Johnny shows which apps it will control and asks once.
- `no` Recording actions (Apple's recording support is too patchy to rely on).

### Johnny · Build › Automations (from Notion's buttons and automations)

- `v1` Triggers: time, a file arriving in a folder, an email matching a rule, a calendar event, a database change, a button.
- `v1` Steps: any agent action, scripts, shell commands, conditions, loops over items, approvals.
- `v1` Run history with logs; retry; pause.
- `v1` Forms that write into a sheet or database.
- `v2` Mini-apps: small tools Johnny builds for you, kept in a sidebar or the notch.
- `v1` Tune: change how 11am looks and behaves by describing it (already in the sandbox for the look).

---

## 4. What you'd still keep

| Keep | Why | Cheapest option |
|---|---|---|
| Your email addresses | 11am is a mail app, not a mail host | Whatever you have; iCloud+ includes custom-domain email |
| A Google or Microsoft account | For people who want to co-edit with you live | Free accounts are enough |
| Payroll software (only if you have employees) | Single Touch Payroll reporting needs STP-enabled software | Xero's smallest plan covering your headcount, or an STP-only app |
| An e-signature service (only when others must sign) | Signing requests need a hosted audit trail | A free tier, until 11am adds it |
| Final Cut Pro (only for heavy pro work) | Multicam features, 360°, plug-ins | Hand off through FCPXML when needed |

Everything else on your list can go.

## 5. Suggested build order

Ordered by what saves the most money and gets used every day, and by which engine unlocks the most apps.

| Step | Build | Unlocks | Retires |
|---|---|---|---|
| 1 | **Accounts and sync** + Marc's learned triage + Leo's Calendar | Mail, Calendar, meeting prep | AI mail apps; makes the brief real |
| 2 | **Document engine** + Notes + PDF | Write, Notes, PDF, Preview | Google Docs (for you), Notes, Acrobat, Preview |
| 3 | **Grid engine** + Money ledger | Sheets, Notion databases, Xero bookkeeping | Google Sheets, Notion, most of Xero |
| 4 | **Canvas engine** | Design, Decks, Photo-lite | Canva, Google Slides, light Photoshop |
| 5 | **Media engine** | Video, Audio, meeting recordings | Final Cut (for creator work), Audacity |
| 6 | Johnny's Terminal, Scripts, Automations | Build | Terminal, Script Editor, Notion automations |
| 7 | **iPhone app** | Energy (Health), capture, scanning | Health habits apps |
| 8 | Harris's language course | Languages | Duolingo |
| 9 | Leo's Tasks | Tasks, promises from mail, Reminders sync | Notion projects and tasks, Todoist, Things |
| 10 | Bolton's pages | Sub-pages, live blocks, versions, comments the agents answer, Notion import with nesting | Notion pages |
| 11 | Conner's Business, finished | People and companies from mail, what's happened from mail and meetings, forecast, proposals | Notion CRM boards |
| 12 | The agents connected | Time blocking from Tasks, meeting prep with open deals, the person card in Mail, reply nudges | Manual copying between apps |
| 13 | Marc's toolkit | Snippets with fill-in fields, send later, receipts to Money, meeting requests to Leo, agreements to sign | Text expanders, mail schedulers |
| 14 | Bolton's Notes extras | Smart folders, locked notes, voice notes written out on the Mac | Apple Notes' locked notes, voice memo apps |
| 15 | George's money in | Quotes that become invoices (deposit then balance), repeating invoices, overdue reminders Marc drafts for you to approve, lock dates and an audit trail, bills to pay in Leo's Tasks | The rest of Xero's invoicing |
| 16 | George's Sheets, finished | Conditional formatting, validation (lists, tick boxes, limits), comments George answers, Clean a column, earlier versions; rules and lists in and out of Excel files | The rest of Google Sheets for one person |

The sandbox has every step built: accounts, Mail and Calendar (0.5), documents, Notes and PDF (0.6), Sheets and the Money ledger (0.7), Design and Decks (0.8), Video and Audio (0.9), Johnny's Terminal, Scripts and Automations (0.10), the iPhone app (0.11), Harris's language course (0.12), Leo's Tasks (0.13), Bolton's pages (0.14), Conner's Business (0.15), the agents connected (0.16), Marc's toolkit (0.17), Notes extras (0.18), George's money in (0.19) and George's Sheets (0.20). Notion is fully replaced; for a business without staff, so is Xero's invoicing.

## 6. Sources

- [Xero AU price changes from 1 July 2026 (official)](https://www.xero.com/au/pricing-plans/update/)
- [Xero pricing for sole traders (Rounded)](https://rounded.com.au/blog/xero-pricing-explained-for-sole-traders) · [Xero plans guide (Digit)](https://digit.business/insights/xero/xero-pricing-plans-australia-guide)
- [Adobe Acrobat pricing (US, official)](https://www.adobe.com/acrobat/pricing/pricing.html) · [Acrobat for business, Australia (official)](https://www.adobe.com/au/acrobat/business/pricing.html)
- [Photoshop 2026: Generative Fill with reference images (Fstoppers)](https://fstoppers.com/photoshop/photoshop-2026-introduces-generative-fill-reference-image-900162) · [Photoshop 2026 hidden features (Digital Camera World)](https://www.digitalcameraworld.com/tech/software/photoshop-2026-is-here-but-its-best-features-are-actually-hidden-heres-what-you-missed-and-where-to-find-it) · [Photoshop 2026 review and pricing](https://create-tools-hub.pages.dev/tools/traditional/adobe-photoshop/)
- [Apple Creator Studio (Engadget)](https://www.engadget.com/apps/apple-creator-studio-is-now-available-for-13-per-month-whats-included-and-what-it-means-for-creators-130000475.html) · [Creator Studio (Macworld)](https://www.macworld.com/article/3031215) · [Creator Studio pricing analysis (RedShark)](https://www.redsharknews.com/apple-creator-studio-features-pricing-analysis)
- [Canva's Creative OS and free Affinity (eCommerceNews AU)](https://ecommercenews.com.au/story/canva-unveils-ai-driven-creative-os-offers-free-affinity-suite) · [Affinity becomes free (heise)](https://heise.de/-10964820) · [Canva Pro overview](https://subger.com/en/service/canva-pro)
- [Notion AI review 2026 (eesel)](https://eesel.ai/blog/notion-ai-review) · [Notion pricing 2026 (ToolScout)](https://toolscout.pages.dev/notion-pricing-2026) · [Notion 3.0 agents (Gmelius)](https://gmelius.com/blog/notion-ai-agents-review)
- [Gemini in Docs, Sheets, Slides and Drive (The Next Web, March 2026)](https://thenextweb.com/news/google-brings-gemini-deeper-into-docs-sheets-slides-and-drive-with-new-beta-features) · [Google AI Pro annual plan (TechRadar)](https://www.techradar.com/computing/artificial-intelligence/google-ai-pros-new-annual-subscription-brings-you-big-savings-heres-how-it-compares-to-chatgpt)
- [Audacity changelog (official)](https://www.audacityteam.org/changelog/) · [Audacity 4.0 released (Phoronix)](https://phoronix.com/news/Audacity-4.0-Released)
- [Duolingo Max review (StoryLearning)](https://storylearning.com/duolingo-max-review) · [Is Duolingo Max worth it (Nibble)](https://nibble-app.com/blog/is-duolingo-max-worth-it) · [Duolingo Q4 earnings call highlights](https://www.marketbeat.com/instant-alerts/duolingo-q4-earnings-call-highlights-2026-02-26/)
- [Apple Notes Markdown import and export (MacRumors)](https://www.macrumors.com/how-to/ios-import-export-markdown-apple-notes/)
- [HealthKit not available to macOS apps (Apple Developer Forums)](https://developer.apple.com/forums/thread/842184)
- [SpeechAnalyzer vs Whisper (MacRumors)](https://macrumors.com/2025/06/18/apple-transcription-api-faster-than-whisper) · [A quick look at SpeechAnalyzer (addpipe)](https://blog.addpipe.com/apple-speechanalyzer-api/)
- [Single Touch Payroll in detail (ATO)](https://ato.gov.au/businesses-and-organisations/hiring-and-paying-your-workers/single-touch-payroll/in-detail) · [STP guide (Sleek)](https://sleek.com/au/resources/single-touch-payroll-guide/)
- [Basiq pricing (CDR bank data)](https://basiq.io/pricing)
- [Superhuman vs Shortwave (Zapier)](https://zapier.com/blog/shortwave-vs-superhuman/) · [Superhuman](https://Superhuman.com)

Prices from non-official sources are marked "about" above. Canva's and Notion's own pricing pages couldn't be fetched from the research environment, so check them before relying on the totals.
