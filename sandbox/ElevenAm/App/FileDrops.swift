import AppKit
import UniformTypeIdentifiers

/// Files dropped on a view, read from the drag's item providers.
enum FileDrops {
    /// The file URLs in a drop, in the order they came, handed over on the main thread once they've all loaded.
    static func urls(from providers: [NSItemProvider], _ done: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var slots = [URL?](repeating: nil, count: providers.count)
        for (index, provider) in providers.enumerated() where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                lock.lock()
                slots[index] = url
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = slots.compactMap { $0 }
            MainActor.assumeIsolated { done(urls) }
        }
    }

    /// The files being dragged right now, anywhere on the screen.
    static func dragged() -> [URL] {
        NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}
