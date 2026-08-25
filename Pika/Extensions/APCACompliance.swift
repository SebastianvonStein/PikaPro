import Cocoa

// swiftlint:disable identifier_name
// identifier_name is disabled because the APCA algorithm uses conventional single-letter
// variable names (c, r, g, b, y, s) from the specification that would be misleading if renamed.

extension NSColor {
    struct APCA {
        var value: CGFloat
        var level: String
    }

    func APCACompliance(with color: NSColor) -> APCA {
        let apcaValue = calculateAPCA(with: color)
        let level = getAPCALevel(value: apcaValue)

        return APCA(
            value: apcaValue,
            level: level
        )
    }

    func toAPCAcontrastValue(with color: NSColor) -> String {
        let value = abs(calculateAPCA(with: color))
        let number = NSNumber(value: value)

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2

        let s = numberFormatter.string(from: number)
        return s!
    }

    private func calculateAPCA(with color: NSColor) -> CGFloat {
        let fgRGB = toRGBAComponents()
        let bgRGB = color.toRGBAComponents()

        return NSColor.apcaLc(
            textY: NSColor.apcaScreenLuminance(red: fgRGB.r, green: fgRGB.g, blue: fgRGB.b),
            backgroundY: NSColor.apcaScreenLuminance(red: bgRGB.r, green: bgRGB.g, blue: bgRGB.b)
        )
    }

    /// APCA screen luminance (Y) from sRGB components in the 0…1 range. Exposed at
    /// component level so callers that synthesise colours numerically — the contrast
    /// picker renders a whole field of candidates — can skip the `NSColor` round trip.
    static func apcaScreenLuminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        let r = pow(red, 2.4)
        let g = pow(green, 2.4)
        let b = pow(blue, 2.4)
        var y = 0.2126729 * r + 0.7151522 * g + 0.072175 * b

        if y < 0.022 {
            y += pow(0.022 - y, 1.414)
        }
        return y
    }

    /// `pow(c, 2.4)` for each of the 256 8-bit channel values — the same lookup trick as
    /// `NSColor.linearTable`, for the same reason (see `relativeLuminance(red:green:blue:)`).
    private static let apcaTable: [CGFloat] = (0 ... 255).map { pow(CGFloat($0) / 255, 2.4) }

    /// APCA screen luminance for an 8-bit sRGB triple, via `apcaTable`.
    static func apcaScreenLuminance(red: UInt8, green: UInt8, blue: UInt8) -> CGFloat {
        var y = 0.2126729 * apcaTable[Int(red)]
            + 0.7151522 * apcaTable[Int(green)]
            + 0.072175 * apcaTable[Int(blue)]

        if y < 0.022 {
            y += pow(0.022 - y, 1.414)
        }
        return y
    }

    /// The signed APCA lightness contrast (Lc) between two screen luminances.
    static func apcaLc(textY yfg: CGFloat, backgroundY ybg: CGFloat) -> CGFloat {
        var c = 1.14

        if ybg > yfg {
            c *= pow(ybg, 0.56) - pow(yfg, 0.57)
        } else {
            c *= pow(ybg, 0.65) - pow(yfg, 0.62)
        }

        if abs(c) < 0.1 {
            return 0
        } else if c > 0 {
            c -= 0.027
        } else {
            c += 0.027
        }

        return c * 100
    }

    private func getAPCALevel(value: CGFloat) -> String {
        let absValue = abs(value)

        switch absValue {
        case 0 ..< 15: return "Fail"
        case 15 ..< 30: return "AA"
        case 30 ..< 45: return "AAA"
        case 45 ..< 60: return "AAA+"
        case 60...: return "Super"
        default: return "Unknown"
        }
    }

    func toAPCACompliance(with color: NSColor) -> (NSColor.APCA) {
        APCACompliance(with: color)
    }
}

// swiftlint:enable identifier_name
