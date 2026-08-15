import Foundation
import XCTest

/// Access to the `examples/` fixtures.
///
/// These are copied into the test bundle as a folder reference rather than read out of the source
/// tree with `#filePath`. Reading the source tree at runtime fails whenever the checkout sits in a
/// TCC-protected location such as `~/Documents`, and stops working altogether under App Sandbox.
enum ExampleDocuments {
    static var directory: URL {
        guard let url = Bundle(for: BundleToken.self).resourceURL?.appendingPathComponent("examples") else {
            fatalError("test bundle has no resource URL")
        }
        return url
    }

    /// Every `.md` fixture, sorted for stable test ordering.
    static func allMarkdownNames() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".md") }
            .sorted()
    }

    static func text(named name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}

private final class BundleToken {}
