import Foundation

// Checks Bolton's pages: the tree and breadcrumbs, live blocks, versions kept and let go, checkboxes,
// mentions, and a Notion export's nesting.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Australia/Sydney")!

// MARK: The tree

let company = UUID(), projects = UUID(), website = UUID(), launch = UUID(), handbook = UUID(), orphan = UUID()
let titles: [UUID: String] = [company: "Company", projects: "Projects", website: "Website", launch: "Launch plan", handbook: "Handbook", orphan: "Orphan"]
func title(_ id: UUID) -> String { titles[id] ?? "" }
var metas: [UUID: PageMeta] = [
    projects: PageMeta(parent: company, order: 2),
    handbook: PageMeta(parent: company, order: 1),
    website: PageMeta(parent: projects),
    launch: PageMeta(parent: website),
    orphan: PageMeta(parent: UUID()),
]
let ids = [company, projects, website, launch, handbook, orphan]

check(PageTree.children(of: nil, ids: ids, metas: metas, title: title) == [company, orphan], "Top level: pages without a parent, and pages whose parent is gone")
check(PageTree.children(of: company, ids: ids, metas: metas, title: title) == [handbook, projects], "Children in your order")
check(PageTree.path(to: launch, ids: ids, metas: metas) == [company, projects, website], "Breadcrumbs from the top down")
check(PageTree.path(to: company, ids: ids, metas: metas).isEmpty, "A top-level page has no breadcrumbs")
check(Set(PageTree.descendants(of: projects, ids: ids, metas: metas)) == [website, launch], "Everything under a page")
check(!PageTree.canMove(projects, under: launch, ids: ids, metas: metas), "A page can't go inside its own sub-page")
check(!PageTree.canMove(projects, under: projects, ids: ids, metas: metas), "…or inside itself")
check(PageTree.canMove(launch, under: handbook, ids: ids, metas: metas) && PageTree.canMove(launch, under: nil, ids: ids, metas: metas), "Moving elsewhere is fine")
let collapsed = PageTree.rows(ids: ids, metas: metas, expanded: [], title: title)
check(collapsed.map(\.id) == [company, orphan] && collapsed[0].hasChildren && !collapsed[1].hasChildren, "Collapsed tree")
let open = PageTree.rows(ids: ids, metas: metas, expanded: [company, projects, website], title: title)
check(open.map(\.id) == [company, handbook, projects, website, launch, orphan] && open.map(\.depth) == [0, 1, 1, 2, 3, 0], "Expanded tree with depths")
var loop = metas
loop[company] = PageMeta(parent: launch)
check(PageTree.path(to: launch, ids: ids, metas: loop).count <= ids.count, "A loop in the tree doesn't hang")
check(PageTree.nextOrder(under: company, ids: ids, metas: metas) == 3, "New pages go after their siblings")
let oldMeta = try? JSONDecoder().decode(PageMeta.self, from: Data(#"{"favourite": true}"#.utf8))
check(oldMeta?.favourite == true && oldMeta?.parent == nil, "Page details saved by older versions still load")

// MARK: Live blocks

check(PageBlocks.parse("{{tasks: Website relaunch}}") == .tasks("Website relaunch"), "A tasks block")
check(PageBlocks.parse("  {{ Sheet : Budget!Q3 }}  ") == .sheet("Budget!Q3"), "Spaces and capitals are fine")
check(PageBlocks.parse("{{page: Team rituals}}") == .page("Team rituals") && PageBlocks.parse("{{calendar: today}}") == .events("today"), "Page and calendar blocks")
check(PageBlocks.parse("Some {{tasks: x}} in a sentence") == nil && PageBlocks.parse("{{tasks: }}") == nil && PageBlocks.parse("{{nope: x}}") == nil, "Only whole lines with a known kind")
let body = "# Plan\n\n{{tasks: today}}\n\n```\n{{tasks: not this}}\n```\n{{page: Rituals}}"
let blocks = PageBlocks.find(in: body)
check(blocks.map { $0.line } == [2, 7] && blocks.map { $0.block } == [.tasks("today"), .page("Rituals")], "Blocks found with their lines, not inside code")
check(PageBlock.sheet("Budget").markdown == "{{sheet: Budget}}", "Blocks write back as one line")
let pages = ["A": "{{page: B}}", "B": "{{page: C}}\n{{page: A}}", "C": "plain"]
check(PageBlocks.embeddedPages(from: "A", text: { pages[$0] }) == ["B", "C"], "Pages inside pages, without going round in circles")

// MARK: History

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
check(PageHistory.shouldKeep(last: nil, lastText: nil, now: t0, text: "a"), "The first version is kept")
check(!PageHistory.shouldKeep(last: t0, lastText: "a", now: t0.addingTimeInterval(60), text: "ab"), "Not every keystroke")
check(PageHistory.shouldKeep(last: t0, lastText: "a", now: t0.addingTimeInterval(700), text: "ab"), "After ten minutes of writing")
check(!PageHistory.shouldKeep(last: t0, lastText: "ab", now: t0.addingTimeInterval(7_000), text: "ab"), "Not when nothing changed")
let name = PageHistory.fileName(for: t0)
check(!name.contains(":") && PageHistory.date(fromFileName: name) == t0, "Version file names round-trip: \(name)")
// 30 versions a few hours apart over five days, and 10 old ones months ago.
var versions = (0..<30).map { t0.addingTimeInterval(Double(-$0) * 4 * 3_600) }
versions += (0..<10).map { t0.addingTimeInterval(Double(-90 - $0) * 86_400) }
let dropped = Set(PageHistory.toDelete(versions, recent: 20, days: 60, now: t0, calendar: cal))
let kept = versions.filter { !dropped.contains($0) }
check(versions.sorted(by: >).prefix(20).allSatisfy { !dropped.contains($0) }, "The newest 20 are kept")
check(kept.count < versions.count && kept.count >= 21, "Older ones thin to one a day")
check(versions.filter { $0 < t0.addingTimeInterval(-61 * 86_400) }.allSatisfy { dropped.contains($0) }, "Versions older than 60 days go")
check(PageHistory.change(from: "a\nb\nc", to: "a\nc\nd\ne") == "+2 lines, −1 line", "What changed, in a line")
check(PageHistory.change(from: "same", to: "same") == "No changes", "No changes")

// MARK: Checkboxes

let list = "# Launch\n- [ ] Call Tom tomorrow 3pm\n- [x] Book the venue\n  * [ ] Order banners #design\n```\n- [ ] not a task\n```\n- [ ] "
let items = PageCheckboxes.items(in: list)
check(items.map(\.text) == ["Call Tom tomorrow 3pm", "Book the venue", "Order banners #design"], "Checkboxes found, not in code, not empty")
check(PageCheckboxes.open(in: list).map(\.line) == [1, 3], "Open ones with their lines")
let ticked = PageCheckboxes.tick(line: 1, in: list, note: "→ Tasks")
check(ticked.components(separatedBy: "\n")[1] == "- [x] Call Tom tomorrow 3pm → Tasks", "Ticked, with where it went")
check(PageCheckboxes.tick(line: 3, in: list).components(separatedBy: "\n")[3] == "  * [x] Order banners #design", "Indented ones keep their indent")
check(PageCheckboxes.tick(line: 99, in: list) == list, "A line that isn't there changes nothing")

// MARK: Mentions

check(Mentions.agents(in: "@Leo can you and @george, check this? @leo again") == ["le", "ge"], "Agents mentioned, once each")
check(Mentions.agents(in: "email me@example.com about @nobody").isEmpty, "Addresses and strangers aren't mentions")
check(Mentions.completion(for: "@Wi") == "William" && Mentions.completion(for: "@") == nil, "Completing a name")
let oldComment = try? JSONDecoder().decode(PageComment.self, from: Data(#"{"text": "hi"}"#.utf8))
check(oldComment?.author == "you" && oldComment?.text == "hi", "Comments saved by older versions still load")

// MARK: Notion exports

check(NotionExport.cleanName("Website relaunch 1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d.md") == "Website relaunch", "Notion's page IDs come off the names")
check(NotionExport.cleanName("Q3 plan.md") == "Q3 plan", "Names without IDs stay as they are")
let exportPaths = NotionExport.withoutCommonRoot([
    "Export-abc/Company 11111111111111111111111111111111.md",
    "Export-abc/Company 11111111111111111111111111111111/Projects 22222222222222222222222222222222.md",
    "Export-abc/Company 11111111111111111111111111111111/Projects 22222222222222222222222222222222/Website 33333333333333333333333333333333.md",
    "Export-abc/Company 11111111111111111111111111111111/Tasks 44444444444444444444444444444444.csv",
    "Export-abc/Company 11111111111111111111111111111111/Tasks 44444444444444444444444444444444/Fix login 55555555555555555555555555555555.md",
    "Export-abc/Archive/Old notes 66666666666666666666666666666666.md",
    "Export-abc/Company 11111111111111111111111111111111/Tasks 44444444444444444444444444444444_all.csv",
    "Export-abc/Company 11111111111111111111111111111111/logo.png",
])
check(exportPaths.allSatisfy { !$0.hasPrefix("Export-abc/") }, "The export's own folder is the top")
let entries = NotionExport.entries(paths: exportPaths)
func entry(_ title: String) -> NotionExport.Entry? { entries.first { $0.title == title } }
check(entries.count == 7, "Pages, a database, its row page and a folder: \(entries.map(\.title))")
check(entry("Company")?.parentPath == nil && entry("Projects")?.parentPath == entry("Company")?.path, "Sub-pages sit under their page")
check(entry("Website")?.parentPath == entry("Projects")?.path, "Nesting goes all the way down")
check(entry("Tasks")?.isDatabase == true && entry("Fix login")?.parentPath == entry("Tasks")?.path, "A database, with its row pages under it")
check(entry("Archive")?.isFolderOnly == true && entry("Old notes")?.parentPath == "Archive", "A folder with no page becomes one")
let positions = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.path, $0) })
check(entries.allSatisfy { e in e.parentPath.map { (positions[$0] ?? 99) < (positions[e.path] ?? 0) } ?? true }, "Parents come before children")
check(NotionExport.wikiLinks("See [Website](Projects%2022/Website%2033.md) and [the web](https://x.com)") == "See [[Website]] and [the web](https://x.com)", "Notion links become [[links]]")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
