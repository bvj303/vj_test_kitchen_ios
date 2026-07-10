#!/usr/bin/env swift
import SwiftUI
import AppKit

// Renders every app-icon look (classic Spatch plus his stunt alter egos —
// pizza surf, rocket ride, balloon ride) to the 1024x1024 light/dark PNGs in
// their .appiconset folders, plus the 256px Settings-picker previews, since
// there's no image-generation tool in this pipeline — all vector SwiftUI art
// rasterized via ImageRenderer.
//
// Usage: swift scripts/render_app_icon.swift VJTestKitchen/Resources/Assets.xcassets
// Re-run after any art tweak; the icon set / imageset names must match
// AppIconOption and ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES in project.yml.
//
// SpatchFigure below is a faithful static port of SpatchCharacterView's
// design-space geometry (112-unit-wide canvas, same part offsets/sizes/shapes)
// so the icon actually looks like the in-app Spatch — keep them in sync if his
// face ever changes. The handle length is the one deliberate departure
// (shortened for icon legibility; full length reads as a distant stick figure
// at home-screen sizes).

// MARK: - Palette (SpatchCharacterView's SpatchPalette hex values)

struct IconPalette {
    let teal: Color
    let tealDeep: Color
    let woodLight: Color
    let woodDark: Color
    let blushPink: Color
    let wireGray: Color
    let spoonGray: Color
    let saffron: Color

    static let light = IconPalette(
        teal: Color(hex: 0x4FB0A5), tealDeep: Color(hex: 0x3E958B),
        woodLight: Color(hex: 0xC08A52), woodDark: Color(hex: 0x9C6C3C),
        blushPink: Color(hex: 0xF08C8C),
        wireGray: Color(hex: 0x8E9296), spoonGray: Color(hex: 0xB4B8BC),
        saffron: Color(red: 0.91, green: 0.63, blue: 0.23)
    )
    static let dark = IconPalette(
        teal: Color(hex: 0x53BCB0), tealDeep: Color(hex: 0x429D92),
        woodLight: Color(hex: 0xB37F4A), woodDark: Color(hex: 0x8F6236),
        blushPink: Color(hex: 0xE98A8A),
        wireGray: Color(hex: 0xA6AAAE), spoonGray: Color(hex: 0xC2C6CA),
        saffron: Color(red: 0.94, green: 0.70, blue: 0.33)
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Moods (the SpatchMood parameters the icons use)

enum FigureMood {
    case happy      // open grin + tongue
    case laughing   // bigger open grin
    case surprised  // round "o" mouth, raised brows

    var eyebrowTilt: CGFloat {
        self == .surprised ? 0.7 : 0
    }
}

// MARK: - Spatch himself

/// SpatchCharacterView's `character(unit:)` assembly, statically. Every part
/// offset/size below is copied from the character view in design units and
/// multiplied by `unit`.
struct SpatchFigure: View {
    var mood: FigureMood = .happy
    var palette: IconPalette
    /// Design-unit height of the wooden handle (the character view uses 118;
    /// icons shorten it so the face stays big at home-screen sizes).
    var handleUnits: CGFloat = 72
    var unit: CGFloat

    /// Total design-space size at this handle length.
    var size: CGSize {
        CGSize(width: 112 * unit, height: (92 + handleUnits) * unit)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            arm
            spoon
            handle
            head
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var head: some View {
        ZStack(alignment: .topLeading) {
            SpatulaHeadShape()
                .fill(LinearGradient(colors: [palette.teal, palette.tealDeep], startPoint: .top, endPoint: .bottom))
            Ellipse()
                .fill(Color.white.opacity(0.14))
                .frame(width: 34 * unit, height: 14 * unit)
                .rotationEffect(.degrees(-18))
                .offset(x: 10 * unit, y: 8 * unit)

            eyebrow
                .rotationEffect(.degrees(Double(-mood.eyebrowTilt) * 14))
                .offset(x: 21 * unit, y: 17 * unit)
            eyebrow
                .rotationEffect(.degrees(Double(mood.eyebrowTilt) * 14))
                .offset(x: 49 * unit, y: 18 * unit)

            eye.offset(x: 17 * unit, y: 29 * unit)
            eye.offset(x: 45 * unit, y: 29 * unit)

            blushDot.offset(x: 13 * unit, y: 59 * unit)
            blushDot.offset(x: 63 * unit, y: 59 * unit)

            mouth
        }
        .frame(width: 88 * unit, height: 94 * unit, alignment: .topLeading)
        .offset(x: 2 * unit, y: 2 * unit)
    }

    private var eyebrow: some View {
        BrowShape()
            .stroke(Color.black.opacity(0.7), style: StrokeStyle(lineWidth: 2.4 * unit, lineCap: .round))
            .frame(width: 18 * unit, height: 6 * unit)
    }

    private var eye: some View {
        let size = 26 * unit
        return ZStack {
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1.6 * unit))
                .shadow(color: .black.opacity(0.18), radius: 1.5 * unit, y: 1 * unit)
            ZStack {
                Circle().fill(Color.black).frame(width: size * 0.46, height: size * 0.46)
                Circle().fill(Color.white.opacity(0.9))
                    .frame(width: size * 0.14, height: size * 0.14)
                    .offset(x: -size * 0.1, y: -size * 0.1)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .laughing:
            openSmile(width: 38, height: 21).offset(x: 25 * unit, y: 58 * unit)
        case .surprised:
            Circle()
                .fill(Color.black.opacity(0.82))
                .frame(width: 12 * unit, height: 12 * unit)
                .offset(x: 38 * unit, y: 61 * unit)
        case .happy:
            openSmile(width: 30, height: 16).offset(x: 29 * unit, y: 60 * unit)
        }
    }

    private func openSmile(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            OpenSmileShape().fill(Color.black.opacity(0.85))
            Ellipse()
                .fill(palette.blushPink)
                .frame(width: width * 0.62 * unit, height: height * 0.5 * unit)
                .offset(y: height * 0.16 * unit)
        }
        .frame(width: width * unit, height: height * unit)
        .clipShape(OpenSmileShape())
    }

    private var blushDot: some View {
        Ellipse()
            .fill(palette.blushPink.opacity(0.65))
            .frame(width: 12 * unit, height: 7 * unit)
    }

    private var handle: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8 * unit, style: .continuous)
                .fill(LinearGradient(colors: [palette.woodLight, palette.woodDark], startPoint: .top, endPoint: .bottom))
            Circle()
                .fill(Color.black.opacity(0.28))
                .frame(width: 8 * unit, height: 8 * unit)
                .padding(.bottom, 10 * unit)
        }
        .frame(width: 17 * unit, height: handleUnits * unit)
        .offset(x: 37.5 * unit, y: 92 * unit)
    }

    private var arm: some View {
        ArmPath()
            .stroke(palette.wireGray, style: StrokeStyle(lineWidth: 3.2 * unit, lineCap: .round))
            .frame(width: 52 * unit, height: 44 * unit)
            .offset(x: 50 * unit, y: 74 * unit)
    }

    private var spoon: some View {
        VStack(spacing: -2 * unit) {
            ZStack {
                Ellipse()
                    .fill(LinearGradient(colors: [palette.spoonGray, palette.wireGray], startPoint: .topLeading, endPoint: .bottomTrailing))
                Ellipse()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 5 * unit, height: 4 * unit)
                    .offset(x: -2.5 * unit, y: -4 * unit)
            }
            .frame(width: 14 * unit, height: 17 * unit)
            Capsule()
                .fill(palette.wireGray)
                .frame(width: 3.2 * unit, height: 16 * unit)
        }
        .frame(width: 14 * unit, alignment: .center)
        .offset(x: 89 * unit, y: 52 * unit)
    }
}

// MARK: - Shapes (verbatim ports from SpatchCharacterView)

struct SpatulaHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let topLeading = CGPoint(x: rect.minX, y: rect.minY)
        let topTrailing = CGPoint(x: rect.minX + w, y: rect.minY + h * 0.13)
        let bottomTrailing = CGPoint(x: rect.minX + w * 0.84, y: rect.maxY)
        let bottomLeading = CGPoint(x: rect.minX + w * 0.16, y: rect.maxY)

        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addArc(tangent1End: bottomLeading, tangent2End: topLeading, radius: w * 0.11)
        path.addArc(tangent1End: topLeading, tangent2End: topTrailing, radius: w * 0.30)
        path.addArc(tangent1End: topTrailing, tangent2End: bottomTrailing, radius: w * 0.24)
        path.addArc(tangent1End: bottomTrailing, tangent2End: bottomLeading, radius: w * 0.11)
        path.closeSubpath()
        return path
    }
}

struct BrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.4)
        )
        return path
    }
}

struct OpenSmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 1.9)
        )
        path.closeSubpath()
        return path
    }
}

struct ArmPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY * 0.86))
        path.addCurve(
            to: CGPoint(x: rect.maxX * 0.77, y: rect.maxY * 0.55),
            control1: CGPoint(x: rect.maxX * 0.5, y: rect.maxY * 1.05),
            control2: CGPoint(x: rect.maxX * 0.82, y: rect.maxY * 0.85)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX * 0.85, y: rect.minY + rect.height * 0.14),
            control: CGPoint(x: rect.maxX * 0.72, y: rect.maxY * 0.28)
        )
        return path
    }
}

/// A four-point star sparkle, like the app's "Suggested for You" ✦ motif.
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let inner = r * 0.22
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + inner, y: c.y - inner))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + inner, y: c.y + inner))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - inner, y: c.y + inner))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - inner, y: c.y - inner))
        p.closeSubpath()
        return p
    }
}

// MARK: - Props (ports of the stunt rigs in SpatchStuntStageView)

/// The pepperoni pizza he surfs — flattened perspective disc: crust, cheese,
/// pepperoni scatter.
struct PizzaProp: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let pepperoni = Color(red: 0.76, green: 0.25, blue: 0.20)
            ZStack {
                Ellipse()
                    .fill(Color(red: 0.85, green: 0.64, blue: 0.36))
                    .frame(width: w, height: h)
                Ellipse()
                    .fill(Color(red: 0.95, green: 0.77, blue: 0.36))
                    .frame(width: w * 0.86, height: h * 0.78)
                pepperoniDot(size: w * 0.09, x: -w * 0.28, y: -h * 0.08, color: pepperoni)
                pepperoniDot(size: w * 0.08, x: -w * 0.05, y: h * 0.16, color: pepperoni)
                pepperoniDot(size: w * 0.09, x: w * 0.22, y: -h * 0.12, color: pepperoni)
                pepperoniDot(size: w * 0.07, x: w * 0.32, y: h * 0.14, color: pepperoni)
                pepperoniDot(size: w * 0.07, x: -w * 0.12, y: -h * 0.24, color: pepperoni)
            }
            .frame(width: w, height: h)
        }
    }

    private func pepperoniDot(size: CGFloat, x: CGFloat, y: CGFloat, color: Color) -> some View {
        Ellipse()
            .fill(color)
            .frame(width: size, height: size * 0.72)
            .offset(x: x, y: y)
    }
}

/// Three party balloons on strings converging to where Spatch holds on.
struct BalloonBunchProp: View {
    var palette: IconPalette

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack(alignment: .topLeading) {
                BalloonStringsShape()
                    .stroke(Color.white.opacity(0.7), lineWidth: h * 0.014)
                balloon(color: palette.blushPink, w: w, h: h, centerX: 0.24, centerY: 0.30)
                balloon(color: palette.saffron, w: w, h: h, centerX: 0.52, centerY: 0.22)
                balloon(color: palette.teal, w: w, h: h, centerX: 0.78, centerY: 0.32)
            }
        }
    }

    private func balloon(color: Color, w: CGFloat, h: CGFloat, centerX: CGFloat, centerY: CGFloat) -> some View {
        let width: CGFloat = w * 0.30
        let height: CGFloat = h * 0.44
        let sheen = Ellipse()
            .fill(Color.white.opacity(0.35))
            .frame(width: width * 0.28, height: height * 0.18)
            .offset(x: -width * 0.2, y: -height * 0.26)
        return Ellipse()
            .fill(color)
            .overlay(sheen)
            .frame(width: width, height: height)
            .offset(x: w * centerX - width / 2, y: h * centerY - height / 2)
    }
}

struct BalloonStringsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let anchor = CGPoint(x: rect.midX, y: rect.maxY)
        for x in [rect.width * 0.24, rect.width * 0.52, rect.width * 0.78] {
            path.move(to: CGPoint(x: x, y: rect.height * 0.50))
            path.addQuadCurve(
                to: anchor,
                control: CGPoint(x: (x + rect.midX) / 2, y: rect.height * 0.82)
            )
        }
        return path
    }
}

/// The rocket-ride thrust flame off the handle tip, with smoke puffs. Puffs
/// are gray (not the stunt view's translucent white) so they survive the
/// icon's cream background.
struct RocketFlameProp: View {
    var puffGray: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                FlameShape()
                    .fill(Color.orange)
                    .overlay(
                        FlameShape()
                            .fill(Color.yellow.opacity(0.9))
                            .frame(width: w * 0.34, height: h * 0.62)
                            .offset(y: -h * 0.16)
                    )
                    .frame(width: w * 0.62, height: h)
                Circle()
                    .fill(puffGray.opacity(0.75))
                    .frame(width: w * 0.40, height: w * 0.40)
                    .offset(x: -w * 0.46, y: h * 0.24)
                Circle()
                    .fill(puffGray.opacity(0.5))
                    .frame(width: w * 0.28, height: w * 0.28)
                    .offset(x: w * 0.44, y: h * 0.32)
            }
            .frame(width: w, height: h)
        }
    }
}

/// A teardrop thrust flame: round shoulders up top, tapering to a tip.
struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.28),
            control: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.82)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.28),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.24)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.minY + rect.height * 0.82)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Icon compositions

enum IconLook: String, CaseIterable {
    case classic
    case pizza
    case rocket
    case balloon

    var appIconSetName: String {
        switch self {
        case .classic: "AppIcon"
        case .pizza: "AppIconPizza"
        case .rocket: "AppIconRocket"
        case .balloon: "AppIconBalloon"
        }
    }

    var previewImageSetName: String {
        switch self {
        case .classic: "IconPreviewClassic"
        case .pizza: "IconPreviewPizza"
        case .rocket: "IconPreviewRocket"
        case .balloon: "IconPreviewBalloon"
        }
    }
}

struct SpatchIconArt: View {
    var look: IconLook
    var dark: Bool

    private var palette: IconPalette { dark ? .dark : .light }

    var body: some View {
        ZStack {
            background
            scene
        }
        .frame(width: 1024, height: 1024)
    }

    // Warm kitchen cream (light) / deep slate-teal (dark), with a soft halo
    // so Spatch pops off the background, and the app's saffron ✦ sparkles.
    // The dark halo is teal-tinted — a white one goes muddy gray on the slate
    // background, while a teal glow reads as Spatch lighting his own corner.
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.11, green: 0.175, blue: 0.175), Color(red: 0.055, green: 0.095, blue: 0.10)]
                    : [Color(red: 0.984, green: 0.953, blue: 0.898), Color(red: 0.945, green: 0.871, blue: 0.755)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: dark
                    ? [palette.teal.opacity(0.22), .clear]
                    : [Color.white.opacity(0.75), Color.white.opacity(0)],
                center: .init(x: 0.5, y: 0.42),
                startRadius: 40, endRadius: 460
            )
            sparkles
        }
    }

    private var sparkles: some View {
        let saffron = palette.saffron
        return ZStack {
            SparkleShape().fill(saffron.opacity(0.95)).frame(width: 92, height: 92).offset(x: -330, y: -300)
            SparkleShape().fill(saffron.opacity(0.75)).frame(width: 56, height: 56).offset(x: -252, y: -180)
            SparkleShape().fill(saffron.opacity(0.9)).frame(width: 74, height: 74).offset(x: 330, y: -238)
            SparkleShape().fill(saffron.opacity(0.7)).frame(width: 52, height: 52).offset(x: -318, y: 300)
        }
    }

    @ViewBuilder
    private var scene: some View {
        switch look {
        case .classic: classicScene
        case .pizza: pizzaScene
        case .rocket: rocketScene
        case .balloon: balloonScene
        }
    }

    private func figure(mood: FigureMood, unit: CGFloat, handleUnits: CGFloat = 72) -> SpatchFigure {
        SpatchFigure(mood: mood, palette: palette, handleUnits: handleUnits, unit: unit)
    }

    private var classicScene: some View {
        figure(mood: .happy, unit: 5.1) // 571 x 836
            .rotationEffect(.degrees(-6))
            .offset(y: 6)
            .modifier(DropShadow(dark: dark))
    }

    private var pizzaScene: some View {
        // He carves across the lower half; the pie tips into the turn with him.
        ZStack {
            VStack(spacing: -34) {
                figure(mood: .laughing, unit: 4.1) // 459 x 672
                PizzaProp()
                    .frame(width: 630, height: 190)
            }
            .rotationEffect(.degrees(-9))
            .offset(x: -14, y: 30)
            .modifier(DropShadow(dark: dark))
            motionStreaks
        }
    }

    /// A couple of teal motion streaks trailing the surf.
    private var motionStreaks: some View {
        VStack(alignment: .trailing, spacing: 56) {
            Capsule().fill(palette.teal.opacity(0.45)).frame(width: 200, height: 26)
            Capsule().fill(palette.teal.opacity(0.30)).frame(width: 130, height: 22)
        }
        .offset(x: -330, y: 240)
    }

    private var rocketScene: some View {
        // Straight up under full thrust, flame right off the handle tip. The
        // handle's center sits at 46 design units, left of the 112-wide
        // figure frame's center — nudge the flame to line up with the wood,
        // not the frame.
        let unit: CGFloat = 4.5
        return VStack(spacing: -16) {
            figure(mood: .surprised, unit: unit) // 504 x 738
            RocketFlameProp(puffGray: palette.spoonGray)
                .frame(width: 190, height: 230)
                .offset(x: (46 - 56) * unit)
        }
        .rotationEffect(.degrees(4))
        .offset(y: -26)
        .modifier(DropShadow(dark: dark))
    }

    private var balloonScene: some View {
        // The balloon bunch lifts him up and off the top, strings meeting his
        // held-up spoon side.
        VStack(spacing: -12) {
            BalloonBunchProp(palette: palette)
                .frame(width: 620, height: 430)
            figure(mood: .happy, unit: 3.7, handleUnits: 66) // 414 x 585
        }
        .offset(y: -8)
        .modifier(DropShadow(dark: dark))
    }
}

struct DropShadow: ViewModifier {
    var dark: Bool
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(dark ? 0.45 : 0.22), radius: 26, y: 18)
    }
}

// MARK: - Rendering

@MainActor
func renderPNG(look: IconLook, dark: Bool, scale: CGFloat, to path: String) {
    let view = SpatchIconArt(look: look, dark: dark)
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: 1024, height: 1024)
    renderer.scale = scale
    guard let cgImage = renderer.cgImage else {
        fatalError("Failed to render \(path)")
    }
    // App icons must not carry an alpha channel (App Store Connect rejects
    // one at submission) — flatten onto an opaque RGB bitmap before encoding,
    // even though the art itself is already fully opaque edge-to-edge.
    let width = cgImage.width, height = cgImage.height
    guard let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("Failed to create flattening context for \(path)")
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let flattened = context.makeImage() else {
        fatalError("Failed to flatten \(path)")
    }
    let rep = NSBitmapImageRep(cgImage: flattened)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for \(path)")
    }
    try! data.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path)")
}

let args = CommandLine.arguments
guard args.count == 2 else {
    fatalError("Usage: swift scripts/render_app_icon.swift <path-to-Assets.xcassets>")
}
let assetsRoot = args[1]

MainActor.assumeIsolated {
    for look in IconLook.allCases {
        let iconDir = "\(assetsRoot)/\(look.appIconSetName).appiconset"
        renderPNG(look: look, dark: false, scale: 1, to: "\(iconDir)/icon-light.png")
        renderPNG(look: look, dark: true, scale: 1, to: "\(iconDir)/icon-dark.png")

        let previewDir = "\(assetsRoot)/\(look.previewImageSetName).imageset"
        renderPNG(look: look, dark: false, scale: 0.25, to: "\(previewDir)/preview-light.png")
        renderPNG(look: look, dark: true, scale: 0.25, to: "\(previewDir)/preview-dark.png")
    }
}
