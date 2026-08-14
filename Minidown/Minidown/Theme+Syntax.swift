import AppKit

extension AppColors {
    static let codeBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1, alpha: 0.08)
            : NSColor(calibratedRed: 0.106, green: 0.106, blue: 0.114, alpha: 0.05)
    }

    static let sxKeyword = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.30, green: 0.67, blue: 0.97, alpha: 1)
            : NSColor(calibratedRed: 0.098, green: 0.443, blue: 0.761, alpha: 1)
    }

    static let sxString = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.41, green: 0.86, blue: 0.49, alpha: 1)
            : NSColor(calibratedRed: 0.184, green: 0.620, blue: 0.267, alpha: 1)
    }

    static let sxComment = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.43, alpha: 1)
            : NSColor(calibratedWhite: 0.60, alpha: 1)
    }

    static let sxNumber = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.30, alpha: 1)
            : NSColor(calibratedRed: 0.910, green: 0.349, blue: 0.047, alpha: 1)
    }

    static let sxType = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.855, green: 0.467, blue: 0.949, alpha: 1)
            : NSColor(calibratedRed: 0.612, green: 0.212, blue: 0.710, alpha: 1)
    }

    static let sxFunc = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.569, green: 0.655, blue: 1.0, alpha: 1)
            : NSColor(calibratedRed: 0.231, green: 0.357, blue: 0.859, alpha: 1)
    }
}
