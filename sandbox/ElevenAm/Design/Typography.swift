import CoreText
import Foundation

enum FontRegistry {
    /// Registers the bundled Alte Haas Grotesk faces for this process (no install needed).
    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
