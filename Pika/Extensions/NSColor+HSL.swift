import Cocoa
import Defaults

// swiftlint:disable identifier_name
// identifier_name is disabled because color science math uses conventional single-letter
// variable names (h, s, b, l, r, g) that would be misleading if renamed.

public struct HSBComponents { let h, s, b: CGFloat }
public struct HSLComponents { let h, s, l: CGFloat }
public struct RGBComponents { let r, g, b: CGFloat }

extension NSColor {
    /*
     * HSB
     */

    public final func toHSBComponents() -> HSBComponents {
        var h: CGFloat = 0.0
        var s: CGFloat = 0.0
        var b: CGFloat = 0.0

        guard let rgbaColor = usingColorSpace(Defaults[.colorSpace]) else {
            fatalError("Could not convert color to RGBA.")
        }

        if toHexString() == NSColor.black.toHexString() {
            return HSBComponents(h: 0.0, s: 0.0, b: 0.0)
        } else if toHexString() == NSColor.white.toHexString() {
            return HSBComponents(h: 0.0, s: 0.0, b: 1.0)
        }

        rgbaColor.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        h = h.truncatingRemainder(dividingBy: 1.0)

        return HSBComponents(h: h, s: s, b: b)
    }

    /**
     Get the hsb values of this color in 8-bit format.

     - returns: An NSColor as an 8-bit hsb string.
     */
    func toHSBString(style: CopyFormat = .css) -> String {
        let HSB = toHSBComponents()
        let hue = Int(round(HSB.h * 360))
        let saturation = Int(round(HSB.s * 100))
        let brightness = Int(round(HSB.b * 100))

        let hsbString: String
        switch style {
        case .css:
            hsbString = String(format: "hsb(%d, %d%%, %d%%)", hue, saturation, brightness)
        case .design:
            hsbString = String(format: "hsb(%d, %d, %d)", hue, saturation, brightness)
        case .swiftUI:
            hsbString = String(format: "Color(hue: %.5g, saturation: %.5g, brightness: %.5g)", HSB.h, HSB.s, HSB.b)
        case .unformatted:
            hsbString = String(format: "%d, %d, %d", hue, saturation, brightness)
        }
        return hsbString
    }

    /*
     * HSL
     */

    public final func toHSLComponents() -> HSLComponents {
        var h: CGFloat = 0.0
        var s: CGFloat = 0.0
        var l: CGFloat = 0.0

        let RGB = toRGBAComponents()
        let r = RGB.r
        let g = RGB.g
        let b = RGB.b

        if toHexString() == NSColor.black.toHexString() {
            return HSLComponents(h: 0.0, s: 0.0, l: 0.0)
        } else if toHexString() == NSColor.white.toHexString() {
            return HSLComponents(h: 0.0, s: 0.0, l: 1.0)
        }

        let min = Swift.min(Swift.min(r, g), b)
        let max = Swift.max(Swift.max(r, g), b)
        let delta = max - min

        if max == min {
            h = 0
        } else if r == max {
            h = (g - b) / delta
        } else if g == max {
            h = 2 + (b - r) / delta
        } else {
            h = 4 + (r - g) / delta
        }

        h = Swift.min(h * 60, 360)

        if h < 0 {
            h += 360
        }

        h /= 360

        l = (min + max) / 2

        if max == min {
            s = 0
        } else if l <= 0.5 {
            s = delta / (max + min)
        } else {
            s = delta / (2 - max - min)
        }

        return HSLComponents(h: h, s: s, l: l)
    }

    /**
     The inverse of `toHSLComponents()`: sRGB components for a hue/saturation/lightness
     triple, each in the 0…1 range. Returned as raw components rather than an `NSColor`
     because the contrast picker walks an entire field of these per redraw.
     */
    public static func fromHSLComponents(h: CGFloat, s: CGFloat, l: CGFloat) -> RGBComponents {
        guard s > 0 else { return RGBComponents(r: l, g: l, b: l) }

        let c = (1 - abs(2 * l - 1)) * s
        let hue = h - h.rounded(.down) // wrap into 0..<1
        let sector = hue * 6
        let x = c * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2

        let rgb: (CGFloat, CGFloat, CGFloat)
        switch sector {
        case ..<1: rgb = (c, x, 0)
        case ..<2: rgb = (x, c, 0)
        case ..<3: rgb = (0, c, x)
        case ..<4: rgb = (0, x, c)
        case ..<5: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }

        return RGBComponents(r: rgb.0 + m, g: rgb.1 + m, b: rgb.2 + m)
    }

    /// An sRGB colour for a hue/saturation/lightness triple, each in the 0…1 range.
    public static func fromHSL(h: CGFloat, s: CGFloat, l: CGFloat) -> NSColor {
        let rgb = fromHSLComponents(h: h, s: s, l: l)
        return NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }

    /**
     Get the hsl values of this color in 8-bit format.

     - returns: An NSColor as an 8-bit hsl string.
     */
    func toHSLString(style: CopyFormat = .css) -> String {
        let HSL = toHSLComponents()
        let hue = Int(round(HSL.h * 360))
        let saturation = Int(round(HSL.s * 100))
        let lightness = Int(round(HSL.l * 100))

        let formatString: NSString
        switch style {
        case .css:
            formatString = "hsl(%d, %d%%, %d%%)"
        case .design, .swiftUI:
            formatString = "hsl(%d, %d, %d)"
        case .unformatted:
            formatString = "%d, %d, %d"
        }

        let hslString = NSString(format: formatString, hue, saturation, lightness)
        return hslString as String
    }
}

// swiftlint:enable identifier_name
