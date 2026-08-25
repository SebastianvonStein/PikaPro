import Cocoa

extension NSColor {
    func clip<T: Comparable>(_ val: T, _ minimum: T, _ maximum: T) -> T {
        max(min(val, maximum), minimum)
    }

    var luminance: CGFloat {
        let rgba = toRGBAComponents(in: .extendedSRGB)
        return NSColor.relativeLuminance(red: rgba.r, green: rgba.g, blue: rgba.b)
    }

    /// WCAG relative luminance straight from sRGB components. The contrast picker builds
    /// candidate colours numerically by the thousand, so it needs this without paying for
    /// an `NSColor` (and a colour-space conversion) per sample.
    static func relativeLuminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        func lumHelper(component: CGFloat) -> CGFloat {
            (component < 0.03928) ? (component / 12.92) : pow((component + 0.055) / 1.055, 2.4)
        }

        let result = 0.2126 * lumHelper(component: red)
            + 0.7152 * lumHelper(component: green)
            + 0.0722 * lumHelper(component: blue)
        return max(.zero, result)
    }

    /// Linearised sRGB for each of the 256 8-bit channel values. The picker's field is
    /// quantised to 8 bits on its way into the bitmap anyway, so looking the transfer
    /// function up here is exact for what's drawn — and spares three `pow` calls per
    /// pixel, which is the bulk of the field's render cost.
    private static let linearTable: [CGFloat] = (0 ... 255).map { value in
        let component = CGFloat(value) / 255
        return (component < 0.03928) ? (component / 12.92) : pow((component + 0.055) / 1.055, 2.4)
    }

    /// WCAG relative luminance for an 8-bit sRGB triple, via `linearTable`.
    static func relativeLuminance(red: UInt8, green: UInt8, blue: UInt8) -> CGFloat {
        let result = 0.2126 * linearTable[Int(red)]
            + 0.7152 * linearTable[Int(green)]
            + 0.0722 * linearTable[Int(blue)]
        return max(.zero, result)
    }

    /// The WCAG contrast ratio between two already-computed relative luminances.
    static func contrastRatio(luminance lum1: CGFloat, with lum2: CGFloat) -> CGFloat {
        lum1 < lum2 ? (lum2 + 0.05) / (lum1 + 0.05) : (lum1 + 0.05) / (lum2 + 0.05)
    }

    func contrastRatio(with color: NSColor) -> CGFloat {
        NSColor.contrastRatio(luminance: luminance, with: color.luminance)
    }

    func toContrastRatioString(with color: NSColor) -> String {
        Double(round(100 * contrastRatio(with: color)) / 100).description as String
    }

    func toLocalizedContrastRatioString(with color: NSColor, locale: Locale = .current) -> String {
        let value = round(100 * contrastRatio(with: color)) / 100
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = locale
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 1
        numberFormatter.maximumFractionDigits = 2
        return numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
