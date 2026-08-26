import AppKit

/// Draws the menu bar gauge — a ring that fills up with the current
/// utilization — into an image, one frame at a time.
///
/// Rendering to `NSStatusBarButton.image` instead of hosting a custom view
/// keeps the button's own geometry intact, which is what AppKit uses to
/// anchor the popover right under the menu bar.
@MainActor
final class MenuBarGauge {
    /// Called with a freshly rendered frame; assign it to the button's image.
    var onFrame: ((NSImage) -> Void)?

    private var target: Double = 0
    private var displayed: Double = 0
    private var pulsePhase: Double = 0
    private var animation: Timer?
    private var level: UsageLevel = .comfortable
    private var isStale = false

    private static let frameDuration = 1.0 / 30.0
    private static let ringWidth: CGFloat = 2.6
    private static let diameter: CGFloat = 16
    private static let dotDiameter: CGFloat = 6
    private static let height: CGFloat = 18

    /// The style actually drawn: the quiet threshold overrides the preference
    /// while the session is far from its cap, but never hides the item — the
    /// dot stays clickable, which `isVisible = false` would not.
    private var effectiveStyle: MenuBarStyle {
        let threshold = Preferences.discreetBelowPercent
        if threshold > 0 && target * 100 < Double(threshold) { return .dot }
        return Preferences.menuBarStyle
    }

    private var showsRing: Bool {
        switch effectiveStyle {
        case .ring, .ringPercent: return true
        case .percent, .dot: return false
        }
    }

    private var showsText: Bool {
        switch effectiveStyle {
        case .ringPercent, .percent: return true
        case .ring, .dot: return false
        }
    }

    /// Dimmed while the quiet threshold is what forced the dot, so the icon
    /// reads as "nothing to see here" rather than as an error.
    private var isQuiet: Bool {
        let threshold = Preferences.discreetBelowPercent
        return threshold > 0
            && target * 100 < Double(threshold)
            && Preferences.menuBarStyle != .dot
    }

    var width: CGFloat {
        switch effectiveStyle {
        case .ring: return Self.diameter + 4
        case .ringPercent: return Self.diameter + 34
        case .percent: return 32
        case .dot: return Self.dotDiameter + 8
        }
    }

    func update(fraction: Double, level: UsageLevel, stale: Bool) {
        target = min(max(fraction, 0), 1)
        self.level = level
        isStale = stale
        // With Reduce Motion on there is nothing to animate: jump to the value
        // and skip the 30 fps timer entirely.
        if Preferences.reduceMotion {
            animation?.invalidate()
            animation = nil
            displayed = target
            pulsePhase = 0
        } else {
            startAnimating()
        }
        render()
    }

    private func startAnimating() {
        guard animation == nil else { return }
        let timer = Timer(timeInterval: Self.frameDuration, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated { self?.step(timer) }
        }
        RunLoop.main.add(timer, forMode: .common)
        animation = timer
    }

    private func step(_ timer: Timer) {
        // Exponential ease toward the target; settles in roughly half a second.
        let delta = target - displayed
        displayed += delta * 0.18
        let settled = abs(delta) < 0.002
        if settled { displayed = target }

        let shouldPulse = level == .critical && !isStale
        pulsePhase = shouldPulse ? pulsePhase + Self.frameDuration : 0

        if settled && !shouldPulse {
            timer.invalidate()
            animation = nil
        }
        render()
    }

    private var tint: NSColor {
        if isStale { return .disabledControlTextColor }
        switch level {
        case .comfortable: return .systemGreen
        case .watch: return .systemYellow
        case .tight: return .systemOrange
        case .critical: return .systemRed
        }
    }

    private func render() {
        let size = NSSize(width: width, height: Self.height)
        let image = NSImage(size: size, flipped: false) { [self] _ in
            draw(in: size)
            return true
        }
        // Not a template image: the fill color is the whole point.
        image.isTemplate = false
        onFrame?(image)
    }

    private func draw(in size: NSSize) {
        let pulse = pulsePhase > 0 ? 0.55 + 0.45 * (0.5 + 0.5 * sin(pulsePhase * 4)) : 1.0
        let alpha = pulse * (isQuiet ? 0.45 : 1.0)

        if effectiveStyle == .dot {
            let rect = NSRect(x: (size.width - Self.dotDiameter) / 2,
                              y: (size.height - Self.dotDiameter) / 2,
                              width: Self.dotDiameter,
                              height: Self.dotDiameter)
            tint.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return
        }

        var textOrigin = NSPoint(x: 2, y: 0)

        if showsRing {
            let ringRect = NSRect(x: 2,
                                  y: (size.height - Self.diameter) / 2,
                                  width: Self.diameter,
                                  height: Self.diameter)
            let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
            let radius = Self.diameter / 2 - Self.ringWidth / 2

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = Self.ringWidth
            NSColor.tertiaryLabelColor.withAlphaComponent(isQuiet ? 0.45 : 1).setStroke()
            track.stroke()

            if displayed > 0.001 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center,
                              radius: radius,
                              startAngle: 90,
                              endAngle: 90 - 360 * displayed,
                              clockwise: true)
                arc.lineWidth = Self.ringWidth
                arc.lineCapStyle = .round
                tint.withAlphaComponent(alpha).setStroke()
                arc.stroke()
            }
            textOrigin.x = ringRect.maxX + 4
        }

        guard showsText else { return }
        let text = "\(Int((displayed * 100).rounded()))%"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha),
        ]
        let textSize = text.size(withAttributes: attributes)
        // Percentage-only centers in its own narrow slot; alongside the ring it
        // keeps the fixed offset so the item does not jitter as digits change.
        let x = showsRing ? textOrigin.x : (size.width - textSize.width) / 2
        text.draw(at: NSPoint(x: x, y: (size.height - textSize.height) / 2),
                  withAttributes: attributes)
    }
}
