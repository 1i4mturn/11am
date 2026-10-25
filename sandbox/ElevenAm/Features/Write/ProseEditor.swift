import AppKit
import SwiftUI

/// A plain-text writing surface on NSTextView, so the app can see the selection
/// (SwiftUI's TextEditor only exposes it from macOS 15).
struct ProseEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var font: NSFont
    var textColor: NSColor
    var lineSpacing: CGFloat = 6

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.textContainerInset = NSSize(width: 0, height: 14)
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text
        apply(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }
        var restyle = false
        if textView.string != text {
            let keep = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            let location = min(keep.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(keep.length, length - location)))
            restyle = true
        }
        // Restyle only when the look changes or the text was replaced, never mid-typing (it would break input methods).
        let rgb = textColor.usingColorSpace(.sRGB)
        let style = "\(font.fontName)-\(font.pointSize)-\(rgb?.redComponent ?? 0)-\(rgb?.alphaComponent ?? 1)-\(lineSpacing)"
        if restyle || style != context.coordinator.lastStyle {
            context.coordinator.lastStyle = style
            apply(to: textView)
        }
    }

    private func apply(to textView: NSTextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = lineSpacing * 1.5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]
        textView.typingAttributes = attributes
        textView.insertionPointColor = textColor
        if let storage = textView.textStorage, storage.length > 0 {
            storage.beginEditing()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ProseEditor
        var isUpdating = false
        var lastStyle = ""

        init(_ parent: ProseEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            // Selection changes arrive mid-update; hand them to SwiftUI on the next turn.
            DispatchQueue.main.async { [weak self] in
                self?.parent.selection = range
            }
        }
    }
}
