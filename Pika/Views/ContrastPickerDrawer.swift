import Defaults
import SwiftUI

/// The contrast picker: a hue × lightness field for choosing a foreground colour, with
/// everything that fails the selected accessibility target scrimmed out against the
/// current background. Sits under the compliance footer, so the ratio the footer reports
/// and the field you are picking from are always talking about the same pair.
struct ContrastPickerDrawer: View {
    @EnvironmentObject var eyedroppers: Eyedroppers
    @ObservedObject var foreground: Eyedropper
    @ObservedObject var background: Eyedropper
    /// Dropped when the window is too narrow for the toolbar's colour/score readout.
    var showsReadout: Bool = true

    @Default(.contrastStandard) var contrastStandard
    @Default(.pickerTarget) var pickerTarget
    @Default(.pickerOverlay) var pickerOverlay
    @Default(.pickerRestrict) var pickerRestrict
    @Environment(\.colorScheme) private var colorScheme

    /// Hue and saturation are held here rather than read back from the colour on every
    /// pass: at the very top and bottom of the field (white and black) they aren't
    /// recoverable from RGB, and a round trip would silently reset the marker's column.
    @State private var hue: CGFloat = 0
    @State private var saturation: CGFloat = 1
    @State private var isEditing = false
    @State private var hovered: NSColor?

    /// The target actually in force. A saved target from the other standard would leave
    /// the menu showing a level that isn't on offer, so fall back when they disagree.
    private var target: ComplianceTarget {
        let available = ComplianceTarget.targets(for: contrastStandard)
        return available.contains(pickerTarget)
            ? pickerTarget
            : ComplianceTarget.defaultTarget(for: contrastStandard)
    }

    private var test: ComplianceTest {
        ComplianceTest(target: target, background: background.color)
    }

    /// The colour the readout describes: whatever the pointer is over, falling back to
    /// the current foreground.
    private var readoutColor: NSColor {
        hovered ?? foreground.color
    }

    var body: some View {
        AdaptiveDivider()
        VStack(spacing: 0) {
            toolbar
            AdaptiveDivider()
            HStack(spacing: 0) {
                ContrastField(
                    hue: $hue,
                    saturation: $saturation,
                    isEditing: $isEditing,
                    hovered: $hovered,
                    foreground: foreground,
                    test: test,
                    overlayEnabled: pickerOverlay,
                    restrictToCompliant: pickerOverlay && pickerRestrict,
                    onCommit: { eyedroppers.recordHistory() }
                )
                AdaptiveDivider(axis: .vertical)
                SaturationStrip(
                    hue: hue,
                    saturation: $saturation,
                    isEditing: $isEditing,
                    onChange: { applySaturation($0) },
                    onCommit: { eyedroppers.recordHistory() }
                )
                .frame(width: 22)
            }
            .frame(height: 110)
        }
        .background(
            ZStack {
                AdaptivePanelBackground()
                Color.black.opacity(colorScheme == .dark ? 0.06 : 0.02)
            }
        )
        .onAppear { syncFromColor() }
        .onChange(of: foreground.color) {
            guard !isEditing else { return }
            syncFromColor()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(ComplianceTarget.targets(for: contrastStandard), id: \.self) { option in
                    Button(action: { pickerTarget = option }) {
                        if option == target {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "accessibility")
                        .font(.system(size: 10))
                    Text(target.label)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(Color.accentColor)
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .fixedSize()
            .help(target.tooltip)

            Spacer(minLength: 4)

            if showsReadout {
                readout
            }

            toolbarToggle(
                isOn: pickerOverlay,
                systemImage: pickerOverlay ? "square.righthalf.filled" : "square",
                help: PikaText.textPickerOverlay
            ) {
                withAnimation(.easeInOut(duration: 0.15)) { pickerOverlay.toggle() }
            }

            toolbarToggle(
                isOn: pickerRestrict,
                systemImage: pickerRestrict ? "lock.fill" : "lock.open",
                help: PikaText.textPickerRestrict,
                disabled: !pickerOverlay
            ) {
                pickerRestrict.toggle()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color.black.opacity(0.05))
    }

    private var readout: some View {
        let color = readoutColor
        let passes = test.passes(foreground: color)
        // Format the score exactly as the footer does, so the two never disagree by a
        // rounding step for the same pair of colours.
        let score = target.standard == .apca
            ? "Lc \(color.toAPCAcontrastValue(with: background.color))"
            : "\(color.toLocalizedContrastRatioString(with: background.color)):1"

        return HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(color))
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )

            Text(color.toHexString())
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize()

            HStack(spacing: 2) {
                IconImage(name: passes ? "checkmark.circle.fill" : "xmark.circle", resizable: true)
                    .frame(width: 11, height: 11)
                Text(score)
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize()
            }
            .foregroundStyle(passes ? Color.primary : Color.secondary.opacity(0.6))
        }
        .help(passes ? PikaText.textColorPass : PikaText.textColorFail)
    }

    private func toolbarToggle(
        isOn: Bool,
        systemImage: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : (isOn ? Color.accentColor : Color.secondary))
        .disabled(disabled)
        .help(help)
    }

    // MARK: - Colour plumbing

    private func syncFromColor() {
        let hsl = foreground.color.toHSLComponents()
        // Grey has no meaningful hue, and pure black/white no meaningful saturation;
        // keeping the last real values leaves the marker where the user put it.
        if hsl.s > 0.001 { hue = hsl.h }
        if hsl.l > 0.001, hsl.l < 0.999 { saturation = hsl.s }
    }

    private func applySaturation(_ value: CGFloat) {
        let lightness = foreground.color.toHSLComponents().l
        foreground.set(ContrastGamut.color(hue: hue, saturation: value, lightness: lightness))
    }
}

// MARK: - Field

/// The hue × lightness plane. Colours failing the active target are scrimmed into the
/// bitmap itself, and — when restricted — refuse the pointer outright.
private struct ContrastField: View {
    @Binding var hue: CGFloat
    @Binding var saturation: CGFloat
    @Binding var isEditing: Bool
    @Binding var hovered: NSColor?
    @ObservedObject var foreground: Eyedropper
    let test: ComplianceTest
    let overlayEnabled: Bool
    let restrictToCompliant: Bool
    let onCommit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?
    @State private var size: CGSize = .zero

    /// How long the field has to sit still before the full-resolution pass runs. Short
    /// enough to feel like the picture simply sharpens, long enough that a drag never
    /// queues one up per frame.
    static let refineDelay = 150

    /// Everything the rendered bitmap depends on. Re-rendering is off the main thread and
    /// keyed on this, so an unrelated redraw doesn't repaint 40,000 pixels.
    private struct RenderKey: Equatable {
        let width: CGFloat
        let height: CGFloat
        let saturation: CGFloat
        let background: String
        let target: ComplianceTarget?
        let hatched: Bool
        let dark: Bool
    }

    private var renderKey: RenderKey {
        RenderKey(
            width: size.width.rounded(),
            height: size.height.rounded(),
            saturation: (saturation * 200).rounded() / 200,
            background: test.backgroundKey,
            target: overlayEnabled ? test.target : nil,
            hatched: restrictToCompliant,
            dark: colorScheme == .dark
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Color(nsColor: .controlBackgroundColor)
                }

                marker(in: geo.size)
            }
            .overlay(
                PointerSurface(
                    onDrag: { location in
                        isEditing = true
                        hovered = color(at: location, in: geo.size)
                        apply(at: location, in: geo.size)
                    },
                    onEnd: {
                        isEditing = false
                        onCommit()
                    },
                    onHover: { location in
                        hovered = location.map { color(at: $0, in: geo.size) }
                    },
                    cursorAt: { location in
                        restrictToCompliant && !isCompliant(at: location, in: geo.size)
                            ? NSCursor.operationNotAllowed
                            : nil
                    }
                )
            )
            .onChange(of: geo.size) { size = geo.size }
            .onAppear { size = geo.size }
        }
        .task(id: renderKey) {
            // Coarse pass first, so dragging never waits on a full-resolution render…
            await render(key: renderKey, quality: .preview)
            // …then sharpen once the inputs settle. A new key cancels this task, so the
            // full pass only ever runs for the values the pointer came to rest on.
            try? await Task.sleep(for: .milliseconds(ContrastField.refineDelay))
            guard !Task.isCancelled else { return }
            await render(key: renderKey, quality: .full)
        }
    }

    @ViewBuilder
    private func marker(in size: CGSize) -> some View {
        let hsl = foreground.color.toHSLComponents()
        // Colours off this saturation slice still deserve a marker — the hue and
        // lightness are what the field encodes, so place it by those two.
        let markerHue = hsl.s > 0.001 ? hsl.h : hue
        let point = CGPoint(
            x: markerHue * size.width,
            y: ContrastGamut.position(forLightness: hsl.l) * size.height
        )

        Circle()
            .strokeBorder(.white, lineWidth: 2)
            .background(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 3.5))
            .frame(width: 12, height: 12)
            .position(x: point.x, y: point.y)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.08), value: point)
    }

    // MARK: Interaction

    private func color(at location: CGPoint, in size: CGSize) -> NSColor {
        let x = min(max(location.x / max(size.width, 1), 0), 1)
        let y = min(max(location.y / max(size.height, 1), 0), 1)
        return ContrastGamut.color(
            hue: x,
            saturation: saturation,
            lightness: ContrastGamut.lightness(atY: y)
        )
    }

    private func isCompliant(at location: CGPoint, in size: CGSize) -> Bool {
        test.passes(foreground: color(at: location, in: size))
    }

    private func apply(at location: CGPoint, in size: CGSize) {
        let picked = color(at: location, in: size)
        // "Restrict to compliant" is a hard stop rather than a nudge: the selection
        // simply doesn't follow the pointer into the scrimmed region.
        guard !restrictToCompliant || test.passes(foreground: picked) else { return }
        hue = min(max(location.x / max(size.width, 1), 0), 1)
        foreground.set(picked)
    }

    // MARK: Rendering

    private func render(key: RenderKey, quality: ContrastGamut.Quality) async {
        guard key.width > 1, key.height > 1 else { return }
        let scrim: (r: CGFloat, g: CGFloat, b: CGFloat) = key.dark
            ? (0.09, 0.09, 0.10)
            : (0.93, 0.93, 0.94)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let test = overlayEnabled ? test : nil

        let rendered: NSImage? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: ContrastGamut.fieldImage(
                    size: CGSize(width: key.width, height: key.height),
                    scale: scale,
                    saturation: key.saturation,
                    test: test,
                    scrim: scrim,
                    hatched: key.hatched,
                    quality: quality
                ))
            }
        }

        guard !Task.isCancelled else { return }
        image = rendered
    }
}

// MARK: - Saturation

/// Vertical saturation strip beside the field, previewed at the current hue.
private struct SaturationStrip: View {
    let hue: CGFloat
    @Binding var saturation: CGFloat
    @Binding var isEditing: Bool
    let onChange: (CGFloat) -> Void
    let onCommit: () -> Void

    private var gradient: Gradient {
        Gradient(colors: stride(from: 0, through: 1, by: 0.2).reversed().map { value in
            Color(ContrastGamut.color(hue: hue, saturation: value, lightness: 0.5))
        })
    }

    var body: some View {
        GeometryReader { geo in
            LinearGradient(gradient: gradient, startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white)
                        .frame(width: 14, height: 3)
                        .overlay(Capsule().strokeBorder(.black.opacity(0.4), lineWidth: 1))
                        .offset(y: (1 - saturation) * max(geo.size.height - 3, 0))
                        .allowsHitTesting(false)
                }
                .overlay(
                    PointerSurface(
                        onDrag: { location in
                            isEditing = true
                            let position = min(max(location.y / max(geo.size.height, 1), 0), 1)
                            saturation = 1 - position
                            onChange(saturation)
                        },
                        onEnd: {
                            isEditing = false
                            onCommit()
                        }
                    )
                )
        }
        .help(PikaText.textPickerSaturation)
    }
}

// MARK: - Pointer handling

/// Mouse handling for the picker's two draggable surfaces.
///
/// This has to be AppKit. Pika's window is movable by its background, and AppKit decides
/// whether a mouse-down starts a window drag — by asking the hit view for
/// `mouseDownCanMoveWindow` — before SwiftUI ever sees the event. A SwiftUI `DragGesture`
/// on the field therefore just drags the whole window; an `NSView` that answers `false`
/// is what actually claims the drag. Handling hover here too keeps the readout and the
/// blocked-pointer cursor on the same event stream as the drag.
private struct PointerSurface: NSViewRepresentable {
    /// Called on mouse-down and for every drag position after it.
    var onDrag: (CGPoint) -> Void
    var onEnd: () -> Void
    var onHover: ((CGPoint?) -> Void)?
    /// The cursor for a position, or `nil` for the ordinary arrow.
    var cursorAt: ((CGPoint) -> NSCursor?)?

    func makeNSView(context _: Context) -> SurfaceView {
        SurfaceView()
    }

    func updateNSView(_ view: SurfaceView, context _: Context) {
        view.onDrag = onDrag
        view.onEnd = onEnd
        view.onHover = onHover
        view.cursorAt = cursorAt
    }

    final class SurfaceView: NSView {
        var onDrag: ((CGPoint) -> Void)?
        var onEnd: (() -> Void)?
        var onHover: ((CGPoint?) -> Void)?
        var cursorAt: ((CGPoint) -> NSCursor?)?

        private var trackingArea: NSTrackingArea?

        /// Match SwiftUI's top-left origin so callers can use one set of coordinates.
        override var isFlipped: Bool { true }

        /// The whole point: keep `isMovableByWindowBackground` from stealing the drag.
        override var mouseDownCanMoveWindow: Bool { false }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            trackingArea = area
        }

        private func location(of event: NSEvent) -> CGPoint {
            convert(event.locationInWindow, from: nil)
        }

        override func mouseDown(with event: NSEvent) {
            onDrag?(location(of: event))
        }

        override func mouseDragged(with event: NSEvent) {
            let point = location(of: event)
            onHover?(point)
            onDrag?(point)
            applyCursor(at: point)
        }

        override func mouseUp(with _: NSEvent) {
            onEnd?()
        }

        override func mouseMoved(with event: NSEvent) {
            let point = location(of: event)
            onHover?(point)
            applyCursor(at: point)
        }

        override func mouseExited(with _: NSEvent) {
            onHover?(nil)
            NSCursor.arrow.set()
        }

        /// Set rather than push/pop: the blocked region changes as the pointer moves
        /// across the field, and a push/pop pair per crossing is far easier to unbalance.
        private func applyCursor(at point: CGPoint) {
            guard let cursorAt = cursorAt else { return }
            (cursorAt(point) ?? .arrow).set()
        }
    }
}

struct ContrastPickerDrawer_Previews: PreviewProvider {
    static var previews: some View {
        ContrastPickerDrawer(
            foreground: Eyedropper(type: .foreground, color: PikaConstants.initialColors.randomElement()!),
            background: Eyedropper(type: .background, color: NSColor.black)
        )
        .environmentObject(Eyedroppers())
        .frame(width: 420)
    }
}
