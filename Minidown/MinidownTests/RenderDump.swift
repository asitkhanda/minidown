// minidown — a minimal, distraction-free Markdown writer for macOS.
// Copyright (C) 2026 Asit Khanda
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU Affero General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option) any
// later version. See <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Foundation

/// Writes render output somewhere a human can look at it.
///
/// The app is sandboxed, so an arbitrary path from the environment is usually unwritable — the
/// container's Caches directory is the reliable destination, and the env var is honoured when it
/// happens to point somewhere the container can reach.
enum RenderDump {
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["MINIDOWN_RENDER_DUMP"],
           FileManager.default.isWritableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let caches = (try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dumps = caches.appendingPathComponent("RenderDumps", isDirectory: true)
        try? FileManager.default.createDirectory(at: dumps, withIntermediateDirectories: true)
        return dumps
    }

    static func write(_ rep: NSBitmapImageRep, named name: String) {
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent(name))
    }

    static func write(_ image: NSImage, named name: String) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        write(rep, named: name)
    }
}
