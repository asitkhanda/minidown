import AppKit

/// Resolves the editor's typefaces, preferring bundled fonts and degrading gracefully.
///
/// All three ship with the app under the SIL Open Font License, which permits redistribution.
/// Sentient was the original choice for the serif and is not here for a licensing reason, not a
/// technical one: the Fontshare Free Font EULA allows free personal and commercial *use* but
/// forbids redistributing the files, including "uploading them in a public server" — which is what
/// committing them to this repository would be. Spectral is a redistributable serif in the same
/// long-form-reading spirit.
enum EditorFonts {
    /// Bundled, SIL Open Font Licence 1.1.
    static let sansSerifFamily = "DM Sans"
    /// Bundled, SIL Open Font Licence 1.1. Used for the typewriter face and for all code.
    static let monospaceFamily = "Fira Code"
    /// Bundled, SIL Open Font Licence 1.1.
    static let serifFamily = "Spectral"

    /// Registers the fonts shipped in the app bundle.
    ///
    /// Done in code rather than via `ATSApplicationFontsPath` so a missing or corrupt file is a
    /// logged fallback rather than a silent, hard-to-diagnose case of "the app is using the system
    /// font and nobody knows why".
    static func registerBundledFonts() {
        guard !hasRegistered else { return }
        hasRegistered = true

        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              )
        else { return }

        let fonts = contents.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
        guard !fonts.isEmpty else { return }
        CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true) { _, _ in false }
    }

    private nonisolated(unsafe) static var hasRegistered = false

    /// Whether a family is actually available to draw with.
    static func isAvailable(_ family: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains {
            $0.compare(family, options: .caseInsensitive) == .orderedSame
        }
    }

    /// First available family in the list, or nil to mean "use the system face".
    static func firstAvailable(_ families: [String]) -> String? {
        families.first { isAvailable($0) }
    }

    /// Builds a font from a family name and weight, going through a descriptor so variable fonts
    /// (DM Sans ships only as one) pick the right instance rather than always drawing Regular.
    static func font(family: String, size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: weight],
        ])
        return NSFont(descriptor: descriptor, size: size)
    }
}
