import CryptoKit
import Foundation

// Checks smart folders (saved searches) and locked notes.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Australia/Sydney")!
func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }
let now = day(2026, 11, 5, 10)

// MARK: Queries

let query = NoteQuery.parse("pilot #Acme has:todo in:Work edited:week")
check(query.words == ["pilot"] && query.tags == ["acme"] && query.hasOpenTodo && query.folder == "Work" && query.editedWithinDays == 7, "A query in all its parts")
check(NoteQuery.parse("").isEmpty && !NoteQuery.parse("x").isEmpty, "Empty and not")
check(NoteQuery.parse("edited:3d").editedWithinDays == 3 && NoteQuery.parse("edited:today").editedWithinDays == 0, "edited:3d and edited:today")
check(NoteQuery.parse("in:Board_papers").folder == "Board papers", "Folder names with spaces use an underscore")

let note = "# Acme pilot\n\nTom wants SSO before the pilot. #acme #board-deck\n\n- [ ] Send Tom the deck\n- [x] Book the room\n\nSee [[Board deck]]."
func matches(_ text: String, folder: String = "Work", pinned: Bool = false, modified: Date = day(2026, 11, 4)) -> Bool {
    query.matches(text: text, folder: folder, pinned: pinned, modified: modified, now: now, calendar: cal)
}
check(matches(note), "The note matches")
check(!matches(note, folder: "Personal"), "Wrong folder")
check(!matches(note, modified: day(2026, 10, 20)), "Edited too long ago")
check(!matches(note.replacingOccurrences(of: "- [ ] Send Tom the deck", with: "- [x] Send Tom the deck")), "No open checkbox left")
check(!matches(note.replacingOccurrences(of: "#acme", with: "acme")), "Tag missing")
check(NoteQuery.parse("is:pinned").matches(text: "x", folder: "", pinned: true, modified: now, now: now, calendar: cal)
      && !NoteQuery.parse("is:pinned").matches(text: "x", folder: "", pinned: false, modified: now, now: now, calendar: cal), "Pinned")
check(NoteQuery.parse("has:link").matches(text: "see https://x.com", folder: "", pinned: false, modified: now, now: now, calendar: cal), "Links")
check(NoteQuery.parse("edited:today").matches(text: "x", folder: "", pinned: false, modified: day(2026, 11, 5, 1), now: now, calendar: cal)
      && !NoteQuery.parse("edited:today").matches(text: "x", folder: "", pinned: false, modified: day(2026, 11, 4, 23), now: now, calendar: cal), "Edited today means since midnight")
check(NoteQuery.tags(in: "# Heading\n#acme and #1 and a&#39; and http://x.com/#frag #Board-deck") == ["acme", "board-deck"], "Tags, not headings, numbers, entities or anchors")

// MARK: Locked notes

let key = NoteLock.newKey()
let secret = "# Bank details\n\nBSB 062-000, account 1234 5678."
let sealed = try! NoteLock.seal(secret, title: "Bank details", key: key)
check(sealed.hasPrefix("# Bank details\n") && NoteLock.isLocked(sealed) && !sealed.contains("1234"), "Sealed: title readable, the rest not")
check((try? NoteLock.open(sealed, key: key)) == secret, "Opens with the key")
check((try? NoteLock.open(sealed, key: NoteLock.newKey())) == nil, "Not with another key")
var tampered = sealed
tampered.insert("A", at: tampered.index(tampered.endIndex, offsetBy: -6))
check((try? NoteLock.open(tampered, key: key)) == nil, "A changed file won't open")
check((try? NoteLock.open("plain", key: key)) == nil && !NoteLock.isLocked(secret), "Plain notes aren't locked")
let text = NoteLock.keyText(key)
check(NoteLock.key(from: text).map { NoteLock.keyText($0) } == text && NoteLock.key(from: "short") == nil, "The key round-trips through the Keychain text")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
