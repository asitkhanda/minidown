// minidown — a minimal, distraction-free Markdown writer for macOS.
// Copyright (C) 2026 Asit Khanda
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU Affero General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option) any
// later version. See <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: AGPL-3.0-or-later

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
