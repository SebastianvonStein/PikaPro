@testable import Pika
import XCTest

final class ContrastGamutTests: XCTestCase {
    private let white = NSColor(r: 1, g: 1, b: 1)
    private let black = NSColor(r: 0, g: 0, b: 0)

    // MARK: - Targets

    func test_wcagTargets_matchTheirStandardThresholds() {
        XCTAssertEqual(ComplianceTarget.wcagAALarge.threshold, 3.0)
        XCTAssertEqual(ComplianceTarget.wcagAANormal.threshold, 4.5)
        XCTAssertEqual(ComplianceTarget.wcagAAALarge.threshold, 4.5)
        XCTAssertEqual(ComplianceTarget.wcagAAANormal.threshold, 7.0)
    }

    func test_targetsForStandard_areFilteredByStandard() {
        XCTAssertEqual(ComplianceTarget.targets(for: .wcag).count, 4)
        XCTAssertEqual(ComplianceTarget.targets(for: .apca).count, 4)
        XCTAssertEqual(ComplianceTarget.targets(for: .both), ComplianceTarget.allCases)
        XCTAssertTrue(ComplianceTarget.targets(for: .wcag).allSatisfy { $0.standard == .wcag })
        XCTAssertTrue(ComplianceTarget.targets(for: .apca).allSatisfy { $0.standard == .apca })
    }

    func test_defaultTarget_belongsToItsStandard() {
        for standard in [ContrastStandard.wcag, .apca, .both] {
            let target = ComplianceTarget.defaultTarget(for: standard)
            XCTAssertTrue(ComplianceTarget.targets(for: standard).contains(target))
        }
    }

    // MARK: - Pass / fail

    func test_whiteOnBlack_passesEveryTarget() {
        for target in ComplianceTarget.allCases {
            XCTAssertTrue(
                target.passes(foreground: white, background: black),
                "white on black should clear \(target.label)"
            )
        }
    }

    func test_sameColor_failsEveryTarget() {
        let gray = NSColor(r: 128, g: 128, b: 128)
        for target in ComplianceTarget.allCases {
            XCTAssertFalse(
                target.passes(foreground: gray, background: gray),
                "a colour on itself should fail \(target.label)"
            )
        }
    }

    func test_target_agreesWithTheFootersWCAGCompliance() {
        // rgb(120,120,120) on black is ~4.76:1 — over AA normal, under AAA normal.
        let foreground = NSColor(r: 120, g: 120, b: 120)
        let wcag = foreground.toWCAGCompliance(with: black)

        XCTAssertEqual(ComplianceTarget.wcagAALarge.passes(foreground: foreground, background: black), wcag.ratio30)
        XCTAssertEqual(ComplianceTarget.wcagAANormal.passes(foreground: foreground, background: black), wcag.ratio45)
        XCTAssertEqual(ComplianceTarget.wcagAAANormal.passes(foreground: foreground, background: black), wcag.ratio70)
    }

    func test_target_agreesWithTheFootersAPCACompliance() {
        let foreground = NSColor(r: 90, g: 90, b: 90)
        let background = NSColor(r: 240, g: 240, b: 240)
        let lc = abs(foreground.toAPCACompliance(with: background).value)

        XCTAssertEqual(
            ComplianceTarget.apcaHeadline.passes(foreground: foreground, background: background),
            lc >= 45
        )
        XCTAssertEqual(
            ComplianceTarget.apcaBody.passes(foreground: foreground, background: background),
            lc >= 75
        )
    }

    // MARK: - ComplianceTest

    func test_complianceTest_scoreMatchesTheContrastRatio() {
        let test = ComplianceTest(target: .wcagAANormal, background: black)
        let rgb = white.toRGBAComponents(in: .sRGB)
        XCTAssertEqual(
            test.score(red: rgb.r, green: rgb.g, blue: rgb.b),
            white.contrastRatio(with: black),
            accuracy: 0.0001
        )
    }

    func test_complianceTest_scoreMatchesTheAPCAValue() {
        let background = NSColor(r: 30, g: 30, b: 30)
        let foreground = NSColor(r: 200, g: 180, b: 40)
        let test = ComplianceTest(target: .apcaTitle, background: background)
        let rgb = foreground.toRGBAComponents(in: .sRGB)
        XCTAssertEqual(
            test.score(red: rgb.r, green: rgb.g, blue: rgb.b),
            abs(foreground.toAPCACompliance(with: background).value),
            accuracy: 0.0001
        )
    }

    func test_complianceTest_backgroundKeyTracksTheBackground() {
        XCTAssertEqual(ComplianceTest(target: .wcagAANormal, background: black).backgroundKey, black.toHexString())
        XCTAssertNotEqual(
            ComplianceTest(target: .wcagAANormal, background: black).backgroundKey,
            ComplianceTest(target: .wcagAANormal, background: white).backgroundKey
        )
    }

    // MARK: - Field geometry

    func test_lightnessAndPosition_areInverses() {
        for step in 0 ... 10 {
            let value = CGFloat(step) / 10
            XCTAssertEqual(
                ContrastGamut.position(forLightness: ContrastGamut.lightness(atY: value)),
                value,
                accuracy: 0.0001
            )
        }
    }

    func test_fieldTopIsWhite_andBottomIsBlack() {
        XCTAssertEqual(ContrastGamut.lightness(atY: 0), 1)
        XCTAssertEqual(ContrastGamut.lightness(atY: 1), 0)
    }

    // MARK: - HSL round trip

    func test_hslRoundTrip_returnsTheOriginalComponents() {
        for hue in stride(from: 0.0 as CGFloat, to: 1.0, by: 0.1) {
            let color = NSColor.fromHSL(h: hue, s: 0.8, l: 0.45)
            let hsl = color.toHSLComponents()
            XCTAssertEqual(hsl.h, hue, accuracy: 0.001)
            XCTAssertEqual(hsl.s, 0.8, accuracy: 0.001)
            XCTAssertEqual(hsl.l, 0.45, accuracy: 0.001)
        }
    }

    func test_zeroSaturation_isGrey() {
        let rgb = NSColor.fromHSLComponents(h: 0.3, s: 0, l: 0.6)
        XCTAssertEqual(rgb.r, 0.6, accuracy: 0.0001)
        XCTAssertEqual(rgb.g, 0.6, accuracy: 0.0001)
        XCTAssertEqual(rgb.b, 0.6, accuracy: 0.0001)
    }

    // MARK: - Rendering

    func test_fieldImage_isRenderedAtTheRequestedPointSize() {
        let size = CGSize(width: 120, height: 40)
        let image = ContrastGamut.fieldImage(
            size: size,
            scale: 2,
            saturation: 1,
            test: ComplianceTest(target: .wcagAANormal, background: black),
            scrim: (0.1, 0.1, 0.1),
            hatched: true
        )
        XCTAssertEqual(image?.size, size)
    }

    // MARK: - Lookup tables

    func test_lookupLuminance_matchesTheExactComputation() {
        for value in 0 ... 255 {
            let component = CGFloat(value) / 255
            XCTAssertEqual(
                NSColor.relativeLuminance(red: UInt8(value), green: UInt8(value), blue: UInt8(value)),
                NSColor.relativeLuminance(red: component, green: component, blue: component),
                accuracy: 1e-12,
                "grey \(value)"
            )
            XCTAssertEqual(
                NSColor.apcaScreenLuminance(red: UInt8(value), green: UInt8(value), blue: UInt8(value)),
                NSColor.apcaScreenLuminance(red: component, green: component, blue: component),
                accuracy: 1e-12,
                "grey \(value)"
            )
        }
    }

    func test_lookupCompliance_agreesWithTheExactTest() {
        // The renderer quantises before testing; on quantised input the two paths must
        // return the same verdict, or the mask and the click test could disagree.
        for target in ComplianceTarget.allCases {
            let test = ComplianceTest(target: target, background: NSColor(hex: "#3355AA"))
            for red in stride(from: 0, through: 255, by: 17) {
                for green in stride(from: 0, through: 255, by: 51) {
                    for blue in stride(from: 0, through: 255, by: 51) {
                        XCTAssertEqual(
                            test.passes(red: UInt8(red), green: UInt8(green), blue: UInt8(blue)),
                            test.passes(
                                red: CGFloat(red) / 255,
                                green: CGFloat(green) / 255,
                                blue: CGFloat(blue) / 255
                            ),
                            "\(target.label) at rgb(\(red), \(green), \(blue))"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Sample budgets

    func test_previewQuality_staysWithinItsSampleBudget() {
        for size in [CGSize(width: 440, height: 110), CGSize(width: 1600, height: 300)] {
            let preview = ContrastGamut.pixelSize(for: size, scale: 2, quality: .preview)
            XCTAssertLessThanOrEqual(
                preview.width * preview.height,
                ContrastGamut.Quality.preview.maximumSamples
            )
        }
    }

    func test_previewQuality_spendsItsBudgetOnRows() {
        // The pass/fail edge is near-horizontal, so a shrunk pass keeps a larger share of
        // its rows than of its columns — that's what stops the boundary stair-stepping.
        let size = CGSize(width: 440, height: 110)
        let full = ContrastGamut.pixelSize(for: size, scale: 2, quality: .full)
        let preview = ContrastGamut.pixelSize(for: size, scale: 2, quality: .preview)

        let rowRatio = CGFloat(preview.height) / CGFloat(full.height)
        let columnRatio = CGFloat(preview.width) / CGFloat(full.width)
        XCTAssertGreaterThan(rowRatio, columnRatio)
    }

    func test_previewQuality_neverOversamplesASmallField() {
        // Biasing towards rows must not invent more rows than the field has pixels.
        let size = CGSize(width: 600, height: 12)
        let full = ContrastGamut.pixelSize(for: size, scale: 2, quality: .full)
        let preview = ContrastGamut.pixelSize(for: size, scale: 2, quality: .preview)
        XCTAssertLessThanOrEqual(preview.height, full.height)
        XCTAssertLessThanOrEqual(preview.width, full.width)
    }

    func test_fullQuality_isFinerThanPreview() {
        let size = CGSize(width: 440, height: 110)
        let preview = ContrastGamut.pixelSize(for: size, scale: 2, quality: .preview)
        let full = ContrastGamut.pixelSize(for: size, scale: 2, quality: .full)
        XCTAssertGreaterThan(full.width * full.height, preview.width * preview.height)
    }

    func test_smallFieldIsNotUpsampled() {
        // A field already under budget renders at its natural resolution, not padded up.
        let size = CGSize(width: 40, height: 20)
        let preview = ContrastGamut.pixelSize(for: size, scale: 2, quality: .preview)
        XCTAssertEqual(preview.width, 80)
        XCTAssertEqual(preview.height, 40)
    }

    func test_fieldImage_isEmptyForAnEmptySize() {
        XCTAssertNil(ContrastGamut.fieldImage(
            size: .zero, scale: 2, saturation: 1, test: nil, scrim: (0, 0, 0), hatched: false
        ))
    }
}
