# 05: iPhone and Mac ↔ iPhone continuity

## The role of the iPhone

The Mac is where the work happens. **The iPhone is where you stay in control**: approve, capture, glance, talk, and get told what matters. It isn't a shrunken copy of the Mac suite.

**Tagline idea:** *the notch on your Mac, the island on your phone.* The same live state appears in both places.

---

## iPhone app structure (one app, agent modules unlocked by purchase)

| Tab | What it does | Agents |
|---|---|---|
| **Today** | Leo's brief and check-in, timeline (calendar + tasks + live jobs), meeting prep cards | Leo (+ everyone's events) |
| **Approvals** | Swipe-to-approve queue: drafts, sends, reschedules, filings. Edit by voice ("make it shorter") | All |
| **Ask** | Voice-first Ask bar. Hold to talk, see routing, get answers with sources | Leo routes |
| **Capture** | Scan a document (VisionKit), take a photo, record a voice note, paste a link; it goes to the right agent | Bolton, George, James, Leo |
| **Agents** | Mobile surfaces of purchased agents (below) | Each add-on |

### Mobile surfaces per agent (only what makes sense on a phone)
| Agent | iPhone surface |
|---|---|
| Leo | Today, check-ins, tasks, meeting recorder (in-person meetings), Live Activities |
| Bolton | Search everything, read notes, capture, recent files (from Mac via sync of metadata and previews) |
| Marc | Triage swipe (Needs you / Later / Done), approve drafts, voice reply drafting, people cards. **Email only; iMessage stays Mac-side** |
| William | Quick drafts, approve rewrites, **keyboard extension**: "rewrite in my voice" in any app (v2) |
| James | Read reports, start research by voice, share sheet "ask James about this link" |
| Johnny | Approve runs, trigger automations, view run history |
| George | Cash, runway and burn glance, snap receipts, approve categorisations |
| Conner | Pipeline glance, log a call by voice, review decks |
| Robert | Capture references (camera), approve variants, quick crops |
| Cole | Capture footage (auto-syncs to the Mac project), review exports, teleprompter |
| Harris | **Primary learning surface**: daily practice, flashcards, speaking drills, listening on the commute |

---

## Dynamic Island, Live Activities, widgets, Siri

| Surface | Use |
|---|---|
| **Live Activities + Dynamic Island** | Running jobs (James 18/30 sources), meeting countdown and recording timer, approvals waiting, Cole export progress. Mirrors the Mac notch. Update via **ActivityKit push** (needs APNs; see "Push without a server") |
| **Widgets** (Home, Lock Screen, StandBy) | Today summary, next meeting, approvals count, cash/runway, Harris "8 cards due" |
| **Control Center controls** (iOS 18+) | Start capture, start meeting recording, pause the team |
| **Action button** | Default App Intent: "Ask Leo" (hold to talk) |
| **Siri / App Intents** | "Ask 11am…", "Add to Bolton", "What's next?", "Approve Marc's drafts" (with confirmation). Intent and entity schemas (iOS/macOS 27) put Bolton content in the Spotlight semantic index |
| **Share extension** | From any app to an agent: link → James, PDF → Bolton, photo → Robert/George |
| **Notifications** | Actionable: Approve / Edit / Later. Grouped by agent. Check-in delivered at 11am |
| **Apple Watch** (later) | Approvals on the wrist, check-in summary, voice capture |
| **macOS 26 menu bar Live Activities** | macOS Tahoe can show iPhone Live Activities in the Mac menu bar (check behaviour); the Mac notch makes this redundant, so suppress duplicates |

---

## Sync architecture

### Choice: **CloudKit private database** (primary) + **local network fast path** (optional)

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **CloudKit (private DB)** | No server to run, free at this scale, tied to Apple ID, push via subscriptions, per-field encryption (`encryptedValues`), works off-network | Apple-only, eventually consistent, record size limits, rate limits | **Use for v1** |
| Local network (Network framework, Bonjour) | Fast, private, large transfers (files, model calls) | Only on the same network | **Fast path + "Mac as brain"** |
| Own sync server | Full control, cross-platform | You run infrastructure, security liability | Only if you go to Windows/Android |
| P2P (iroh, MIT/Apache) | Cross-network P2P, no server, Rust | More moving parts | Consider for "Mac as brain" off-network (v2) |
| Multipeer Connectivity | — | Apple is steering developers to Network framework (TN3213, Jul 2026); reportedly deprecated in Xcode 27 betas | **Don't use** |

### What syncs
- **Synced (CloudKit):** tasks, calendar overlays (11am metadata only; events themselves sync via the user's calendar accounts), approvals queue, briefs, notes (Markdown), memories (respecting data classes), people/entities, deals, James reports, Harris cards and reviews, George summaries (not raw transactions unless enabled), spec changes, settings.
- **Not synced by default:** raw mail bodies (the iPhone app fetches mail directly from the provider, just like any mail client), iMessage content, large files (metadata and previews only; full file on demand over LAN or iCloud Drive), model weights.

### Sync mechanics
1. The Rust core emits **change sets** (record id, fields, HLC timestamp, device id) for synced tables.
2. The Swift CloudKit adapter batches change sets into `CKRecord`s (sensitive fields in `encryptedValues`) and pushes them via `CKSyncEngine` (iOS 17+/macOS 14+, which handles scheduling, retries and push subscriptions).
3. Incoming changes are applied by the core. **Conflicts:** last-writer-wins per field for structured data (HLC ordered); **CRDT (Automerge or Yrs)** for notes and William documents so concurrent edits merge.
4. The **iPhone runs the same Rust core** (compiled for iOS) with the same schema, so behaviour is identical.

### Push without a server
- `CKSyncEngine`/`CKDatabaseSubscription` deliver silent pushes when records change. The iPhone wakes, syncs and updates widgets.
- **Live Activity updates** need APNs pushes with an ActivityKit token. That requires a tiny push relay (a serverless function holding your APNs key). The Mac sends "job progress" to the relay and the relay pushes to the phone. Alternatively, update the Live Activity locally whenever the app gets background time (less real-time). **Recommendation:** start local-only. Add the relay when you build the business backend (you'll need one for licensing anyway; see [08](./08-shipping-and-business.md)).

---

## "Mac as brain" (the iPhone uses your Mac's models)

The iPhone's own models are small: Apple's on-device model on Apple Intelligence iPhones, plus maybe a 2–4B MLX model on 8 GB+ iPhones. For anything bigger:

1. **Same network:** the Mac advertises `_11am._tcp` via Bonjour (`NWListener`), and the iPhone discovers it (`NWBrowser`). Connection is TLS with a **pairing key** established once by scanning a QR code on the Mac (no passwords). The iPhone sends a job, and the Mac runs it with its local models and streams back.
2. **Away from home:** options, in order of simplicity: (a) queue the job in CloudKit so the Mac picks it up and the result syncs back (works if the Mac is awake; slow but private); (b) Tailscale (the user installs it, and 11am just uses the Mac's tailnet address); (c) iroh P2P built in (v2).
3. **Mac asleep:** macOS "Wake for network access" plus the Bonjour Sleep Proxy can wake a Mac on the same network for some traffic (check reliability). Otherwise jobs queue until wake. Leo says so honestly: "Your Mac is asleep. Run on iPhone (smaller model), use cloud, or wait?"
4. **Home server mode:** a Mac mini or Studio at home runs 11am in "server mode" (no UI needed; login item + core + ModelHost) and acts as the household brain for your MacBook and iPhone.

---

## Continuity features to use

| Feature | 11am use |
|---|---|
| **Handoff** (`NSUserActivity`) | Start reading a James report on iPhone and continue on the Mac. Draft in William on the Mac and continue on iPhone |
| **Universal Clipboard** | Works automatically. Bolton's shelf can capture the clipboard history from both devices (Mac-side) |
| **Continuity Camera** | iPhone as a scanner or camera for Bolton, George receipts and Robert references directly into Mac apps; as a webcam for Cole |
| **iPhone Mirroring** | System feature; nothing to build, but don't conflict with it |
| **AirDrop** | The notch shelf supports AirDrop share (as boring.notch does) |
| **Universal Links** | `11am.app/...` links open the right agent on either device |
| **Shared App Group + Keychain access group** | Share credentials and settings between the iOS app and its extensions (widgets, share, keyboard) |

---

## iPhone constraints to design around

- **No iMessage/SMS access** for third-party apps. Marc on iPhone is email + approvals only.
- **No reading other apps' content** (no Accessibility API equivalent). Use the Share sheet, App Intents and the keyboard extension.
- **Background limits:** use `BGProcessingTask` (charging + idle) for indexing and model work, and `BGAppRefreshTask` for light sync. Long jobs go to the Mac.
- **Keyboard extensions** have no network unless the user grants "Full Access". Keep the William keyboard on-device (Apple FM) where possible.
- **Memory:** iOS kills apps that use too much memory. Keep on-device models at ≤2–3 GB, loaded only in the foreground or a processing task.
- **App Store review:** clear privacy labels, explain AI features, no hidden data collection. In-app purchase for digital goods (agents). See [08](./08-shipping-and-business.md).
