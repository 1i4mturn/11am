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
| **Today** (Leo) | Today from every calendar (or a sample day), the brief, an optional 11am check-in notification | "Write my brief" |
| **Calendar** (Leo) | Every calendar on this Mac (iCloud, Google, Exchange) and your Outlook or Microsoft 365 calendar in one place: day, 3 days, week, month and agenda. Type events in plain words. Drag on empty time to book it, drag a block to move it (across days too), drag its bottom edge to change the length. Each event shows its join button, who's coming, your yes/maybe/no, clashes, and a **Prep me** note from Leo with your recent mail with them. **Find a time** copies your free slots into an email or holds two hours for focus. Australian public holidays and reminders that are due sit above the hours | Type "Lunch with Tom Fri 1pm at Lune" in the box at the top. Drag the kickoff onto Wednesday. Open **Find a time**, then **Copy for an email**. **Connect** for your real calendars; for 365, **Microsoft 365** signs in through Mail |
| **Mail** (Marc) | Every account in one inbox, sorted into **Needs you · Worth reading · FYI · Noise** by what you actually do: what you open and how soon, how long you read, what you answer, flag, snooze, archive unread or never open. On day one Marc learns from the read, replied and flagged marks your provider already keeps, and who you write to. Each email says why it's there (**Why?** shows the evidence). Archive, delete, flag, snooze, unsubscribe, block, and reply or write from the right account with a few seconds to undo. **j k e u s r a f** and **⌫** work like a mail app | Start with the sample: move an email to another lane and watch Marc learn. Then **Accounts › Add an account…**: an app password for iCloud, Gmail, Fastmail, Yahoo or any IMAP, or **Sign in with Microsoft** for Outlook and Microsoft 365. Open **How Marc sorts** (the brain button) |
| **Write** (William) | Formatted documents that stay plain Markdown files on your Mac: headings, bold and italic, highlight, lists and checklists, tables, quotes and callouts, code, links and pictures, shown as a page while you type. Templates (letter, proposal, one-pager, meeting notes, report, résumé, press release), an outline, find and replace, focus and typewriter modes, and a version every 15 minutes. **Import** Word, Google Docs (as .docx), RTF, HTML and OpenDocument; **Export** a PDF with your page setup, a Word file with real headings and lists, a web page, Markdown or plain text. William rewrites a selection as a suggestion you accept or reject | Open **Welcome to Write** and try the shortcuts. Select a paragraph of the investor update and choose **In my voice**. **Export › Word** and open it in Word or Pages |
| **Notes** (Bolton) | Notes in folders, with pinning, #tags, [[links]] between notes and what links back, pictures and files kept with the note, and today's note with your calendar in it. **⌥⇧N** starts a note from anywhere. Import everything from Apple Notes (folders kept), or Markdown and Notion exports; export it all as Markdown. **Ask** answers from your notes and names the ones it used | Open **Acme pilot**, click the [[Board deck]] link, tick a box. Press **Today**. Ask "what does Tom need before go-live?" |
| **Files** (Bolton) | Local index of folders you choose (PDF, Word, RTF, Markdown, text), with name, content and meaning search | Add a folder, search, then "Ask Bolton about these results" |
| **PDF** (Bolton) | Read with thumbnails, contents and search; highlight, underline, strike out, sticky notes, text boxes, drawing and your signature (drawn or typed, kept for next time); fill in forms. **Pages**: drag to reorder, rotate, duplicate, delete, insert from other files, save some pages, split. Combine PDFs and pictures. **Compress**, **protect with a password** (and turn off printing or copying), **flatten**, remove hidden details, make scanned pages searchable, and **redact for real**: what's under the boxes is removed from the file, then checked. Ask Bolton for a summary, the key points, or the dates, money and obligations, with page numbers | **Try a sample agreement**, highlight a line, sign at the bottom. Mark the bank account with the redaction tool and **Apply**. Switch to **Pages** and drag page 2 first |
| **Research** (James) | A WebKit browser with James beside it: summarise or ask the page, add pages as sources, then a report that cites them, sent to Write | Open a start-page link, **Add to sources**, then ask a question under **Report** |
| **Money** (George) | Proper books, with Australian GST. **Bank**: import statements (CSV, OFX or QIF from any bank; duplicates skipped) and reconcile: George suggests the match (a payment for an invoice, a payee coded like last time, a transfer between your accounts) and you press **OK**, or **Accept the sure ones** for all of them. **Invoices** and **Bills**: write them with GST per line, approve, record payments, void, save a tax invoice PDF or email it with the PDF attached. **Contacts** with what each owes. **Reports**: profit and loss, balance sheet, cash, trial balance, owed to you and you owe (by how late), for any month, quarter or financial year, and the **accountant's pack** as one Excel file. **GST**: the quarter's BAS figures (G1, G3, G10, G11, 1A, 1B) on cash or accrual, with the due date. The overview still has cash, burn and runway, and George answers from the books | Open **Bank** and press **OK** on the Kestrel payment. Open **Invoices**, pick INV-0004 and **Record payment…**. Look at **GST**, then **Reports › Accountant's pack…** |
| **Sheets** (George) | Spreadsheets with live formulas: about 110 Excel functions (SUMIFS, XLOOKUP, INDEX/MATCH, TEXT, dates, PMT, NPV, IRR…), typed money, percentages and dates understood, a fill handle that continues series and copies formulas, frozen header rows, sort, insert and delete rows and columns (formulas everywhere follow), number formats, bold, colours, several sheets per workbook, copy and paste with other apps, undo. **Charts** (column, bar, line, area, pie, scatter) and **Summarise** (a live pivot of a table, with a chart). **Open and save Excel files** and CSV, export PDF. George writes a formula from a sentence, explains one, answers questions from the sheet or makes a new sheet | In **Budget**, drag the fill handle under F7 down a row. Select B2:E7 to see the sum at the bottom. **Summarise** the **Sales** sheet by Client. **Ask George** "total of Amount where Region is North" |
| **Business** (Conner) | The pipeline as a board: drag deals between stages, weighted value, "going quiet" nudges, follow-ups drafted in your voice | Drag a deal to **Proposal**, open it, **Draft follow-up** |
| **Design** (Robert) | A canvas for every size: social posts, stories, LinkedIn and YouTube, email headers, link previews, slides, A4, posters, flyers, business cards and logos. Templates (announcement, quote, big number, event, hiring, launch, photo and caption) laid out from your brand kit, or **Make me a graphic…** from a sentence. Text, shapes, lines and arrows, pictures (drop them in) and QR codes; move with snapping guides, resize from any handle, rotate, group, align and distribute, lock, layer order, copy and paste. The inspector sets fonts, weight, spacing, colours and gradients, outlines, corners and shadows, picture fit, and removes a picture's background on this Mac. **Resize into** another size as a new design; export PNG, JPEG, PDF or SVG. Image tools and the brand kit are still here | Open **Founder breakfast**, change the headline, drag it until the centre guide shows. **Export › Resize into a new design › Instagram post**. **Make me a graphic…** "we hit 1,000 customers" |
| **Decks** (Conner) | Slides on the same canvas: thirteen layouts (title, section, statement, points, two columns, picture, big number, quote, chart, table, team, timeline, closing), five themes or your brand kit, a slide sorter, speaker notes. Change the words and the slide lays itself out again; move things by hand and it remembers. New decks from an outline, a document in Write, or a draft from Conner. **Present** full screen with the arrow keys, with a presenter view (notes, next slide, timer) on a second display. Export PDF, PowerPoint or pictures | Open **Seed round**, click the chart slide and change a bar. Switch the theme to **Ember**. **Present** (⌥⌘↩), then esc |
| **Photo** (Robert) | Non-destructive photo editing: looks, light, colour, three colour wheels, colour by colour, curve, sharpen, noise, fade, vignette, grain and .cube LUTs. Crop to a shape, straighten (or **Auto** level the horizon), rotate, flip. **Clean up** paints out dust, spots and small distractions. **Cut out** removes the background. RAW files open too. Undo, before/after, export JPEG, HEIC, PNG or TIFF at full resolution | Press **Auto**, then try a look. **Crop** › 4:5 and drag the corners. **Clean up** › paint over the sun |
| **Video** (Cole) | A real timeline: add clips, drag their edges to trim, **⌘B** to split at the playhead, reorder, duplicate, speed (¼× to 4×). Each clip has its own grade (the same colour panel as Photo), volume and mute. **Clean up the voice** runs Apple's Voice Isolation, a rumble filter and levelling on this Mac. Reframe for 9:16, 1:1 or 4:5. Dip to black or white between clips, fade in and out. Transcribe a clip and strike lines to cut them. Export H.264, HEVC, 720p, ProRes or sound only, plus captions | **Try two sample clips**, drag the second clip's left edge, grade it with **Teal & orange**, switch the shape to **9:16**, play |
| **Learn** (Harris) | Flashcards with spaced repetition and a flip-card review, cards made from your notes, learning paths | Review the sample deck. Paste notes and **Make cards** |
| **Build** (Johnny) | Tune 11am by describing the change (preview, apply, undo). **Make a colour look** from a description, saved for Photo and Video. A terminal where Johnny suggests commands but only you run them | Try "Warmer, and a bit more see-through", then **Revert**. Make "Warm film with soft blacks" and find it under Looks in Photo |
| **Overnight** | Heavy jobs wait for the charger, a cool Mac and idle time or your overnight window. Writes tomorrow's brief ahead of time | "Run Now" to see it work immediately. **⇧⌘R** does the same |
| **The Suite** | The apps that replace the subscription pile, and which ones are in this sandbox | Look, react, tell us what's missing or unnecessary |
| **Design Lab** | Live sliders for paper tone, frost, **clarity** (how much of the desktop shows through), grain, depth, ink, **motion**, radius, display face and backdrop. Starts from your round-one picks | Tune it until it feels right, then **Copy Values** and paste them into your feedback |

Shortcuts: **⌘1–⌘9** switch between the first nine apps · **⌘Z / ⇧⌘Z** undo and redo in Photo, Video, Sheets, Design and Decks · **⌘B** splits, **⌘↩** plays and pauses, **⌘⌫** removes a clip in Video · **⇧⌘N** writes a new email (a new event in Calendar, a new note in Notes) · **⌥⇧N** jots a note from anywhere · in Write and Notes, **⌘B ⌘I ⌘U ⌘K ⌘E**, **⌥⌘1–3** headings, **⇧⌘7 ⇧⌘8 ⇧⌘L** lists, **⌘F** find and replace · in Calendar, **T** today, **← →** move, **D 3 W M A** change the view, **↩** edits, **⌫** deletes · in Sheets, arrows move (**⌘** jumps to the edge of the data, **⇧** selects), type to replace, **↩** or **F2** to edit, **⌘D** fills down, **⌘B ⌘I** bold and italic · on a canvas, arrows nudge (**⇧** for 10), **⌘D** duplicates, **⌘G / ⇧⌘G** group and ungroup, **⌘] ⌘[** layer order, **⌘L** locks, **↩** edits text, hold **⌘** while dragging to skip snapping · **⌥⌘↩** presents a deck · **⌘\\** shows or hides the agent pane (it also steps aside on narrow windows) · **⌥Space** asks from anywhere · **⇧⌘R** runs tonight's work now · **⌘,** opens settings.

Screenshots from the CI Mac (a small virtual display without a notch, so the notch shows as a pill, with a busy test desktop behind the app) are on the `ci/sandbox-shots` branch. Push a commit with `[shots]` in its message to refresh them.

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

## Photo and Video: what's under the hood

- **One colour engine for both.** Core Image does the work on the GPU. Tone, contrast, the three colour wheels (lift, gamma, gain), saturation and colour-by-colour are baked into a single 33×33×33 colour cube, so a grade costs one lookup per pixel and plays in real time on video. Exposure, white balance, highlights and shadows, vibrance, sharpening, noise reduction, vignette and grain are Core Image filters around it.
- **Looks are plain files.** Every look you save (or Johnny makes) is a small JSON file in `~/Library/Application Support/11am-sandbox/Looks`. Drop `.cube` LUTs from Resolve, Premiere or a LUT pack into **Import .cube…** and they work in both apps.
- **Clean-ups stay on this Mac.** The spot healer fills each spot from the nearby patch whose surroundings match best, colour-matched and feathered. Background removal is Vision's subject mask. Auto straighten is Vision's horizon detector.
- **Video never re-encodes until you export.** Trims, splits, speed and transcript cuts are an `AVMutableComposition`. Colour, reframing and dips are a per-frame Core Image pass. Volume and fades are an audio mix. Voice clean-up uses Apple's `AUSoundIsolation` unit rendered offline, and falls back to a rumble filter and levelling if Voice Isolation isn't available.
- **Adding more later.** Ask Johnny for a look in plain English. For a new tool (a mask brush, keyframes, titles), ask Claude Code in this repo: the engine is in `ElevenAm/Media` (shared) and `Features/Photo` and `Features/Video` (the apps), and each piece is small enough to extend.

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
