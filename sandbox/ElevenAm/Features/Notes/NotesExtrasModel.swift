import AppKit
import CryptoKit
import Foundation
import LocalAuthentication

/// Smart folders, locked notes and voice notes.
extension NotesModel {
    private var smartURL: URL { root.appendingPathComponent(".smart.json") }

    func loadExtras() {
        if let data = try? Data(contentsOf: smartURL), let saved = try? JSONDecoder().decode([SmartFolder].self, from: data) {
            smartFolders = saved
        } else {
            smartFolders = NoteQuery.suggestions
        }
    }

    private func saveSmartFolders() {
        if let data = try? JSONEncoder().encode(smartFolders) { try? data.write(to: smartURL, options: .atomic) }
    }

    // MARK: Smart folders

    func matches(smart id: UUID, _ note: Note) -> Bool {
        guard let folder = smartFolders.first(where: { $0.id == id }) else { return false }
        let query = NoteQuery.parse(folder.query)
        return !query.isEmpty && query.matches(text: note.text, folder: note.folder, pinned: note.pinned, modified: note.modified,
                                               now: Date(), calendar: .current)
    }

    func count(smart id: UUID) -> Int { notes.filter { matches(smart: id, $0) }.count }

    /// Saves what's in the search box as a folder that keeps itself up to date.
    func saveSmartFolder(named name: String, query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let folder = SmartFolder(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? trimmed : name, query: trimmed)
        smartFolders.append(folder)
        saveSmartFolders()
        search = ""
        scope = .smart(folder.id)
    }

    func deleteSmartFolder(_ id: UUID) {
        smartFolders.removeAll { $0.id == id }
        saveSmartFolders()
        if scope == .smart(id) { scope = .all }
    }

    // MARK: Locked notes

    func isLocked(_ note: Note) -> Bool { NoteLock.isLocked(note.text) }
    func isOpen(_ note: Note) -> Bool { unlocked[note.id] != nil }

    /// What the editor shows: the note, or the opened words of a locked one.
    func editableText(_ id: UUID) -> String {
        if let open = unlocked[id] { return open }
        return notes.first { $0.id == id }?.text ?? ""
    }

    /// Edits go to the note, sealed again if it's locked.
    func edit(_ id: UUID, text: String) {
        guard unlocked[id] != nil else {
            update(id, text: text)
            return
        }
        unlocked[id] = text
        guard let key = lockKey(create: false), let sealed = try? NoteLock.seal(text, title: title(of: text), key: key) else { return }
        update(id, text: sealed)
    }

    func lock(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }), !NoteLock.isLocked(note.text), let key = lockKey(create: true),
              let sealed = try? NoteLock.seal(note.text, title: note.title, key: key) else { return }
        update(id, text: sealed)
        unlocked[id] = nil
        notice = "Locked. Open it with Touch ID or your Mac password. It's sealed on disk, so search and Ask can't read it."
    }

    /// Asks for Touch ID or your Mac password, then opens the note until you move away from it.
    func unlock(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "open \u{201C}\(note.title)\u{201D}") { ok, _ in
            Task { @MainActor in
                guard ok else { return }
                guard let key = self.lockKey(create: false), let text = try? NoteLock.open(note.text, key: key) else {
                    self.notice = "That note couldn't be opened. Its key isn't in this Mac's Keychain."
                    return
                }
                self.unlocked[id] = text
            }
        }
    }

    /// Takes the lock off: the note is plain Markdown again.
    func removeLock(_ id: UUID) {
        guard let text = unlocked[id] else { return }
        unlocked[id] = nil
        update(id, text: text)
    }

    private func lockKey(create: Bool) -> SymmetricKey? {
        if let stored = Keychain.read(account: "notes-lock-key"), let key = NoteLock.key(from: stored) { return key }
        guard create else { return nil }
        let key = NoteLock.newKey()
        Keychain.save(NoteLock.keyText(key), account: "notes-lock-key")
        return key
    }

    private func title(of text: String) -> String {
        let title = MarkdownInfo.title(text)
        return title.isEmpty ? "Locked note" : title
    }

    // MARK: Voice notes

    /// Records into the open note (or a new one), then writes out what was said, on this Mac.
    func startVoiceNote() {
        Task { @MainActor in
            guard await MicRecorder.permission() else {
                notice = "11am needs the microphone. Allow it in System Settings › Privacy & Security › Microphone."
                return
            }
            let target: UUID
            if let selected, !NoteLock.isLocked(selected.text) {
                target = selected.id
            } else {
                target = newNote(text: "# Voice note, \(Date().formatted(date: .abbreviated, time: .shortened))\n\n").id
            }
            let folder = root.appendingPathComponent("attachments/\(target.uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = folder.appendingPathComponent("voice-\(stamp).caf")
            do {
                try recorder.start(to: url)
                recordingURL = url
                recordingNoteID = target
            } catch {
                notice = "Couldn't start recording: \(error.localizedDescription)"
            }
        }
    }

    func stopVoiceNote() {
        guard let id = recordingNoteID, let url = recordingURL else { return }
        let seconds = Int(recorder.elapsed.rounded())
        recorder.stop()
        recordingNoteID = nil
        recordingURL = nil
        let relative = "attachments/\(id.uuidString)/\(url.lastPathComponent)"
        let length = String(format: "%d:%02d", seconds / 60, seconds % 60)
        let link = "\n\n🎙 [Voice note, \(length)](\(relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative))\n"
        update(id, text: editableText(id) + link)
        transcribing.insert(id)
        Task { @MainActor in
            defer { transcribing.remove(id) }
            do {
                let lines = try await Transcriber.transcribe(url)
                let words = lines.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                guard !words.isEmpty else {
                    notice = "Nothing to write out: the recording was quiet."
                    return
                }
                update(id, text: editableText(id) + "\n> \(words)\n")
                notice = "Voice note written out, on this Mac."
            } catch {
                notice = "The recording is in the note. It couldn't be written out: \(error.localizedDescription)"
            }
        }
    }
}
