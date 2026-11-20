import CoreText
import Foundation

enum FontRegistry {
    /// Registers the bundled brand faces for this process (no install needed): Schibsted Grotesk, Instrument Sans,
    /// Courier Prime, Hack and Reenie Beanie.
    static func registerBundledFonts() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
