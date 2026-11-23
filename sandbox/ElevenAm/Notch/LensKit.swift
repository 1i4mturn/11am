import CoreGraphics
import Foundation

/// What the lens read: the words inside its circle, in reading order. Pure, so CI can check it.
enum LensKit {
    struct Word: Equatable {
        var text: String
        /// Where it was found, in the captured picture's points (origin top left).
        var box: CGRect
    }

    /// The lines whose middle falls inside the circle, top to bottom, left to right within a line.
    static func lines(_ words: [Word], center: CGPoint, radius: CGFloat) -> [String] {
        let inside = words.filter { word in
            let middle = CGPoint(x: word.box.midX, y: word.box.midY)
            return hypot(middle.x - center.x, middle.y - center.y) <= radius && !word.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        // Words share a line when their middles are within half a line's height of each other.
        let sorted = inside.sorted { $0.box.midY < $1.box.midY }
        var rows: [[Word]] = []
        for word in sorted {
            if let last = rows.last?.last, abs(last.box.midY - word.box.midY) < max(last.box.height, word.box.height) * 0.5 {
                rows[rows.count - 1].append(word)
            } else {
                rows.append([word])
            }
        }
        return rows.map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }

    /// The first useful line: for a task's title or a look-up, without trailing punctuation, kept short.
    static func headline(_ lines: [String], limit: Int = 70) -> String {
        let first = lines.first { $0.count > 3 } ?? lines.first ?? ""
        var text = first.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ".,;:".contains(last) { text.removeLast() }
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }

    /// Where the lens's circle sits in the picture it took of the square around it.
    static func circle(in size: CGSize) -> (center: CGPoint, radius: CGFloat) {
        (CGPoint(x: size.width / 2, y: size.height / 2), min(size.width, size.height) / 2)
    }
}
