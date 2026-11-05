import AppKit
import Foundation

/// A kept version of a page.
struct PageVersion: Identifiable, Equatable {
    var date: Date
    var url: URL

    var id: URL { url }
}

/// Bolton's pages: notes that nest like a wiki, with versions, comments the agents answer, checkboxes that
/// become tasks, and Notion exports brought in with their nesting.
extension NotesModel {
    private var pagesURL: URL { root.appendingPathComponent(".pages.json") }
    private var commentsURL: URL { root.appendingPathComponent(".comments.json") }
    private var historyRoot: URL { root.appendingPathComponent(".history", isDirectory: true) }

    // MARK: Loading and saving

    func loadPages() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: pagesURL), let saved = try? decoder.decode([String: PageMeta].self, from: data) {
            pages = Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
        }
        if let data = try? Data(contentsOf: commentsURL), let saved = try? decoder.decode([String: [PageComment]].self, from: data) {
            comments = Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
        }
        // Pages with sub-pages start open, so the tree shows what's there.
        let ids = notes.map(\.id)
        expanded = Set(ids.filter { id in pages.values.contains { $0.parent == id } })
    }

    func savePages() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let keyed = Dictionary(uniqueKeysWithValues: pages.map { ($0.key.uuidString, $0.value) })
        if let data = try? encoder.encode(keyed) { try? data.write(to: pagesURL, options: .atomic) }
    }

    func saveComments() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let keyed = Dictionary(uniqueKeysWithValues: comments.map { ($0.key.uuidString, $0.value) })
        if let data = try? encoder.encode(keyed) { try? data.write(to: commentsURL, options: .atomic) }
    }

    // MARK: The tree

    private var noteIDs: [UUID] { notes.map(\.id) }

    private func title(of id: UUID) -> String {
        notes.first { $0.id == id }?.title ?? ""
    }

    /// Pages that nest (they have a parent or sub-pages), as rows for the sidebar.
    var pageRows: [PageTree.Row] {
        let ids = noteIDs
        let existing = Set(ids)
        let parents = Set(pages.values.compactMap(\.parent)).intersection(existing)
        let nested = ids.filter { parents.contains($0) || PageTree.parent(of: $0, metas: pages, existing: existing) != nil }
        return PageTree.rows(ids: nested, metas: pages, expanded: expanded, title: title(of:))
    }

    var favourites: [Note] {
        notes.filter { pages[$0.id]?.favourite == true }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func breadcrumbs(for id: UUID) -> [Note] {
        PageTree.path(to: id, ids: noteIDs, metas: pages).compactMap { page in notes.first { $0.id == page } }
    }

    func subpages(of id: UUID) -> [Note] {
        PageTree.children(of: id, ids: noteIDs, metas: pages, title: title(of:)).compactMap { page in notes.first { $0.id == page } }
    }

    func icon(of id: UUID) -> String? { pages[id]?.icon }

    /// A new page inside this one, in the same folder.
    @discardableResult
    func newSubpage(of parent: UUID) -> Note? {
        guard let parentNote = notes.first(where: { $0.id == parent }) else { return nil }
        let order = PageTree.nextOrder(under: parent, ids: noteIDs, metas: pages)
        let note = newNote(text: "# Untitled\n\n", folder: parentNote.folder)
        pages[note.id] = PageMeta(parent: parent, order: order)
        expanded.insert(parent)
        savePages()
        return note
    }

    /// Moves a page inside another (or to the top with nil). Refuses to put a page inside itself.
    @discardableResult
    func setParent(_ id: UUID, to parent: UUID?) -> Bool {
        guard PageTree.canMove(id, under: parent, ids: noteIDs, metas: pages) else {
            notice = "A page can't go inside itself or one of its own sub-pages."
            return false
        }
        var meta = pages[id] ?? PageMeta()
        meta.parent = parent
        meta.order = PageTree.nextOrder(under: parent, ids: noteIDs, metas: pages)
        pages[id] = meta
        if let parent { expanded.insert(parent) }
        savePages()
        return true
    }

    func toggleFavourite(_ id: UUID) {
        var meta = pages[id] ?? PageMeta()
        meta.favourite.toggle()
        pages[id] = meta
        savePages()
    }

    func setIcon(_ icon: String?, for id: UUID) {
        var meta = pages[id] ?? PageMeta()
        meta.icon = icon
        pages[id] = meta
        savePages()
    }

    func toggleExpanded(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// A deleted page's sub-pages move up a level rather than disappearing.
    func pageDeleted(_ id: UUID) {
        let parent = pages[id]?.parent
        for (child, meta) in pages where meta.parent == id {
            var moved = meta
            moved.parent = parent
            pages[child] = moved
        }
        pages[id] = nil
        comments[id] = nil
        savePages()
        saveComments()
    }

    // MARK: Versions

    private func historyFolder(for id: UUID) -> URL {
        historyRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Keeps a version when you've been writing for a while (every ten minutes at most), and lets old ones go.
    func keepVersion(of note: Note, force: Bool = false) {
        let last = lastVersion[note.id] ?? latestVersion(of: note.id)
        guard force || PageHistory.shouldKeep(last: last?.date, lastText: last?.text, now: Date(), text: note.text) else { return }
        let folder = historyFolder(for: note.id)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        try? note.text.write(to: folder.appendingPathComponent(PageHistory.fileName(for: now)), atomically: true, encoding: .utf8)
        lastVersion[note.id] = (now, note.text)
        let all = versions(of: note.id)
        for date in PageHistory.toDelete(all.map(\.date), now: now, calendar: .current) {
            if let version = all.first(where: { $0.date == date }) { try? FileManager.default.removeItem(at: version.url) }
        }
    }

    private func latestVersion(of id: UUID) -> (date: Date, text: String)? {
        guard let newest = versions(of: id).first, let text = try? String(contentsOf: newest.url, encoding: .utf8) else { return nil }
        return (newest.date, text)
    }

    /// Newest first.
    func versions(of id: UUID) -> [PageVersion] {
        let files = (try? FileManager.default.contentsOfDirectory(at: historyFolder(for: id), includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in PageHistory.date(fromFileName: url.lastPathComponent).map { PageVersion(date: $0, url: url) } }
            .sorted { $0.date > $1.date }
    }

    func text(of version: PageVersion) -> String {
        (try? String(contentsOf: version.url, encoding: .utf8)) ?? ""
    }

    /// Puts an older version back. What's there now is kept as a version first, so nothing is lost.
    func restore(_ version: PageVersion, to id: UUID) {
        guard let current = notes.first(where: { $0.id == id }) else { return }
        keepVersion(of: current, force: true)
        update(id, text: text(of: version))
        notice = "Put back the version from \(version.date.formatted(date: .abbreviated, time: .shortened)). What was there is kept in the history."
    }

    // MARK: Checkboxes to tasks

    /// Every open checkbox becomes a task in Leo's Tasks, read the way quick add reads it ("Call Tom tomorrow 3pm").
    @discardableResult
    func sendCheckboxesToTasks(_ id: UUID) -> Int {
        guard let note = notes.first(where: { $0.id == id }), let tasks else { return 0 }
        let open = PageCheckboxes.open(in: note.text)
        guard !open.isEmpty else {
            notice = "No open checkboxes on this page. Start a line with - [ ] to make one."
            return 0
        }
        var text = note.text
        for item in open {
            let origin = TaskOrigin(kind: .note, monogram: "bn", label: "Page · \(note.title)", reference: id.uuidString, quote: item.text)
            if tasks.add(item.text, in: .inbox, origin: origin, select: false) != nil {
                text = PageCheckboxes.tick(line: item.line, in: text, note: "→ Tasks")
            }
        }
        update(id, text: text)
        notice = open.count == 1 ? "Leo added 1 task from this page." : "Leo added \(open.count) tasks from this page."
        return open.count
    }

    // MARK: Comments

    func addComment(_ text: String, to id: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let note = notes.first(where: { $0.id == id }) else { return }
        comments[id, default: []].append(PageComment(author: "you", text: trimmed, date: Date()))
        saveComments()
        for monogram in Mentions.agents(in: trimmed) {
            answer(trimmed, by: monogram, on: note)
        }
    }

    func resolveComment(_ comment: UUID, on id: UUID) {
        guard let index = comments[id]?.firstIndex(where: { $0.id == comment }) else { return }
        comments[id]?[index].resolved.toggle()
        saveComments()
    }

    func deleteComment(_ comment: UUID, on id: UUID) {
        comments[id]?.removeAll { $0.id == comment }
        saveComments()
    }

    /// An agent answers a comment that mentions them, from the page.
    private func answer(_ comment: String, by monogram: String, on note: Note) {
        let name = Mentions.agents.first { $0.monogram == monogram }?.name ?? "Bolton"
        // "@Leo turn these into tasks" does it rather than talking about it.
        if monogram == "le", comment.lowercased().contains("task") {
            let count = sendCheckboxesToTasks(note.id)
            let reply = count == 0 ? "There are no open checkboxes on this page yet. Start a line with - [ ] and ask me again."
                : "Done: \(count) \(count == 1 ? "task is" : "tasks are") in your Inbox in Tasks, each linked back to this page."
            comments[note.id, default: []].append(PageComment(author: monogram, text: reply, date: Date()))
            saveComments()
            return
        }
        let roles = [
            "le": "the chief of staff, who plans the day, the calendar and tasks",
            "mc": "who handles mail and people",
            "wm": "who writes and edits in the user's voice",
            "bn": "who keeps notes and memory and finds things",
            "jm": "who researches",
            "ge": "who handles money and spreadsheets",
            "cr": "who handles customers, the pipeline and decks",
            "rt": "who designs",
            "co": "who edits video and audio",
            "hr": "who teaches and explains",
            "jo": "who builds software and automations",
        ]
        let request = BrainRequest(
            system: "You are \(name), \(roles[monogram] ?? "one of the agents") in 11am, a Mac app for founders. Someone mentioned you in a comment on one of their pages. Reply in two to five plain sentences, no headings or bullet symbols. Use only what's on the page and what they asked. If something isn't on the page, say so.",
            prompt: "Page: \(note.title)\n\n\(String(note.text.prefix(8_000)))\n\nTheir comment: \(comment)",
            weight: .quick)
        let run = brain.run(request)
        answering.insert(note.id)
        Task { @MainActor in
            await run.finished()
            answering.remove(note.id)
            let reply: String
            if case .done = run.status {
                reply = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                reply = "I couldn't answer just now: \(run.status.failureText)."
            }
            comments[note.id, default: []].append(PageComment(author: monogram, text: reply, date: Date()))
            saveComments()
        }
    }

    // MARK: Notion

    func looksLikeNotionExport(_ folder: URL) -> Bool {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var checked = 0
        while let file = enumerator?.nextObject() as? URL, checked < 200 {
            checked += 1
            let name = file.deletingPathExtension().lastPathComponent
            if let last = name.split(separator: " ").last, last.count == 32, last.allSatisfy(\.isHexDigit) { return true }
        }
        return false
    }

    /// A Notion export, nesting kept: pages under their pages, databases as sheets in Sheets with a page that shows them.
    func importNotion(_ folder: URL) -> Int {
        var absolute: [String: URL] = [:]
        let base = folder.standardizedFileURL.path
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        while let file = enumerator?.nextObject() as? URL {
            let path = file.standardizedFileURL.path
            guard path.hasPrefix(base) else { continue }
            let relative = String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !relative.isEmpty { absolute[relative] = file }
        }
        // The export's own folder isn't a page; what's inside it is the top level.
        let keys = Array(absolute.keys)
        var byStripped: [String: URL] = [:]
        for (original, short) in zip(keys, NotionExport.withoutCommonRoot(keys)) {
            byStripped[short] = absolute[original]
        }
        let target = Self.folderName("Notion")
        var ids: [String: UUID] = [:]
        var databases: [URL] = []
        var count = 0
        for (position, entry) in NotionExport.entries(paths: Array(byStripped.keys)).enumerated() {
            var text: String
            if entry.isDatabase {
                if let url = byStripped[entry.path] { databases.append(url) }
                text = "# \(entry.title)\n\nThis was a Notion database. It's now a workbook in Sheets:\n\n{{sheet: \(entry.title)}}\n"
            } else if entry.isFolderOnly {
                text = "# \(entry.title)\n"
            } else {
                guard let url = byStripped[entry.path],
                      let body = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { continue }
                text = NotionExport.wikiLinks(body)
                if !text.hasPrefix("#") { text = "# \(entry.title)\n\n" + text }
            }
            let note = Note(id: UUID(), text: text, folder: target, pinned: false, created: Date(), modified: Date())
            add(note)
            ids[entry.path] = note.id
            if let parentPath = entry.parentPath, let parent = ids[parentPath] {
                pages[note.id] = PageMeta(parent: parent, order: Double(position))
            }
            count += 1
        }
        savePages()
        if !databases.isEmpty { sheets?.importURLs(databases) }
        expanded.formUnion(Set(pages.values.compactMap(\.parent)))
        return count
    }

    // MARK: Sample

    /// A small company wiki, for screenshots and for trying pages out.
    func loadPageSample() {
        if let existing = note(titled: "Website relaunch"), pages[existing.id]?.parent != nil {
            selectedID = existing.id
            return
        }
        func page(_ text: String, parent: UUID?, icon: String? = nil, favourite: Bool = false) -> UUID {
            let note = Note(id: UUID(), text: text, folder: "", pinned: false, created: Date(), modified: Date())
            add(note)
            pages[note.id] = PageMeta(parent: parent, icon: icon, favourite: favourite, order: Double(pages.count))
            return note.id
        }
        let handbook = page("# Company handbook\n\nHow we work, what we're building, and where everything lives.\n\n- [[How we work]]\n- [[Projects]]\n", parent: nil, icon: "📘", favourite: true)
        _ = page("# How we work\n\nWe write things down. Decisions go in the page they belong to, with the date.\n\n## Weekly rhythm\n- Monday: plan the week with Leo\n- Thursday: demo what shipped\n- Friday: weekly review\n", parent: handbook, icon: "🧭")
        let projects = page("# Projects\n\nOne page per project, with its tasks and numbers live inside it.\n", parent: handbook, icon: "🗂️")
        let website = page("""
        # Website relaunch

        New homepage, About page and redirects, live by the end of the month. Owner: you. Design: Robert.

        ## Before launch
        - [ ] Send Robert the copy for the homepage by Friday
        - [ ] Check the redirects on staging next Tuesday #web
        - [x] Pick the hosting plan

        ## Live from Tasks
        {{tasks: Website relaunch}}

        ## Budget
        {{sheet: Budget}}

        ## Decisions
        - 3 Nov: keep the old blog at /journal.
        """, parent: projects, icon: "🌐", favourite: true)
        _ = page("# Launch plan\n\nNewsletter on launch day, LinkedIn post the day after.\n\n{{page: How we work}}\n", parent: website, icon: "🚀")
        comments[website] = [
            PageComment(author: "you", text: "@Leo what's left before we can launch?", date: Date().addingTimeInterval(-3_600)),
            PageComment(author: "le", text: "Two things are open on this page: Robert needs the homepage copy by Friday, and the redirects need checking on staging next Tuesday. The hosting plan is done. The About page is due Monday in Tasks.", date: Date().addingTimeInterval(-3_500)),
        ]
        expanded.formUnion([handbook, projects, website])
        savePages()
        saveComments()
        selectedID = website
    }
}
