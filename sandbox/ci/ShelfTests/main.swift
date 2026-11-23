// The drop's shelf: what kind of file each is, which agents' rings open for it, what they'd do, and the shelf list.
import Foundation

var failures = 0

func check(_ condition: Bool, _ label: String) {
    print(condition ? "PASS" : "FAIL", label)
    if !condition { failures += 1 }
}

// MARK: Kinds

check(ShelfKind.of(extension: "PDF") == .pdf, "kinds: PDF in capitals")
check(ShelfKind.of(extension: "heic") == .image && ShelfKind.of(extension: "jpeg") == .image, "kinds: photos")
check(ShelfKind.of(extension: "mov") == .video && ShelfKind.of(extension: "m4a") == .audio, "kinds: video and sound")
check(ShelfKind.of(extension: "docx") == .document && ShelfKind.of(extension: "md") == .document, "kinds: documents")
check(ShelfKind.of(extension: "xlsx") == .sheet && ShelfKind.of(extension: "csv") == .sheet, "kinds: spreadsheets")
check(ShelfKind.of(extension: "key") == .deck && ShelfKind.of(extension: "ics") == .calendar, "kinds: decks and invites")
check(ShelfKind.of(extension: "py") == .code && ShelfKind.of(extension: "zip") == .other, "kinds: code and the rest")
check(ShelfKind.of(URL(fileURLWithPath: "/tmp/Clients"), isFolder: true) == .folder, "kinds: folders")

// MARK: Who takes what

func action(_ agent: String, _ kinds: [ShelfKind]) -> ShelfAction? { ShelfRouting.action(agent: agent, kinds: kinds) }

check(action("mr", [.pdf, .image, .other]) == .email, "Marc emails any files")
check(action("mr", [.folder]) == nil, "Marc doesn't take a folder")
check(action("mc", [.pdf]) == .email, "an older code still routes to Marc")
check(action("ge", [.pdf]) == .receipt && action("ge", [.pdf, .image]) == .receipt, "George files receipts")
check(action("ge", [.sheet]) == .sheet && action("ge", [.sheet, .sheet]) == nil, "George opens one spreadsheet")
check(action("ge", [.video]) == nil, "George turns down a video")
check(action("rb", [.image]) == .photo && action("rb", [.image, .image]) == nil, "Robert edits one photo")
check(action("ce", [.video, .video]) == .video && action("ce", [.audio]) == .audio, "Cole takes video or sound")
check(action("ce", [.video, .audio]) == nil, "Cole doesn't mix video and sound in one go")
check(action("jo", [.folder]) == .terminal && action("jo", [.code]) == .terminal, "Johnny opens a terminal")
check(action("jo", [.pdf]) == nil, "Johnny turns down a PDF")
check(action("bn", [.pdf]) == .pdf && action("bn", [.folder]) == .files, "Bolton opens a PDF, shows a folder")
check(action("bn", [.pdf, .image]) == .note && action("bn", [.other]) == .note, "Bolton keeps the rest in Notes")
check(action("bn", [.folder, .pdf]) == nil, "Bolton doesn't mix a folder with files")
check(action("wi", [.document, .document]) == .write && action("wi", [.pdf]) == nil, "William opens documents only")
check(action("jm", [.pdf, .document]) == .source && action("jm", [.image]) == nil, "James keeps PDFs and pages as sources")
check(action("cr", [.document]) == .deck && action("cr", [.document, .document]) == nil, "Conner makes a deck from one document")
check(action("le", [.pdf, .image]) == .task, "Leo makes tasks")
check(action("le", Array(repeating: .pdf, count: 11)) == nil, "Leo stops at ten tasks at once")
check(action("11", [.pdf]) == .ask && action("11", [.pdf, .pdf]) == nil && action("11", [.folder]) == nil, "the 11 asks about one file")
check(action("hr", [.document]) == nil, "Harris takes nothing yet")
check(action("mr", []) == nil, "nothing dragged, no ring")

// MARK: Words

check(ShelfRouting.verb(.email, count: 1) == "email it" && ShelfRouting.verb(.email, count: 3) == "email them", "verbs: it and them")
check(ShelfRouting.verb(.receipt, count: 2) == "file the receipts", "verbs: receipts")
check(ShelfAction.email.opensApp && !ShelfAction.receipt.opensApp && !ShelfAction.task.opensApp, "receipts and tasks happen quietly")

// MARK: The shelf list

let list = ShelfList.adding(["/a", "/b"], to: ["/c", "/a"])
check(list == ["/a", "/b", "/c"], "shelf: new files first, no repeats")
check(ShelfList.adding(["/x", "/x"], to: []) == ["/x"], "shelf: the same file twice is one chip")
let full = ShelfList.adding(["/new"], to: (0..<30).map { "/\($0)" })
check(full.count == ShelfList.limit && full.first == "/new", "shelf: kept to its limit, newest first")
check(ShelfList.chipName("Receipt.pdf") == "Receipt.pdf", "chips: short names stay whole")
let long = ShelfList.chipName("Acme pilot agreement signed by both parties final v3.pdf")
check(long.count <= 26 && long.hasSuffix(".pdf") && long.contains("…"), "chips: long names lose their middle, keep the extension")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
