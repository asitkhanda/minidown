import AppKit
import SwiftUI

/// Native Liquid Glass, with a coherent fallback below macOS 26.
///
/// The window backdrop uses AppKit's `NSGlassEffectView` rather than SwiftUI's `glassEffect`:
/// `glassEffect` is designed for discrete floating controls with a shape, while the window surface
/// wants a full-bleed material that samples what is behind the window. Discrete chrome — the
/// status bar and its controls — does use the SwiftUI modifiers, which is what they are for.
enum LiquidGlass {
    /// Corner radius for grouped chrome, matching the system's control curvature.
    static let chromeCornerRadius: CGFloat = 12

    /// The tint applied to the window glass. Dynamic, so it tracks light and dark.
    ///
    /// Liquid Glass is designed for the interface layer floating *above* content, not for the
    /// content itself. Left untinted, whatever is behind the window shows through the prose and
    /// the document becomes genuinely hard to read — the opposite of what a distraction-free
    /// writer is for. Chrome stays pure glass; the canvas keeps enough paper for text to stay
    /// crisp while the material still reads at the edges and in motion.
    static var canvasTint: NSColor { AppColors.glassCanvasTint }
}

/// Full-bleed window backdrop.
struct GlassBackdrop: NSViewRepresentable {
    var style: ChromeStyle
    /// Tint keeps text legible over busy desktops without making the glass opaque.
    var tint: NSColor?

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        rebuild(in: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        rebuild(in: nsView)
        configureWindow(for: nsView)
    }

    private func rebuild(in container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }

        let backdrop: NSView
        if style.usesGlass, #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.tintColor = tint ?? LiquidGlass.canvasTint
            backdrop = glass
        } else {
            // Below macOS 26: a vibrant material, which is the closest coherent surface available.
            let effect = NSVisualEffectView()
            effect.material = .underWindowBackground
            effect.blendingMode = .behindWindow
            effect.state = .active
            backdrop = effect
        }

        backdrop.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: container.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    /// Glass samples what is behind the window, so the window itself must not paint over it.
    ///
    /// Only opacity changes here. The title bar stays transparent in both styles: toggling
    /// `titlebarAppearsTransparent` alters the window's chrome metrics, so switching material
    /// would visibly move the content underneath it.
    private func configureWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.backgroundColor = style.usesGlass ? .clear : .windowBackgroundColor
            window.isOpaque = !style.usesGlass ? true : false
            window.minSize = NSSize(width: 480, height: 320)
        }
    }
}

extension View {
    /// Applies Liquid Glass to a piece of chrome, falling back to a material below macOS 26.
    ///
    /// `.glassEffect` is the real thing: it refracts and reacts to what is behind it, which
    /// `.ultraThinMaterial` only approximates.
    @ViewBuilder
    func chromeGlass(_ style: ChromeStyle, cornerRadius: CGFloat = LiquidGlass.chromeCornerRadius) -> some View {
        if style.usesGlass, #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else if style.usesGlass {
            self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
        }
    }

    /// Groups nearby glass elements so the system can merge and batch them.
    @ViewBuilder
    func glassGroup(_ style: ChromeStyle) -> some View {
        if style.usesGlass, #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { self }
        } else {
            self
        }
    }

    /// A status-bar control whose *metrics are identical* in every chrome style.
    ///
    /// Swapping `.buttonStyle(.glass)` for `.buttonStyle(.plain)` changed the layout, not just the
    /// material: glass buttons are padded capsules and plain buttons are bare text, so the status
    /// bar's height and every control's width shifted when the window style changed — and the
    /// editor moved with it. Metrics are fixed here and only the background differs.
    func statusChip(_ style: ChromeStyle, isHighlighted: Bool = false) -> some View {
        buttonStyle(StatusChipStyle(chrome: style, isHighlighted: isHighlighted))
    }
}

/// Fixed-metric status bar control. Only its background reflects the chrome style.
struct StatusChipStyle: ButtonStyle {
    let chrome: ChromeStyle
    var isHighlighted = false

    /// Shared by every chrome style, so the bar is exactly the same size in each.
    private static let horizontalPadding: CGFloat = 10
    private static let verticalPadding: CGFloat = 4
    private static let minHeight: CGFloat = 20
    private static let cornerRadius: CGFloat = 10

    /// Exposed so a test can assert the metrics do not vary with chrome or state.
    struct Metrics: Equatable {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let minHeight: CGFloat
        let cornerRadius: CGFloat
    }

    var metrics: Metrics {
        Metrics(
            horizontalPadding: Self.horizontalPadding,
            verticalPadding: Self.verticalPadding,
            minHeight: Self.minHeight,
            cornerRadius: Self.cornerRadius
        )
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .frame(minHeight: Self.minHeight)
            .background { background }
            .contentShape(.rect(cornerRadius: Self.cornerRadius))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .foregroundStyle(
                isHighlighted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)
            )
    }

    @ViewBuilder
    private var background: some View {
        if chrome.usesGlass, #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.interactive(), in: .rect(cornerRadius: Self.cornerRadius))
        } else {
            // Same footprint, different surface: a quiet fill instead of glass.
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(Color.primary.opacity(0.06))
        }
    }
}

extension AppColors {
    /// The editor surface. Clear under glass so the material shows through — an opaque background
    /// here would defeat the entire effect.
    static func editorBackground(glass: Bool) -> NSColor {
        glass ? .clear : background
    }
}
