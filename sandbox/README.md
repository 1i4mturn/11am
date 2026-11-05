# 11am sandbox

A small native Mac app for settling the look and the core behaviour before building the real thing. It's more than the canvas mockups (it runs, uses your calendar, indexes your files, thinks on your Mac and lives in the notch), but it's not the product yet.

## Run it (about 5 minutes)

You need **macOS 14 or later** and **Xcode 26** (free from the App Store). Apple's on-device model needs **macOS 26 with Apple Intelligence turned on**.

```bash
cd ~/Projects/11am/sandbox
./setup.sh
```

`setup.sh` installs [XcodeGen](https://github.com/yonaskolb/XcodeGen) with Homebrew if needed, generates `ElevenAm.xcodeproj` and opens it. Press **⌘R** in Xcode.

If Homebrew isn't installed: get it from [brew.sh](https://brew.sh), then run `./setup.sh` again.

The app is signed "to run locally" (no Apple Developer account needed). Because the signature changes on each build, macOS may ask again for Calendar or Keychain access after a rebuild. That's normal for a sandbox.

## What's in it

| Part | What it does | Try this |
|---|---|---|
| **Vellum shell** | A window you can see through: the desktop reads through the sidebar, sheets are frosted white paper, real brand monograms and wordmark | Move the window over a busy wallpaper or other windows. Switch dark mode |
| **The notch** | Black island that grows out of the camera notch. Idle ears, hover to peek, click to open: **Now**, **Ask**, **Overnight** | Move the pointer to the notch. Press **⌥Space** anywhere to ask |
| **Brain** | Routes each request to the cheapest brain that can do it: Apple's on-device model → a local model server (optional) → Claude with your key (optional) | Settings › Brain. Try "On this Mac only", then "Balanced" with a key |
| **Today** (Leo) | Today from every calendar (or a sample day), the brief, an optional 11am check-in notification. With the iPhone app paired, an **Energy** card (last night against your usual, resting heart rate, heart-rate variability, steps, two weeks of sleep) and Leo shapes the brief around it | "Write my brief". **Pair your iPhone** at the top right |
| **Calendar** (Leo) | Every calendar on this Mac (iCloud, Google, Exchange) and your Outlook or Microsoft 365 calendar in one place: day, 3 days, week, month and agenda. Type events in plain words. Drag on empty time to book it, drag a block to move it (across days too), drag its bottom edge to change the length. Each event shows its join button, who's coming, your yes/maybe/no, clashes, and a **Prep me** note from Leo with your recent mail with them. **Find a time** copies your free slots into an email or holds two hours for focus. Australian public holidays and reminders that are due sit above the hours | Type "Lunch with Tom Fri 1pm at Lune" in the box at the top. Drag the kickoff onto Wednesday. Open **Find a time**, then **Copy for an email**. **Connect** for your real calendars; for 365, **Microsoft 365** signs in through Mail |
| **Tasks** (Leo) | Your tasks in an **Inbox**, **Today** (overdue first), **Upcoming** (by day), **Someday** and a **Logbook**, plus projects with sections and #tags. Type a task the way you'd say it: "Call Tom tomorrow 3pm #work !!", "Water the plants every 3 days", "Renew rego 3/12 @House", and it shows what it understood before you press Return. Repeats (every weekday, every fortnight on Monday and Thursday, three days after it's done), snoozing, steps, notes, and **Break it into steps** from Leo. Show a list as a **List**, a **Board** (To do, Doing, Waiting, Done) or a **Week** beside your calendar, and drag tasks between them. Marc adds tasks from what you promise in the mail you send ("I'll send you the deck by Friday" becomes *Send Tom the deck*, due Friday), and **Make a task** on any email. Keeps in step with **Apple Reminders**, so Siri and your iPhone add to it. **⌥⇧T** adds a task from anywhere, or start with **+** in the notch's Ask | **⋯ › Try the sample tasks**. Type "Book flights next friday 9am #travel" in the box and watch the chips. Drag a task onto **Someday**. Switch to **Board** in **Website relaunch** and drag a card to **Done**. **⋯ › Sync with Apple Reminders…** |
| **Mail** (Marc) | Every account in one inbox, sorted into **Needs you · Worth reading · FYI · Noise** by what you actually do: what you open and how soon, how long you read, what you answer, flag, snooze, archive unread or never open. On day one Marc learns from the read, replied and flagged marks your provider already keeps, and who you write to. Each email says why it's there (**Why?** shows the evidence). Archive, delete, flag, snooze, unsubscribe, block, and reply or write from the right account with a few seconds to undo. **j k e u s r a f** and **⌫** work like a mail app | Start with the sample: move an email to another lane and watch Marc learn. Then **Accounts › Add an account…**: an app password for iCloud, Gmail, Fastmail, Yahoo or any IMAP, or **Sign in with Microsoft** for Outlook and Microsoft 365. Open **How Marc sorts** (the brain button) |
| **Write** (William) | Formatted documents that stay plain Markdown files on your Mac: headings, bold and italic, highlight, lists and checklists, tables, quotes and callouts, code, links and pictures, shown as a page while you type. Templates (letter, proposal, one-pager, meeting notes, report, résumé, press release), an outline, find and replace, focus and typewriter modes, and a version every 15 minutes. **Import** Word, Google Docs (as .docx), RTF, HTML and OpenDocument; **Export** a PDF with your page setup, a Word file with real headings and lists, a web page, Markdown or plain text. William rewrites a selection as a suggestion you accept or reject | Open **Welcome to Write** and try the shortcuts. Select a paragraph of the investor update and choose **In my voice**. **Export › Word** and open it in Word or Pages |
| **Notes** (Bolton) | Notes in folders, with pinning, #tags, [[links]] between notes and what links back, pictures and files kept with the note, and today's note with your calendar in it. **Pages** like a wiki: sub-pages, a page tree, breadcrumbs, favourites and icons, earlier versions to put back, and **live blocks**: a line like `{{tasks: Website relaunch}}`, `{{sheet: Budget}}`, `{{page: How we work}}` or `{{calendar: today}}` shows that live under the page. **Comments** on a page, where mentioning **@Leo**, **@Bolton** or any agent gets an answer from the page, and checkboxes go to Tasks in one click. **⌥⇧N** starts a note from anywhere. Import everything from Apple Notes (folders kept), Markdown, or a **Notion export with its nesting** (databases become workbooks in Sheets); export it all as Markdown. **Ask** answers from your notes and names the ones it used | Open **Acme pilot**, click the [[Board deck]] link, tick a box. Press **Today**. Ask "what does Tom need before go-live?" For pages: **⋯ › Try the sample pages**, then in **Website relaunch** tick a task in its live block, press the checklist button to send its checkboxes to Tasks, and open **Comments** to ask "@Leo what's left?" |
| **Files** (Bolton) | Local index of folders you choose (PDF, Word, RTF, Markdown, text), with name, content and meaning search | Add a folder, search, then "Ask Bolton about these results" |
| **PDF** (Bolton) | Read with thumbnails, contents and search; highlight, underline, strike out, sticky notes, text boxes, drawing and your signature (drawn or typed, kept for next time); fill in forms. **Pages**: drag to reorder, rotate, duplicate, delete, insert from other files, save some pages, split. Combine PDFs and pictures. **Compress**, **protect with a password** (and turn off printing or copying), **flatten**, remove hidden details, make scanned pages searchable, and **redact for real**: what's under the boxes is removed from the file, then checked. Ask Bolton for a summary, the key points, or the dates, money and obligations, with page numbers | **Try a sample agreement**, highlight a line, sign at the bottom. Mark the bank account with the redaction tool and **Apply**. Switch to **Pages** and drag page 2 first |
| **Research** (James) | A WebKit browser with James beside it: summarise or ask the page, add pages as sources, then a report that cites them, sent to Write | Open a start-page link, **Add to sources**, then ask a question under **Report** |
| **Money** (George) | Proper books, with Australian GST. **Bank**: import statements (CSV, OFX or QIF from any bank; duplicates skipped) and reconcile: George suggests the match (a payment for an invoice, a payee coded like last time, a transfer between your accounts) and you press **OK**, or **Accept the sure ones** for all of them. **Invoices** and **Bills**: write them with GST per line, approve, record payments, void, save a tax invoice PDF or email it with the PDF attached. **Contacts** with what each owes. **Reports**: profit and loss, balance sheet, cash, trial balance, owed to you and you owe (by how late), for any month, quarter or financial year, and the **accountant's pack** as one Excel file. **GST**: the quarter's BAS figures (G1, G3, G10, G11, 1A, 1B) on cash or accrual, with the due date. The overview still has cash, burn and runway, and George answers from the books | Open **Bank** and press **OK** on the Kestrel payment. Open **Invoices**, pick INV-0004 and **Record payment…**. Look at **GST**, then **Reports › Accountant's pack…** |
| **Sheets** (George) | Spreadsheets with live formulas: about 110 Excel functions (SUMIFS, XLOOKUP, INDEX/MATCH, TEXT, dates, PMT, NPV, IRR…), typed money, percentages and dates understood, a fill handle that continues series and copies formulas, frozen header rows, sort, insert and delete rows and columns (formulas everywhere follow), number formats, bold, colours, several sheets per workbook, copy and paste with other apps, undo. **Charts** (column, bar, line, area, pie, scatter) and **Summarise** (a live pivot of a table, with a chart). **Open and save Excel files** and CSV, export PDF. George writes a formula from a sentence, explains one, answers questions from the sheet or makes a new sheet | In **Budget**, drag the fill handle under F7 down a row. Select B2:E7 to see the sum at the bottom. **Summarise** the **Sales** sheet by Client. **Ask George** "total of Amount where Region is North" |
| **Business** (Conner) | The pipeline as a board: drag deals between stages, weighted value, "going quiet" nudges, follow-ups drafted in your voice | Drag a deal to **Proposal**, open it, **Draft follow-up** |
| **Design** (Robert) | A canvas for every size: social posts, stories, LinkedIn and YouTube, email headers, link previews, slides, A4, posters, flyers, business cards and logos. Templates (announcement, quote, big number, event, hiring, launch, photo and caption) laid out from your brand kit, or **Make me a graphic…** from a sentence. Text, shapes, lines and arrows, pictures (drop them in) and QR codes; move with snapping guides, resize from any handle, rotate, group, align and distribute, lock, layer order, copy and paste. The inspector sets fonts, weight, spacing, colours and gradients, outlines, corners and shadows, picture fit, and removes a picture's background on this Mac. **Resize into** another size as a new design; export PNG, JPEG, PDF or SVG. Image tools and the brand kit are still here | Open **Founder breakfast**, change the headline, drag it until the centre guide shows. **Export › Resize into a new design › Instagram post**. **Make me a graphic…** "we hit 1,000 customers" |
| **Decks** (Conner) | Slides on the same canvas: thirteen layouts (title, section, statement, points, two columns, picture, big number, quote, chart, table, team, timeline, closing), five themes or your brand kit, a slide sorter, speaker notes. Change the words and the slide lays itself out again; move things by hand and it remembers. New decks from an outline, a document in Write, or a draft from Conner. **Present** full screen with the arrow keys, with a presenter view (notes, next slide, timer) on a second display. Export PDF, PowerPoint or pictures | Open **Seed round**, click the chart slide and change a bar. Switch the theme to **Ember**. **Present** (⌥⌘↩), then esc |
| **Photo** (Robert) | Non-destructive photo editing: looks, light, colour, three colour wheels, colour by colour, curve, sharpen, noise, fade, vignette, grain and .cube LUTs. Crop to a shape, straighten (or **Auto** level the horizon), rotate, flip. **Clean up** paints out dust, spots and small distractions. **Cut out** removes the background. RAW files open too. Undo, before/after, export JPEG, HEIC, PNG or TIFF at full resolution | Press **Auto**, then try a look. **Crop** › 4:5 and drag the corners. **Clean up** › paint over the sun |
| **Video** (Cole) | A real timeline: add clips, drag their edges to trim, **⌘B** to split at the playhead, reorder, duplicate, speed (¼× to 4×). Each clip has its own grade (the same colour panel as Photo), volume and mute. **Clean up the voice** runs Apple's Voice Isolation, a rumble filter and levelling on this Mac; **Cut the pauses** takes out the dead air (one clip or all of them, and puts it back). A **music bed** under the whole movie that loops, fades with it and turns itself down whenever someone talks. **Titles**: lower thirds, title cards and end cards in your brand kit's colours and fonts, and **captions burned into the picture** from the transcript. Reframe for 9:16, 1:1 or 4:5. Dip to black or white between clips, fade in and out. Transcribe a clip and strike lines to cut them. Export H.264, HEVC, 720p, ProRes or sound only, as it is or at −14 or −16 LUFS, plus captions (.srt) | **Try two sample clips**, drag the second clip's left edge, grade it with **Teal & orange**, switch the shape to **9:16**. In **Titles**, add a **Lower third** and type a name. In **Sound**, press **Sample bed** and play |
| **Audio** (Cole) | A multitrack sound editor for podcasts, voice-overs and calls. **Record** from the microphone or **this Mac's sound** (a call, a video; 11am's own sound is left out), with a level meter. Import WAV, AIFF, MP3, M4A, FLAC or CAF, or the sound from a video. Tracks with mute, solo, volume and pan; clips you drag, split (**⌘B**), duplicate (**⌘D**), delete (**⌫**, the rest closes up), fade and turn up or down; markers (**M**) that become chapters. **Effects** on a clip or a selected stretch: louder or quieter, normalise, loudness, fades, rumble filter, voice presence, warmer, brighter, telephone, compressors, limiter, noise gate, tempo without changing pitch, pitch, reverse, silence. **Clean up**: **Studio sound** (Voice Isolation, then a voice chain), **Remove long silences**, **Transcribe**, and **Remove ums and uhs** by the word. The panel shows the mix's loudness, the silences found, chapters to copy and Cole's show notes. Export WAV, AIFF, M4A or FLAC as it is or at −14, −16, −19 or −23 LUFS, with a chapters file. Undo and redo throughout | Open **Founders' hour · episode 12** (made on this Mac with its own voices), play it with **space**, select the first clip and choose **Effects › Voice compressor**. Open **Silences** and **Remove them**. **Export › M4A › −16 LUFS** |
| **Learn** (Harris) | **Languages**: a course from beginner (A1) to upper intermediate (B2) in short lessons. It covers words with pictures, listening, speaking (what you say is compared word by word), translating both ways, filling the gap, matching pairs, dictation and building sentences. Mistakes come back in reviews until they stick, there are short stories read aloud with questions, a placement test, and grammar tips when you first need them. Spanish and French ship with written units. Italian, German, Portuguese, Japanese, Mandarin and Korean are written by Harris as you go. There's a daily goal and an optional reminder, and streaks only if you want them; no hearts, no ads. **Cards and paths**: flashcards with spaced repetition, cards made from your notes, learning paths | **Learn › Languages › Spanish**, then **Continue**. In lesson 3, press **Press and speak** and say the sentence. Try the **Placement test** |
| **Build** (Johnny) | **Terminal**: a real terminal (zsh or your shell, full-screen programs like vim, htop and ssh work) with tabs, split panes, 256 and true colours, search, clickable links and file paths (⌘-click), your command history searchable by a few letters, and tabs that come back after a restart. Each command is marked with its exit status (a green or red bar), ⌘↑ and ⌘↓ jump between them. **Ask Johnny** for a command in plain English, **Explain** what the last one printed, **Fix it** when it fails; Johnny only ever types, never presses Return, and commands that can delete or change things ask twice. A notification when a long command finishes while you're elsewhere. **Scripts**: AppleScript, JavaScript for Automation, shell and Python in one library, coloured as you type, checked without running, run with the result and log, each app's scripting dictionary to browse, Open and save .applescript, .scpt and .scptd, export as a double-clickable app, and your Shortcuts. Johnny writes, explains and fixes scripts, and asks once before a script controls an app. **Automations**: a trigger (a button, a schedule, a file arriving in a folder, an email, a calendar event) and steps (shell, scripts, an agent, read a document, conditions, for each, ask me first, add to a note, notify, Shortcuts), with a history of every run and its log, retry and stop. **Tune 11am** and **Make a colour look** are still here | **Terminal**: try `ls -la`, then type `false` and press **Fix it**. ⌘D splits, ⌘T opens a tab, ⌥⌘R searches your history. **Scripts**: run **Say the time**, then **Unread mail** (it asks first). **Automations**: open **Tidy screenshots off the Desktop** and press **Run** |
| **Overnight** | Heavy jobs wait for the charger, a cool Mac and idle time or your overnight window. Writes tomorrow's brief ahead of time | "Run Now" to see it work immediately. **⇧⌘R** does the same |
| **The Suite** | The apps that replace the subscription pile, and which ones are in this sandbox | Look, react, tell us what's missing or unnecessary |
| **Design Lab** | Live sliders for paper tone, frost, **clarity** (how much of the desktop shows through), grain, depth, ink, **motion**, radius, display face and backdrop. Starts from your round-one picks | Tune it until it feels right, then **Copy Values** and paste them into your feedback |

Shortcuts: **⌘1–⌘9** switch between the first nine apps · **⌘Z / ⇧⌘Z** undo and redo in Photo, Video, Audio, Sheets, Design and Decks · in a language lesson, **↩** checks and continues, **esc** stops · **⌘B** splits, **⌘↩** plays and pauses, **⌘⌫** removes a clip in Video · in Audio, **space** plays, **⌘B** splits, **⌫** deletes and closes the gap, **⌘D** duplicates, **M** drops a marker · **⇧⌘N** writes a new email (a new event in Calendar, a new note in Notes) · **⌥⇧N** jots a note from anywhere · **⌥⇧T** adds a task from anywhere · in Write and Notes, **⌘B ⌘I ⌘U ⌘K ⌘E**, **⌥⌘1–3** headings, **⇧⌘7 ⇧⌘8 ⇧⌘L** lists, **⌘F** find and replace · in Calendar, **T** today, **← →** move, **D 3 W M A** change the view, **↩** edits, **⌫** deletes · in Sheets, arrows move (**⌘** jumps to the edge of the data, **⇧** selects), type to replace, **↩** or **F2** to edit, **⌘D** fills down, **⌘B ⌘I** bold and italic · on a canvas, arrows nudge (**⇧** for 10), **⌘D** duplicates, **⌘G / ⇧⌘G** group and ungroup, **⌘] ⌘[** layer order, **⌘L** locks, **↩** edits text, hold **⌘** while dragging to skip snapping · **⌥⌘↩** presents a deck · **⌘\\** shows or hides the agent pane (it also steps aside on narrow windows) · **⌥Space** asks from anywhere · **⇧⌘R** runs tonight's work now · **⌘,** opens settings.

Screenshots from the CI Mac (a small virtual display without a notch, so the notch shows as a pill, with a busy test desktop behind the app) are on the `ci/sandbox-shots` branch. Push a commit with `[shots]` in its message to refresh them.

## Your iPhone (11am for iPhone)

The iPhone app is where you stay in touch while away from the Mac. It has four tabs:

- **Today**: Leo's brief and your day from the Mac, the Energy line, and **Ask your Mac**, which your Mac answers with its own brain.
- **Energy**: Apple Health, read only. Last night's sleep against your own usual, when you fell asleep and woke, steps, active energy, exercise, stand hours, resting heart rate and heart-rate variability, and workouts. Each is charted, with what it means for the day ("Short night. Put the hardest work after 10."). It compares you with you, and gives no medical advice.
- **Capture**: scan a document (edges found, flattened, text recognised, saved as a PDF), take a photo, record a voice note (transcribed on the iPhone), write a note, or save a link. Each goes to Notes on the Mac (in Captures, or Receipts with #receipt), with the files in `~/Documents/11am Captures`. If the Mac isn't around, captures wait on the phone and go when it is.
- **Mac**: pairing and the connection.

**How they talk.** The Mac makes a pairing code (Today › **Pair your iPhone**, or 11am › Settings › iPhone). It's a QR code holding a key made on the Mac. The iPhone scans it once. After that they find each other on your Wi-Fi (Bonjour) and every message is sealed with that key (ChaChaPoly). There's no server, no account and no iCloud in between. Health data never leaves the two devices, and Leo uses it only in your brief.

**Putting it on your iPhone.** It isn't on the App Store, so Xcode installs it from this project:

1. Run `./setup.sh` on the Mac as above. In Xcode, choose the **ElevenAmPhone** scheme at the top.
2. Plug in your iPhone, unlock it and tap **Trust**. On the iPhone, turn on **Settings › Privacy & Security › Developer Mode** (it restarts).
3. In Xcode, open **Settings › Accounts** and add your Apple ID. Then, in the **ElevenAmPhone** target › **Signing & Capabilities**, pick it as the **Team**. If Xcode says the bundle identifier isn't available, change it to something of your own, such as `au.yourname.11am`.
4. Choose your iPhone as the destination and press **⌘R**. The first time, the iPhone asks you to trust the developer under **Settings › General › VPN & Device Management**.
5. On the Mac, choose **Today › Pair your iPhone › Make a pairing code**. On the iPhone, open **Mac › Scan the code**, and allow Local Network when asked (on both). Then allow Apple Health in **Energy**.

**With a free Apple ID**, Xcode-installed apps stop opening after 7 days. Press ⌘R again to renew. A paid Apple Developer Program membership makes it a year.

**HealthKit and free accounts.** I couldn't confirm whether Apple lets a free account (a "Personal Team") use HealthKit. If Xcode reports that your team doesn't support HealthKit, there are two options. You can join the Apple Developer Program, or you can remove the **HealthKit** capability in Signing & Capabilities: everything else works, and Energy offers sample data instead.

**Tested on every build** (`ci/PhoneTests`):
- What last night means: a short night, a good one, an ordinary one, a late bedtime, and the body working harder than usual.
- Pairing codes.
- Sealed messages: a wrong key or a changed message is refused.
- Framing.
- A real connection on the CI Mac: a 3 MB photo arrives intact, and a device without the key is cut off.
- Bonjour discovery: the test reports whether the CI machine could do it.

The iPhone app is built for the simulator on every push, and screenshots come from the simulator with sample data. The camera, scanning, Health and the connection between two real devices can only be tried on your iPhone.

## Languages: how Harris teaches

**The course.** Each unit has about ten words and eight sentences at one level, a grammar tip and sometimes a short story. Each unit has three lessons:
1. Meet the words with pictures, match them, and hear them in sentences.
2. Translate, build sentences from tiles, and fill gaps.
3. Speak, take dictation, and write in the language.

The first units of Spanish and French are written by hand and tested (every word taught once, sentences built from words already taught). Later units, and every other language, are written by Harris through your brain (Apple Intelligence or Claude) and checked before they're used: right shape, enough words and sentences, nothing empty or repeated, story questions with real answers. Generated units are good for vocabulary and practice. Expect less polish than a course a team has refined for years.

**Checking answers** forgives capitals, punctuation and a small typo, and accepts other natural English (“I'd like a coffee” for “I want a coffee”). A missing accent counts as right, with a note to watch it.

**Speaking** uses this Mac's speech recognition (on-device where the Mac supports the language) and compares what it heard with the sentence word by word, marking each word heard or missed.

**Reviews** use the same boxes as the flashcards: right answers wait longer each time (a day, three days, a week…), wrong ones come back in ten minutes. Due reviews are woven into lessons as well as having their own **Review** button.

**The placement test** asks up to four questions at each level and stops early once a level is too hard. It starts you at the next level after the last one you passed.

**Voices** are the Mac's own. The premium voices sound much better: download them in **System Settings › Accessibility › Spoken Content › System Voice › Manage Voices**.

**Tested on every build** (`ci/LanguageTests`):
- The written courses: each word taught once, sentences use taught words, answerable stories, and placement questions at every level.
- Lessons built from units: the same each time, with tiles and gaps that contain the answer, and earlier mistakes woven in.
- Answer checking: accents, typos, other English, apostrophes.
- Pronunciation scoring.
- The review boxes, placement levels, minutes and streaks.
- Reading units Harris writes, and refusing broken ones.

## Tasks: how Leo keeps them

**Lists.** The **Inbox** holds tasks with no date and no project. **Today** has what's due today or overdue (overdue first, then the most important), and anything whose start date has come. **Upcoming** has the future, grouped by day. **Someday** is for ideas. The **Logbook** has what you've ticked off. A task added while you're looking at a list takes that list's meaning: added in Today, it's due today; added in a project, it's in the project.

**Quick add** understands:

| You type | It becomes |
|---|---|
| tomorrow, tonight, friday, on sun, next monday, next week, this weekend, end of month | a due day (tonight is 6 pm; "next monday" is the Monday of next week) |
| 3pm, at 9, 5:30, 15:45, tomorrow morning | a time (a lone "at 3" or "5:30" means the afternoon) |
| 12 March, March 14th, 3/12, 2026-12-01 | a date (3/12 is 3 December outside the US; a date that's passed means next year) |
| in 3 days, in 2 hours, in a fortnight | counted from now |
| every day, every weekday, every 2 weeks, every mon and thu, fortnightly, monthly | a repeat |
| start monday, from 3 March | hidden until then |
| !, !!, !!!, p1 | priority |
| #tag, @project, someday | a tag, a project, Someday |

Words in "double quotes" are left alone, and short day names only count after "on", "by", "this" or "next", so "sun cream" stays sun cream.

**Repeats** come back when you tick them off. If you missed a few, the next one is from today, not a pile of overdue copies. **Count from when it's done** suits chores like watering plants.

**Snooze** hides a task until later today, this evening, tomorrow, the weekend or next week.

**From the other agents.** After you send an email, Marc looks for promises in the words you wrote (not the message you were replying to or your signature): "I'll…", "I will…", "Let me…". Each one becomes a task with the person's name and the date you said, and shows the sentence it came from. Questions and "I'll be…" don't count. Turn it off in **⋯**. **Make a task** on an email links back to it.

**Apple Reminders.** **⋯ › Sync with Apple Reminders…** links the Inbox to your default Reminders list and each project to a list of its name, creating lists in Reminders for new projects and projects in 11am for your other lists. Titles, notes, due dates and times (with an alert on your phone), priority, done and deleted go both ways, and whichever side changed last wins. Tags, steps, sections, start dates and repeats stay in 11am. Stopping the sync leaves both sides as they are.

**Tested on every build** (`ci/TasksTests`):
- Quick add: about 40 phrasings, including the ones that must not become dates.
- Repeats: weekdays, fortnights on chosen days, month ends, catching up after missed ones, and after it's done.
- Smart lists, ordering and snoozing.
- Promises found in a sent email, and names taken from addresses.
- The Reminders merge rules: new on either side, newer edits, ticked off and deleted.

## Pages: how Bolton's wiki works

**Pages are notes.** Every note can hold sub-pages: **+** in the bar above a note adds one, and dragging a note onto a page in the sidebar puts it inside. The sidebar shows **Favourites** (the star) and the **Pages** that nest; notes that don't nest stay in the list as before. The files stay plain Markdown in the notes folder; where each page sits, its icon and the comments are kept beside them (`.pages.json`, `.comments.json`), so deleting those loses the tree, never the words. Deleting a page moves its sub-pages up a level.

**Live blocks** are one line each, on a line of their own:

| Line | Shows |
|---|---|
| `{{tasks: Website relaunch}}` | That project's open tasks from Tasks, to tick off there and then. Also `today`, `upcoming`, `inbox`, `someday` or a `#tag` |
| `{{sheet: Budget}}` or `{{sheet: Budget!Sales}}` | The first rows and columns of a workbook in Sheets, as they display, with formulas worked out |
| `{{page: How we work}}` | Another page, always up to date (edit it on its own page) |
| `{{calendar: today}}` or `{{calendar: week}}` | Your calendar |

They show under the page, in the order they appear, rather than in the middle of the text.

**Versions.** While you write, a version is kept every ten minutes or so. The newest 20 are kept, then one a day for two months. **Versions** shows what changed since each one, and putting one back keeps what was there as a version too.

**Comments and agents.** Mention an agent in a comment and they answer from the page: "@George does the budget add up?", "@William tighten the intro". "@Leo turn these into tasks" sends the page's open checkboxes to Tasks (read the way quick add reads them, so "Call Tom tomorrow 3pm" gets its date), ticks them, and notes "→ Tasks" beside each.

**Notion.** Export from Notion as **Markdown & CSV** (with sub-pages), unzip it, and choose the folder in **⋯ › Markdown files or a Notion export…**. Pages keep their nesting under a **Notion** folder, Notion's IDs come off the names, links between pages become [[links]], folders without a page become pages, and each database comes in as a workbook in Sheets, with a page that shows it and its row pages inside. Pictures from the export aren't brought in yet.

**Tested on every build** (`ci/PagesTests`): the tree (children, breadcrumbs, moving a page into its own sub-page refused, loops), finding blocks (not in code, only whole lines), which versions are kept, checkboxes, mentions, and a Notion export's nesting with databases and folders.

## Mail: how Marc learns

- **Accounts:** IMAP and SMTP over TLS, written for 11am (no mail service in between). Passwords live in the Keychain. Gmail, iCloud, Fastmail and Yahoo work with an app password.
- **Outlook and Microsoft 365:** **Sign in with Microsoft** (OAuth with PKCE, in a system sign-in sheet; 11am never sees your Microsoft password). Mail is read over IMAP with the token and sent through Microsoft Graph, so it works even where a 365 tenant has SMTP sign-in switched off. Microsoft only lets registered apps do this, so you register 11am once (free, about five minutes); the add-account sheet walks you through it. The refresh token lives in the Keychain; access tokens are kept in memory only. Apple Mail on this Mac still works as a read-only alternative.
- **Signals, all local:** opened and how soon, reading time, replies, flags, snoozes, archived or deleted without opening, unread for three days, unsubscribes and blocks, and moving an email to another lane (the strongest).
- **The model:** 26 readable features (your history with the sender and their company, who you write to, whether it asks you something, has a deadline, is a newsletter or receipt, whether you're in To or Cc, and the fixed rules' opinion) into a small logistic regression that retrains in under a second on this Mac: after corrections, after day-one history, and overnight. Each lane comes with the reasons that weighed most, using the real numbers ("You've replied to Priya 9 of 10 times").
- **Tested on every build:** the IMAP and SMTP clients run against a small fake mail server on the CI Mac (`ci/fake_mail_server.py`, `ci/MailTests`), and the model is checked on the sample history.

## Documents, notes and PDFs: how they work

- **One document engine.** Write and Notes share it. Files are plain Markdown (with `==highlight==`, `++underline++`, `- [ ]` checklists, tables and `> [!NOTE]` callouts), so they open in any editor and never get stuck in 11am. The editor styles the Markdown as you type rather than hiding it, so what you see is exactly what's saved. Spelling, grammar, dictation and the dictionary come from macOS.
- **Word in and out, properly.** Export writes real Word heading styles (so Word's navigation pane and Google Docs' outline work), real numbered and bulleted lists, tables, links, pictures and page numbers. Import reads a .docx's own XML, so headings, list levels, checklists, quotes, code, links and tables come back as they were; Google Docs comes in through File › Download › Word. RTF, HTML and OpenDocument use the system's readers.
- **PDF export** typesets the document onto pages with your paper size, orientation and margins, the title at the top of later pages and "page 2 of 5" at the bottom. The text stays text, so it can be searched and copied.
- **PDFs.** Everything runs on PDFKit on this Mac. Redaction redraws each marked page with the boxes burnt in, adds a fresh text layer with on-device text recognition, then searches the saved file for what was under the boxes and tells you if anything survived. Compression re-saves pictures at screen resolution. Passwords use the PDF standard's encryption, so they work in Preview, Acrobat and browsers.
- **Tested on every build:** the Markdown parser, HTML, Word export (checked as valid XML and opened with the system's Word reader) and Word import, PDF export, and every PDF operation, including that redacted text is really gone (`ci/DocTests`).

## Sheets and Money: how George keeps the numbers

- **One grid engine.** Formulas are parsed into a tree and worked out lazily with a cache, in Excel's order of operations; ranges, whole columns (`A:A`), other sheets (`'Sales'!E2:E18`), named ranges, `$` references, array maths inside SUMPRODUCT and criteria with wildcards behave as they do in Excel. Circular references show `#CYCLE!` instead of hanging. A SUMIF over 20,000 rows takes a few hundredths of a second.
- **Excel files both ways.** Saving writes a real `.xlsx` (styles, number formats, frozen panes, column widths, named ranges, cached values, and the `_xlfn.` prefix newer functions need); opening reads shared strings, styles and shared formulas. Workbooks live as files in `~/Library/Application Support/11am-sandbox/Sheets`.
- **Books in cents, double-entry.** Every invoice, bill, payment and bank line becomes a balanced journal entry against an Australian chart of accounts, with the GST split out per line and tagged (GST, GST-free, input-taxed, capital, BAS-excluded), so the BAS is worked out from the same entries as the reports. Cash basis counts invoices and bills in proportion to what's been paid in the quarter.
- **George learns payees.** Coding a bank line teaches the payee (by its first two meaningful words), so "AWS EMEA 1234" and "AWS EMEA 9876" are coded alike. Matching uses invoice numbers, the contact's name and exact amounts. Nothing is reconciled without your **OK** (or **Accept the sure ones**).
- **For your accountant.** The pack is a workbook (profit and loss, balance sheet with a zero check, trial balance, general ledger, GST, aged lists and every invoice and bill) with totals as formulas, so they can follow the arithmetic. **Open in Sheets** puts the same workbook in Sheets.
- **Not tax advice.** George's GST figures come from your books; check them with your tax agent before you lodge.
- **Tested on every build:** the grid (`ci/GridTests`: functions, formats, fill, insert and delete, sort, summaries, CSV, Excel out and back in, speed) and the books (`ci/LedgerTests`: GST rounding, posting, part payments, matching, transfers, undo, BAS on both bases, every report, statement files from four banks' formats, the tax invoice and the accountant's pack).

## Design and Decks: one canvas

- **Plain data, drawn by Core Graphics.** A design or slide is a list of layers (text, shapes, pictures, QR codes) with position, size, rotation, opacity, fills, outlines and shadows, saved as JSON with pictures beside it in `~/Library/Application Support/11am-sandbox/Designs` and `Decks`. The same drawing code paints the editor, PNG and JPEG, PDF (with real, selectable text) and SVG (text kept as text, wrapped where the canvas wraps it).
- **Magic resize** keeps backgrounds full-bleed, centred things centred and corner things in their corners, and scales the type with the design.
- **Slides are layouts, not pictures.** Each layout lays out what the slide says in the theme, shrinking text to fit; charts are drawn as shapes, so they stay sharp and editable in PowerPoint. PowerPoint files have each text box, shape and picture as a real object (speaker notes go in the PDF for now).
- **Tested on every build** (`ci/CanvasTests`): align, distribute, layer order, groups, snapping, rotation-aware hit testing, magic resize, pixels in the right place (and pictures the right way up), text that wraps and shrinks to fit, PDF text, SVG, QR codes that scan, every slide layout staying on the slide, decks from an outline, re-theming, and the PowerPoint file's parts.

## Calendar: how Leo reads your calendars

- **Calendars on this Mac:** whatever macOS already syncs (iCloud, Google, Exchange, CalDAV), through EventKit. Grant access once with **Connect**; there are no extra logins. Changes you make in 11am sync back the usual way.
- **Outlook and Microsoft 365:** the same **Sign in with Microsoft** as Mail asks for calendar access too, and Leo reads and edits it through Microsoft Graph. If you signed in to Mail before Calendar existed, Leo asks once for the extra permission (**Allow**). Answering an Outlook invitation tells the organiser directly. For calendars on this Mac, invitations open in Apple's Calendar, because macOS doesn't let other apps answer them.
- **Quick add** uses the system's own date detector, so "tomorrow", "next Tue 3pm", "12 Dec" and "9:30 for 45 min" all work, with "at" or "@" for the place.
- **Find a time** looks at weekdays from 9 to 5 around everything you haven't declined. **Prep me** sends only the event and your recent mail with the people in it to the brain you've chosen.
- **Holidays** are the national ones (New Year, Australia Day, Easter, Anzac Day, Christmas, Boxing Day) with their weekend substitutes. State days such as Labour Day and the King's Birthday differ by state, so add your state's holiday calendar in Calendar settings on your Mac if you want them.
- **Tested on every build:** quick add, free time, the side-by-side layout, holiday dates and the Graph calendar calls (paging, UTC times, all-day dates across time zones, create, edit, answer, delete) run against the fake server in Sydney time.

## Build: how Johnny's terminal, scripts and automations work

- **A real terminal, written for 11am.** Your shell runs in a pseudo-terminal, and 11am's own screen engine (`Features/Build/TerminalKit.swift`) reads what programs write: xterm's cursor movement, erasing, scroll regions, the alternate screen full-screen programs use, 16, 256 and true colours, bold, italic, underline and inverse, wide characters and emoji, line drawing, bracketed paste, mouse reporting, titles and hyperlinks. Long lines re-wrap when you resize the window. It's drawn with Core Text on the GPU-backed view, character by character on a grid.
- **Shell integration** is a few lines 11am adds to zsh or bash's startup (your own `.zshrc` and prompt are loaded first and left alone). They mark each prompt, command and exit status, and say which folder the shell is in, which is how Johnny knows what you ran, what it printed, and whether it worked.
- **Johnny never runs anything on his own.** Suggestions and fixes are typed at the prompt for you to read; nothing runs until you press Return. Commands that delete, use `sudo`, pipe a download into a shell or force-push ask twice.
- **Scripts run in their own process** through macOS's `osascript` (AppleScript and JavaScript for Automation), zsh or Python, so a stuck script can be stopped and can't take 11am down. Checking compiles without running; exporting uses macOS's own `osacompile`. The library is `scripts.json` in 11am's folder. The first time a script controls an app (Mail, Finder…), Johnny lists the apps and asks once; macOS then asks for its own permission too.
- **Automations** are saved as `automations.json`, and the last 200 runs with their logs as `automation-runs.json`. Schedules are checked every 20 seconds, folders are watched by macOS as files arrive, new email and upcoming events come from Mail and Calendar. In shell steps, `{{input}}`, `{{trigger}}` and `{{item}}` go in quoted, so a file name or an email subject can't change the command. A script used in an automation must have been allowed in Scripts first. Everything starts switched off.
- **Tested on every build** (`ci/BuildTests`): the screen engine (text, wrapping, cursor, erasing, colours, scrolling, the alternate screen, wide characters, emoji and accents, status answers, titles, links, shell marks, search, re-wrapping), keys and mouse, a real pseudo-terminal, zsh and bash marking commands and exit statuses end to end; AppleScript, JavaScript, shell and Python runs, checking, compiling an app, Finder's dictionary; schedules, quoting, conditions, folder watching and whole automations running step by step.

## Audio and Video sound: what's under the hood

- **One sound engine** (`Features/Audio/AudioKit.swift`) does the maths for both apps with Accelerate: decibels, peaks, **loudness measured the broadcast way** (ITU-R BS.1770 K-weighting with gating, so −16 LUFS here is −16 LUFS on YouTube or Spotify), silence and speech finding, EQ (RBJ filters), compressor, limiter, gate, fades, tempo and pitch (Apple's time-pitch unit, rendered offline) and the multitrack mixdown.
- **Projects are plain files.** An Audio project is a JSON file with its recordings beside it in `~/Library/Application Support/11am-sandbox/Audio`. Effects make a new take of the clip's sound, so undo is instant and the original recording is never changed.
- **Recording** uses `AVAudioEngine` for the microphone and ScreenCaptureKit for the Mac's sound, so it needs **Microphone** or **Screen & System Audio Recording** permission the first time (macOS asks).
- **Ums, uhs and silences** are cut from the word timings Apple's speech recogniser gives, and from the level, with a breath of air left so speech doesn't run together.
- **In Video, the music ducks under speech** found from each clip's level, easing down a quarter-second before each line and back up after; titles are drawn with the Design canvas engine and laid over the picture in the same Core Image pass as the colour. Exporting at a loudness target mixes the movie's sound, brings it to the target under a −1 dB ceiling and puts it back under the picture (movies up to 20 minutes).
- **Tested on every build** (`ci/AudioTests`): file round trips in every format, loudness against the EBU reference tone, filters' frequency response, compressor, limiter and gate behaviour, silence and speech finding, tempo and pitch, every edit on a project (split, ripple delete, markers and words moving with it), fillers, the mix (solo, pan, mute) and the music ducking envelope.

## Photo and Video: what's under the hood

- **One colour engine for both.** Core Image does the work on the GPU. Tone, contrast, the three colour wheels (lift, gamma, gain), saturation and colour-by-colour are baked into a single 33×33×33 colour cube, so a grade costs one lookup per pixel and plays in real time on video. Exposure, white balance, highlights and shadows, vibrance, sharpening, noise reduction, vignette and grain are Core Image filters around it.
- **Looks are plain files.** Every look you save (or Johnny makes) is a small JSON file in `~/Library/Application Support/11am-sandbox/Looks`. Drop `.cube` LUTs from Resolve, Premiere or a LUT pack into **Import .cube…** and they work in both apps.
- **Clean-ups stay on this Mac.** The spot healer fills each spot from the nearby patch whose surroundings match best, colour-matched and feathered. Background removal is Vision's subject mask. Auto straighten is Vision's horizon detector.
- **Video never re-encodes until you export.** Trims, splits, speed, transcript cuts and cut pauses are an `AVMutableComposition`. Colour, reframing, dips, titles and captions are a per-frame Core Image pass. Volume, fades and the music bed's ducking are an audio mix. Voice clean-up uses Apple's `AUSoundIsolation` unit rendered offline, and falls back to a rumble filter and levelling if Voice Isolation isn't available.
- **Adding more later.** Ask Johnny for a look in plain English. For a new tool (a mask brush, keyframes, animated titles), ask Claude Code in this repo: the engine is in `ElevenAm/Media` (shared) and `Features/Photo` and `Features/Video` (the apps), and each piece is small enough to extend.

## On an 8 GB MacBook Air (M2)

This sandbox is designed around your Mac:

- **Apple's on-device model is the local brain.** It ships with macOS 26 and the system manages its memory, so 11am loads nothing extra. No model downloads, no gigabytes of RAM.
- **Heavy work waits.** Indexing and the brief run overnight, on the charger, when the Mac is cool, or after 20 idle minutes. They pause in Low Power Mode.
- **The index stays small.** A few thousand characters per file and a compact on-device sentence embedding (Apple's NaturalLanguage framework). Up to 4,000 files.
- **Native everything.** No Electron, no Docker, no bundled browser engine.
- **Optional cloud.** For bigger thinking, add a Claude API key. You choose the model and set a monthly cap, and 11am stops using Claude when the cap is reached.

## Using your Claude credit

Yes, you can, with one catch: **a claude.ai Pro or Max subscription can't be used as an API key.** The API is billed separately:

1. Go to **platform.claude.com**, sign in, add credit (prepaid) and create an API key.
2. In 11am: **Settings › Brain › Claude**, paste the key, then **Test**. The key is stored in the macOS Keychain.
3. Choose a model and a monthly cap.

Prices per million tokens (Anthropic API, October 2026):

| Model | In | Out | Good for |
|---|---|---|---|
| Claude Opus 5.5 (default) | US$4 | US$20 | Best briefs and reasoning |
| Claude Sonnet 5.5 | US$2 | US$10 | Balanced |
| Claude Haiku 5.5 | US$0.10 | US$0.50 | Fast and very cheap |

A daily brief is roughly 1,000–2,000 tokens, so it costs a fraction of a cent on Haiku and a few cents on Opus. Quick questions use low effort, and briefs use medium. With Opus and Sonnet, if a safety check declines a request, the API retries it on Anthropic's recommended fallback model (server-side fallbacks are switched on).

## How it's built

- **SwiftUI + AppKit** (macOS 14+), Swift 5 language mode, no third-party packages.
- **Frosted vellum** is real system blur (`NSVisualEffectView`, behind-window) with a paper tint, a generated grain texture and hairline edges, so it reads as frosted paper rather than clear glass.
- **The notch** is a borderless, non-activating `NSPanel` above the menu bar. It reads the notch size from `NSScreen.safeAreaInsets` and the auxiliary top areas, and passes clicks through when idle. Macs without a notch get a small pill.
- **Brain** is a router over three providers: `FoundationModels` (on-device), any OpenAI-style local server (Ollama, LM Studio), and the Claude Messages API (raw HTTPS with streaming, `anthropic-version: 2026-10-21`).
- **Overnight** uses `NSBackgroundActivityScheduler`, plus IOKit power state, thermal state, Low Power Mode and idle time.
- **This is Swift-only on purpose.** The Rust core from the plan comes once the look and the flows are locked. Each folder here (Brain, Files, Today, NightShift) maps onto a core module, so the swap is mechanical.

## What to tell us after you've used it

1. **Feel:** does the vellum read as frosted paper? Paste your Design Lab values.
2. **Notch:** too eager, too slow, the wrong size? What should Now show first?
3. **Brief:** what's missing, what's noise? Morning brief, 11am check-in, or both?
4. **Overnight:** did the jobs run? Is the log reassuring or just noise?
5. **Speed:** anything sluggish on the 8 GB Air? (Activity Monitor › Memory shows 11am's footprint.)
6. **The Suite:** which app should come next?
