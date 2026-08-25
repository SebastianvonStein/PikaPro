import Cocoa
import Defaults

/// One accessibility bar the contrast picker can filter against: a standard paired with
/// the text size (WCAG) or the use case (APCA) it applies to. The footer reports every
/// level at once, but the picker has to mask the field against exactly one, so the levels
/// live here as discrete, selectable choices.
enum ComplianceTarget: String, Codable, CaseIterable {
    case wcagAALarge
    case wcagAANormal
    case wcagAAALarge
    case wcagAAANormal
    case apcaBaseline
    case apcaHeadline
    case apcaTitle
    case apcaBody

    var standard: ContrastStandard {
        switch self {
        case .wcagAALarge, .wcagAANormal, .wcagAAALarge, .wcagAAANormal: return .wcag
        case .apcaBaseline, .apcaHeadline, .apcaTitle, .apcaBody: return .apca
        }
    }

    /// The bar to clear: a WCAG contrast ratio, or an absolute APCA lightness contrast.
    var threshold: CGFloat {
        switch self {
        case .wcagAALarge: return 3.0
        case .wcagAANormal: return 4.5
        case .wcagAAALarge: return 4.5
        case .wcagAAANormal: return 7.0
        case .apcaBaseline: return 30.0
        case .apcaHeadline: return 45.0
        case .apcaTitle: return 60.0
        case .apcaBody: return 75.0
        }
    }

    /// The conformance level ("AA") or APCA use case ("Headline").
    var title: String {
        switch self {
        case .wcagAALarge, .wcagAANormal: return "AA"
        case .wcagAAALarge, .wcagAAANormal: return "AAA"
        case .apcaBaseline: return PikaText.textAPCABaseline
        case .apcaHeadline: return PikaText.textAPCAHeadline
        case .apcaTitle: return PikaText.textAPCATitle
        case .apcaBody: return PikaText.textAPCABody
        }
    }

    /// The qualifier after the level — text size for WCAG, the Lc bar for APCA.
    var detail: String {
        switch self {
        case .wcagAALarge, .wcagAAALarge: return PikaText.textColorLarge
        case .wcagAANormal, .wcagAAANormal: return PikaText.textColorNormal
        case .apcaBaseline, .apcaHeadline, .apcaTitle, .apcaBody:
            return "Lc \(Int(threshold))"
        }
    }

    /// Full label for the picker's target menu, e.g. "AA · Normal".
    var label: String { "\(title) · \(detail)" }

    /// Tooltip text, reusing the footer's existing per-level descriptions.
    var tooltip: String {
        switch self {
        case .wcagAALarge: return PikaText.textColorWCAG30
        case .wcagAANormal, .wcagAAALarge: return PikaText.textColorWCAG45
        case .wcagAAANormal: return PikaText.textColorWCAG70
        case .apcaBaseline: return PikaText.textColorAPCA30
        case .apcaHeadline: return PikaText.textColorAPCA45
        case .apcaTitle: return PikaText.textColorAPCA60
        case .apcaBody: return PikaText.textColorAPCA75
        }
    }

    /// The targets on offer for a contrast standard. `.both` lists all of them, in the
    /// same WCAG-then-APCA order the footer stacks its two rows.
    static func targets(for standard: ContrastStandard) -> [ComplianceTarget] {
        switch standard {
        case .wcag: return allCases.filter { $0.standard == .wcag }
        case .apca: return allCases.filter { $0.standard == .apca }
        case .both: return allCases
        }
    }

    /// The level to fall back to when the selected one doesn't belong to the standard the
    /// user has switched to — the most commonly cited bar for each.
    static func defaultTarget(for standard: ContrastStandard) -> ComplianceTarget {
        standard == .apca ? .apcaHeadline : .wcagAANormal
    }

    func passes(foreground: NSColor, background: NSColor) -> Bool {
        ComplianceTest(target: self, background: background).passes(foreground: foreground)
    }
}

/// A compliance target with its background side pre-computed. Rendering the picker field
/// tests tens of thousands of candidate colours against one fixed background, so the
/// background's luminance is resolved once here and every sample reuses it.
struct ComplianceTest {
    let target: ComplianceTarget
    /// Identity of the background side, for view code that needs to know when a redraw
    /// is actually necessary.
    let backgroundKey: String
    private let backgroundLuminance: CGFloat
    private let backgroundY: CGFloat

    init(target: ComplianceTarget, background: NSColor) {
        self.target = target
        let normalized = background.usingColorSpace(.sRGB) ?? background
        let rgb = normalized.toRGBAComponents(in: .sRGB)
        backgroundKey = normalized.toHexString()
        backgroundLuminance = NSColor.relativeLuminance(red: rgb.r, green: rgb.g, blue: rgb.b)
        backgroundY = NSColor.apcaScreenLuminance(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// The candidate's score against the background — a contrast ratio for WCAG, an
    /// absolute Lc for APCA — on the same scale as `target.threshold`.
    func score(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        switch target.standard {
        case .apca:
            let textY = NSColor.apcaScreenLuminance(red: red, green: green, blue: blue)
            return abs(NSColor.apcaLc(textY: textY, backgroundY: backgroundY))
        case .wcag, .both:
            let luminance = NSColor.relativeLuminance(red: red, green: green, blue: blue)
            return NSColor.contrastRatio(luminance: luminance, with: backgroundLuminance)
        }
    }

    func passes(red: CGFloat, green: CGFloat, blue: CGFloat) -> Bool {
        score(red: red, green: green, blue: blue) >= target.threshold
    }

    /// The same verdict for an already-quantised colour, taking the table-driven path.
    /// This is the one the field renderer calls, once per pixel.
    func passes(red: UInt8, green: UInt8, blue: UInt8) -> Bool {
        let score: CGFloat
        switch target.standard {
        case .apca:
            let textY = NSColor.apcaScreenLuminance(red: red, green: green, blue: blue)
            score = abs(NSColor.apcaLc(textY: textY, backgroundY: backgroundY))
        case .wcag, .both:
            let luminance = NSColor.relativeLuminance(red: red, green: green, blue: blue)
            score = NSColor.contrastRatio(luminance: luminance, with: backgroundLuminance)
        }
        return score >= target.threshold
    }

    func passes(foreground: NSColor) -> Bool {
        let rgb = (foreground.usingColorSpace(.sRGB) ?? foreground).toRGBAComponents(in: .sRGB)
        return passes(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

/// Renders the picker's colour field: hue across, lightness down, at a fixed saturation —
/// with the colours that fail the selected compliance target scrimmed out.
///
/// The mask is baked into the bitmap rather than layered as a SwiftUI overlay because the
/// pass/fail boundary is a curve through hue × lightness, not a shape: only a per-pixel
/// test puts the edge exactly where compliance actually flips.
enum ContrastGamut {
    /// Cap on the rendered bitmap so a very wide window doesn't blow up the per-pixel
    /// cost. The field is a smooth gradient, so upscaling the last few points is invisible.
    static let maximumPixels = 1200

    /// How finely to sample the field. Dragging the saturation strip re-renders on every
    /// frame, and at full retina resolution that is a few milliseconds of work per frame —
    /// so interaction gets a coarse pass that lands in a fraction of that, and the full
    /// pass follows once the values settle. Upscaling a `.preview` softens the pass/fail
    /// edge slightly; nothing else about it is different.
    enum Quality {
        case preview
        case full

        var maximumSamples: Int {
            switch self {
            case .preview: return 60_000
            case .full: return 300_000
            }
        }

        /// How much of a shrunk budget to spend on rows rather than columns. The
        /// pass/fail boundary is a shallow, near-horizontal curve: its vertical position
        /// is a hard edge that upscaling can only blur, while hue varies slowly across the
        /// field and interpolates back almost perfectly. So a coarse pass buys rows.
        var heightBias: CGFloat {
            switch self {
            case .preview: return 2
            case .full: return 1
            }
        }
    }

    /// Pixel dimensions for a field of `size` at `scale`, shrunk to fit the quality's
    /// sample budget. Both axes shrink by the same factor, so the aspect ratio — and with
    /// it the shape of the compliance boundary — is preserved.
    static func pixelSize(for size: CGSize, scale: CGFloat, quality: Quality) -> (width: Int, height: Int) {
        var width = min(Int((size.width * scale).rounded()), maximumPixels)
        var height = min(Int((size.height * scale).rounded()), maximumPixels)
        guard width > 0, height > 0 else { return (0, 0) }

        if width * height > quality.maximumSamples {
            // Spend the budget on rows first (see `heightBias`), then give the remainder
            // to columns — never more of either than the field actually needs. Rounding
            // down keeps the result under budget rather than a hair over it.
            let budget = CGFloat(quality.maximumSamples)
            let aspect = CGFloat(width) / CGFloat(height)
            let rows = min(CGFloat(height), (budget * quality.heightBias / aspect).squareRoot())
            height = max(2, Int(rows.rounded(.down)))
            width = max(2, min(width, Int((budget / CGFloat(height)).rounded(.down))))
        }
        return (width, height)
    }

    /// Lightness at a normalised vertical position — top of the field is white.
    static func lightness(atY y: CGFloat) -> CGFloat { 1 - y }

    /// Vertical position for a lightness, the inverse of `lightness(atY:)`.
    static func position(forLightness lightness: CGFloat) -> CGFloat { 1 - lightness }

    static func color(hue: CGFloat, saturation: CGFloat, lightness: CGFloat) -> NSColor {
        NSColor.fromHSL(h: hue, s: saturation, l: lightness)
    }

    // swiftlint:disable:next function_parameter_count
    static func fieldImage(
        size: CGSize,
        scale: CGFloat,
        saturation: CGFloat,
        test: ComplianceTest?,
        scrim: (r: CGFloat, g: CGFloat, b: CGFloat),
        hatched: Bool,
        quality: Quality = .full
    ) -> NSImage? {
        let (width, height) = pixelSize(for: size, scale: scale, quality: quality)
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        // Strength of the scrim over failing colours: enough to read as "unavailable"
        // while the hue underneath still shows through.
        let scrimAlpha: CGFloat = 0.74
        let hatchAlpha: CGFloat = 0.88
        // Scale the hatch to the bitmap, not the screen, so a coarse pass doesn't come
        // back as one solid smear once it's upscaled.
        let stripe = max(4, Int((6 * CGFloat(width) / max(size.width, 1)).rounded()))

        for y in 0 ..< height {
            let level = lightness(atY: (CGFloat(y) + 0.5) / CGFloat(height))
            for x in 0 ..< width {
                let hue = (CGFloat(x) + 0.5) / CGFloat(width)
                let rgb = NSColor.fromHSLComponents(h: hue, s: saturation, l: level)

                // Quantise up front: the compliance test then runs off the lookup tables,
                // and it judges exactly the colour that gets drawn.
                var red = UInt8(clamping: Int((rgb.r * 255).rounded()))
                var green = UInt8(clamping: Int((rgb.g * 255).rounded()))
                var blue = UInt8(clamping: Int((rgb.b * 255).rounded()))

                if let test = test, !test.passes(red: red, green: green, blue: blue) {
                    // Diagonal hatching marks the region as locked, not merely dimmed,
                    // when "restrict to compliant" is refusing clicks there.
                    let onStripe = hatched && ((x + y) % stripe) < max(1, stripe / 4)
                    let alpha = onStripe ? hatchAlpha : scrimAlpha
                    red = blend(red, toward: scrim.r, alpha: alpha)
                    green = blend(green, toward: scrim.g, alpha: alpha)
                    blue = blend(blue, toward: scrim.b, alpha: alpha)
                }

                let offset = (y * width + x) * 4
                pixels[offset] = red
                pixels[offset + 1] = green
                pixels[offset + 2] = blue
                pixels[offset + 3] = 255
            }
        }

        // The context has to be built, drawn from, and finished inside the buffer's
        // lifetime — `makeImage()` reads straight out of `pixels`.
        let image: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }

        guard let image = image else { return nil }
        return NSImage(cgImage: image, size: size)
    }

    private static func blend(_ component: UInt8, toward target: CGFloat, alpha: CGFloat) -> UInt8 {
        let value = CGFloat(component) / 255 * (1 - alpha) + target * alpha
        return UInt8(clamping: Int((value * 255).rounded()))
    }
}
