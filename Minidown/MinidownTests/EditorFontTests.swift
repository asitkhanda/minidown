import AppKit
import XCTest
@testable import Minidown

/// The bundled faces must actually load, and the unbundled one must degrade cleanly.
@MainActor
final class EditorFontTests: XCTestCase {
    override func setUp() {
        super.setUp()
        EditorFonts.registerBundledFonts()
    }

    func testBundledFontsAreShippedAndRegistered() throws {
        let fonts = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("Fonts"))
        let files = try FileManager.default.contentsOfDirectory(atPath: fonts.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("DMSans") }, "DM Sans must ship in the bundle")
        XCTAssertTrue(files.contains { $0.hasPrefix("FiraCode") }, "Fira Code must ship in the bundle")
        XCTAssertTrue(files.contains { $0.hasPrefix("Spectral") }, "Spectral must ship in the bundle")

        XCTAssertTrue(EditorFonts.isAvailable(EditorFonts.sansSerifFamily), "DM Sans did not register")
        XCTAssertTrue(EditorFonts.isAvailable(EditorFonts.monospaceFamily), "Fira Code did not register")
        XCTAssertTrue(EditorFonts.isAvailable(EditorFonts.serifFamily), "Spectral did not register")
    }

    /// Redistribution of these two is what the SIL OFL permits, so the licences must travel too.
    func testOpenFontLicencesAreBundled() throws {
        let fonts = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("Fonts"))
        for licence in ["DMSans-OFL.txt", "FiraCode-OFL.txt", "Spectral-OFL.txt"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: fonts.appendingPathComponent(licence).path),
                "\(licence) must ship alongside the font it covers"
            )
        }
    }

    func testSansSerifResolvesToDMSans() {
        let font = EditorFontFamily.sansSerif.font(ofSize: 17)
        XCTAssertEqual(font.familyName, EditorFonts.sansSerifFamily)
        XCTAssertEqual(font.pointSize, 17)
        XCTAssertFalse(EditorFontFamily.sansSerif.isUsingFallback)
    }

    func testTypewriterResolvesToFiraCode() {
        let font = EditorFontFamily.typewriter.font(ofSize: 15)
        XCTAssertEqual(font.familyName, EditorFonts.monospaceFamily)
        XCTAssertFalse(EditorFontFamily.typewriter.isUsingFallback)
    }

    /// Code is always Fira Code, whatever the prose is set in.
    func testCodeUsesFiraCodeForEveryProseFont() {
        for family in EditorFontFamily.allCases {
            XCTAssertEqual(
                family.monoFont(ofSize: 14).familyName,
                EditorFonts.monospaceFamily,
                "\(family.title) should still set code in Fira Code"
            )
        }
    }

    /// Weight has to come through the descriptor: DM Sans ships only as a variable font, so a
    /// naive `NSFont(name:size:)` would draw Regular for every weight.
    func testWeightsResolveOnAVariableFont() {
        let regular = EditorFontFamily.sansSerif.font(ofSize: 17, weight: .regular)
        let semibold = EditorFontFamily.sansSerif.font(ofSize: 17, weight: .semibold)
        XCTAssertNotEqual(
            regular.fontDescriptor.object(forKey: .face) as? String,
            semibold.fontDescriptor.object(forKey: .face) as? String,
            "semibold must be a different instance from regular"
        )
    }

    func testSerifResolvesToSpectral() {
        let font = EditorFontFamily.serif.font(ofSize: 17)
        XCTAssertEqual(font.familyName, EditorFonts.serifFamily)
        XCTAssertEqual(font.pointSize, 17)
        XCTAssertFalse(EditorFontFamily.serif.isUsingFallback)
    }

    /// Every prose face is bundled, so nothing should be substituting at runtime.
    func testNoFamilyIsSilentlySubstituted() {
        for family in EditorFontFamily.allCases {
            XCTAssertFalse(family.isUsingFallback, "\(family.title) fell back to a system face")
            XCTAssertEqual(family.menuTitle, family.title)
        }
    }

    func testUnavailableFamilyReportsCorrectly() {
        XCTAssertFalse(EditorFonts.isAvailable("A Font That Does Not Exist"))
        XCTAssertNil(EditorFonts.firstAvailable(["Nope One", "Nope Two"]))
        XCTAssertEqual(
            EditorFonts.firstAvailable(["Nope One", EditorFonts.monospaceFamily]),
            EditorFonts.monospaceFamily
        )
    }
}
