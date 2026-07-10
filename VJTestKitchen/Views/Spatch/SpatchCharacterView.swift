import SwiftUI

/// Spatch: the app's mascot — a teal silicone spatula with a long wooden
/// handle, a curled wire arm holding a measuring spoon, and reactive googly
/// eyes (all echoing the reference photo). Pure vector SwiftUI (no image
/// assets), shared verbatim between iOS and macOS. Eyes drift on their own
/// when idle, follow a drag within a small radius (like the real toy, they
/// track whatever's nudging them), and the whole body gives a little spring
/// wobble on release, like bopping a googly-eye toy. A subtle breathing scale
/// keeps him feeling alive even at rest.
///
/// Every part is laid out in a fixed **design coordinate space**
/// (`designSize`, 112×220 units) and multiplied by one uniform scale factor
/// (`min(frameWidth/112, frameHeight/220)`), then centered. That makes his
/// proportions immune to the caller's frame shape — a too-wide frame yields a
/// centered, correctly-proportioned spatula with side margins, never a fat
/// one. Placement uses only fixed `.frame`s and `.offset()` (an earlier
/// version that computed a fit via nested `GeometryReader` + `.position()`
/// rendered at the wrong scale in the running app despite looking correct in
/// static previews — `.offset` is a pure render-time translation and cannot
/// affect layout/sizing the way `.position()` can).
struct SpatchCharacterView: View {
    var mood: SpatchMood = .idle
    /// Flips him horizontally — the arm/spoon (drawn on the trailing side by
    /// default) and the whole silhouette mirror together, so he reads as
    /// facing the other way. Callers pop him in "facing inward": mirrored at a
    /// trailing-corner cameo, unmirrored at a leading one (see
    /// `SpatchCorner.isTrailing` / `SpatchBuddyView`).
    var isMirrored = false

    @State private var isBlinking = false
    @State private var idleLookOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var wobble: Angle = .zero
    @State private var isDragging = false
    @State private var isBreathing = false

    /// The fixed canvas every part is positioned in, in design units.
    private static let designSize = CGSize(width: 112, height: 220)

    /// How far the pupils can travel from their eye's center, in design units
    /// (scaled with him, so pupils stay inside the eye at cameo size too).
    private let pupilTravelUnits: CGFloat = 4.5

    var body: some View {
        GeometryReader { proxy in
            let unit = min(
                proxy.size.width / Self.designSize.width,
                proxy.size.height / Self.designSize.height
            )

            character(unit: unit)
                .frame(width: Self.designSize.width * unit, height: Self.designSize.height * unit)
                .scaleEffect(x: isMirrored ? -1 : 1, y: isBreathing ? 1.02 : 1, anchor: .bottom)
                .rotationEffect(wobble, anchor: .bottom)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            dragOffset = clamp(value.translation, radius: pupilTravelUnits * unit)
                        }
                        .onEnded { _ in
                            isDragging = false
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                                dragOffset = .zero
                            }
                            bop()
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity) // center in whatever frame the caller gave
        }
        .task { await runIdleLoop() }
        .task { await runBreathingLoop() }
    }

    // MARK: - Assembly

    /// All parts positioned in the design space, back to front: the wire arm
    /// tucks *behind* the handle (so its joint is hidden, like the reference
    /// photo), then handle, then the paddle head with the face.
    private func character(unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            arm(unit: unit)
            spoon(unit: unit)
            handle(unit: unit)
            head(unit: unit)
        }
        .frame(
            width: Self.designSize.width * unit,
            height: Self.designSize.height * unit,
            alignment: .topLeading
        )
    }

    private var siliconeTeal: Color { SpatchPalette.teal }
    private var siliconeTealDeep: Color { SpatchPalette.tealDeep }
    private var woodLight: Color { SpatchPalette.woodLight }
    private var woodDark: Color { SpatchPalette.woodDark }
    private var blushPink: Color { SpatchPalette.blushPink }
    private var wireGray: Color { SpatchPalette.wireGray }
    private var spoonGray: Color { SpatchPalette.spoonGray }

    // MARK: - Head (the paddle face)

    /// A real spatula-paddle silhouette: generous rounding, a top edge that
    /// slants gently down toward the trailing side, and sides that taper
    /// inward toward the neck — not a symmetric rounded blob.
    private func head(unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            SpatulaHeadShape()
                .fill(
                    LinearGradient(
                        colors: [siliconeTeal, siliconeTealDeep],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            // A soft sheen so the silicone reads as glossy, not flat.
            Ellipse()
                .fill(Color.white.opacity(0.14))
                .frame(width: 34 * unit, height: 14 * unit)
                .rotationEffect(.degrees(-18))
                .offset(x: 10 * unit, y: 8 * unit)

            eyebrow(unit: unit)
                .rotationEffect(.degrees(Double(-mood.eyebrowTilt) * 14))
                .offset(x: 21 * unit, y: 17 * unit)
            eyebrow(unit: unit)
                .rotationEffect(.degrees(Double(mood.eyebrowTilt) * 14))
                .offset(x: 49 * unit, y: 18 * unit)

            eye(unit: unit)
                .offset(x: 17 * unit, y: 29 * unit)
            eye(unit: unit, isRightEye: true)
                .offset(x: 45 * unit, y: 29 * unit)

            blushDot(unit: unit).offset(x: 13 * unit, y: 59 * unit)
            blushDot(unit: unit).offset(x: 63 * unit, y: 59 * unit)

            mouth(unit: unit)
        }
        .frame(width: 88 * unit, height: 94 * unit, alignment: .topLeading)
        .offset(x: 2 * unit, y: 2 * unit)
    }

    /// A thin arched brow — a stroked curve, not a heavy filled bar.
    private func eyebrow(unit: CGFloat) -> some View {
        BrowShape()
            .stroke(Color.black.opacity(0.7), style: StrokeStyle(lineWidth: max(1.2, 2.4 * unit), lineCap: .round))
            .frame(width: 18 * unit, height: 6 * unit)
    }

    /// A googly eye: white with a thin dark rim (like the plastic toy), pupil
    /// + catch-light inside.
    private func eye(unit: CGFloat, isRightEye: Bool = false) -> some View {
        let size = 26 * unit
        return ZStack {
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: max(0.8, 1.6 * unit)))
                .shadow(color: .black.opacity(0.18), radius: 1.5 * unit, y: 1 * unit)
            if mood.isWinking && isRightEye {
                Capsule()
                    .fill(Color.black)
                    .frame(width: size * 0.62, height: max(1.5, size * 0.12))
            } else {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: size * 0.46, height: size * 0.46)
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: size * 0.14, height: size * 0.14)
                        .offset(x: -size * 0.1, y: -size * 0.1)
                }
                .offset(pupilOffset)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(y: isBlinking ? 0.15 : 1, anchor: .center)
    }

    @ViewBuilder
    private func mouth(unit: CGFloat) -> some View {
        switch mood.openMouthKind {
        case .laugh:
            openSmile(unit: unit, width: 38, height: 21)
                .offset(x: 25 * unit, y: 58 * unit)
        case .surprised:
            Circle()
                .fill(Color.black.opacity(0.82))
                .frame(width: 12 * unit, height: 12 * unit)
                .offset(x: 38 * unit, y: 61 * unit)
        case nil where mood.mouthCurve >= 0.7:
            // A big happy grin renders open (dark mouth + tongue), like the
            // reference photo — a closed stroke only for calmer moods.
            openSmile(unit: unit, width: 30, height: 16)
                .offset(x: 29 * unit, y: 60 * unit)
        case nil:
            MouthShape(curve: mood.mouthCurve)
                .stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: max(1.8, 3.4 * unit), lineCap: .round))
                .frame(width: 28 * unit, height: 10 * unit)
                .offset(x: 30 * unit, y: 63 * unit)
        }
    }

    /// The open-smile "D" (flat-ish top, deep curved bottom) with a tongue —
    /// the reference photo's expression.
    private func openSmile(unit: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            OpenSmileShape()
                .fill(Color.black.opacity(0.85))
            Ellipse()
                .fill(blushPink)
                .frame(width: width * 0.62 * unit, height: height * 0.5 * unit)
                .offset(y: height * 0.16 * unit)
        }
        .frame(width: width * unit, height: height * unit)
        .clipShape(OpenSmileShape())
    }

    private func blushDot(unit: CGFloat) -> some View {
        Ellipse()
            .fill(blushPink.opacity(0.65))
            .frame(width: 12 * unit, height: 7 * unit)
    }

    // MARK: - Handle

    private func handle(unit: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8 * unit, style: .continuous)
                .fill(
                    LinearGradient(colors: [woodLight, woodDark], startPoint: .top, endPoint: .bottom)
                )
            // The hang-hole near the base, like a real spatula handle.
            Circle()
                .fill(Color.black.opacity(0.28))
                .frame(width: 8 * unit, height: 8 * unit)
                .padding(.bottom, 10 * unit)
        }
        .frame(width: 17 * unit, height: 118 * unit)
        .offset(x: 37.5 * unit, y: 92 * unit)
    }

    // MARK: - Arm + measuring spoon

    /// The curled wire arm, emerging from *behind the handle* at the neck (so
    /// it never crosses the face) and swooping out to hold the spoon beside
    /// the paddle — the asymmetric detail from the reference photo, and what
    /// makes `isMirrored` visually read as "facing the other way" rather than
    /// a no-op flip of an otherwise-symmetric face.
    private func arm(unit: CGFloat) -> some View {
        ArmPath()
            .stroke(wireGray, style: StrokeStyle(lineWidth: max(1.4, 3.2 * unit), lineCap: .round))
            .frame(width: 52 * unit, height: 44 * unit)
            .offset(x: 50 * unit, y: 74 * unit)
            .allowsHitTesting(false)
    }

    private func spoon(unit: CGFloat) -> some View {
        VStack(spacing: -2 * unit) {
            ZStack {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [spoonGray, wireGray],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                Ellipse()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 5 * unit, height: 4 * unit)
                    .offset(x: -2.5 * unit, y: -4 * unit)
            }
            .frame(width: 14 * unit, height: 17 * unit)
            Capsule()
                .fill(wireGray)
                .frame(width: 3.2 * unit, height: 16 * unit)
        }
        .frame(width: 14 * unit, alignment: .center)
        .offset(x: 89 * unit, y: 52 * unit)
        .allowsHitTesting(false)
    }

    // MARK: - Life

    /// A quick spring rotation, like bopping a googly-eye toy — triggered when
    /// a drag/tap ends.
    private func bop() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.35)) {
            wobble = .degrees(Double.random(in: -8...8))
        }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                wobble = .zero
            }
        }
    }

    /// Idle eye wander + blinking, so Spatch feels alive even when no one's
    /// touching him. Torn down automatically with the view (`.task` cancels on
    /// disappear).
    private func runIdleLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(.random(in: 2...4)))
            guard !Task.isCancelled, !isDragging else { continue }
            withAnimation(.easeInOut(duration: 0.5)) {
                idleLookOffset = CGSize(
                    width: .random(in: -2...2),
                    height: .random(in: -1.2...1.2)
                )
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { continue }
            withAnimation(.easeInOut(duration: 0.12)) { isBlinking = true }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeInOut(duration: 0.12)) { isBlinking = false }
        }
    }

    /// A slow, gentle scale breathe so Spatch never looks like a frozen sticker.
    private func runBreathingLoop() async {
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 1.8)) { isBreathing = true }
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.8)) { isBreathing = false }
            try? await Task.sleep(for: .seconds(1.8))
        }
    }

    /// Negates the x-component when mirrored, so the pupils — drawn in this
    /// pre-mirror coordinate space — still visually track the real drag
    /// direction once the whole view is flipped for rendering.
    private func clamp(_ translation: CGSize, radius: CGFloat) -> CGSize {
        let signed = isMirrored ? CGSize(width: -translation.width, height: translation.height) : translation
        let distance = (signed.width * signed.width + signed.height * signed.height).squareRoot()
        guard distance > radius else { return signed }
        let scale = radius / distance
        return CGSize(width: signed.width * scale, height: signed.height * scale)
    }

    private var pupilOffset: CGSize {
        isDragging ? dragOffset : idleLookOffset
    }
}

/// Spatch's own colors — the mascot's identity, deliberately separate from
/// the brand palette in Theme.swift (whose roles don't cover "cheerful teal
/// silicone" or "light wood", and the mascot shouldn't repaint if the brand
/// palette shifts). Shared by every Spatch-branded surface — the character
/// itself, his speech bubble, and the tutorial card — so they can't drift
/// apart the way the old sage-tinted chrome did after his teal redesign.
enum SpatchPalette {
    static let teal = Color.dynamic(light: 0x4FB0A5, dark: 0x53BCB0)
    static let tealDeep = Color.dynamic(light: 0x3E958B, dark: 0x429D92)
    static let woodLight = Color.dynamic(light: 0xC08A52, dark: 0xB37F4A)
    static let woodDark = Color.dynamic(light: 0x9C6C3C, dark: 0x8F6236)
    static let blushPink = Color.dynamic(light: 0xF08C8C, dark: 0xE98A8A)
    static let wireGray = Color.dynamic(light: 0x8E9296, dark: 0xA6AAAE)
    static let spoonGray = Color.dynamic(light: 0xB4B8BC, dark: 0xC2C6CA)
}

// MARK: - Shapes

/// The paddle silhouette: big rounded top corners with the top edge slanting
/// gently down toward the trailing side, sides tapering inward to the neck.
private struct SpatulaHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        // Corner points in unit-ish proportions of the design (88x94 box).
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

/// A thin arched eyebrow.
private struct BrowShape: Shape {
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

/// A closed smile/frown curve, driven by `SpatchMood.mouthCurve` (-1 frown ...
/// +1 big smile). Open-mouth moods are drawn by `openSmile`/`OpenSmileShape`.
private struct MouthShape: Shape {
    var curve: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.midY + rect.height * curve * 1.6)
        )
        return path
    }
}

/// The open grin: a gently curved top lip and a deep round bottom — a "D"
/// lying on its flat side.
private struct OpenSmileShape: Shape {
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

/// The wire arm: out from behind the handle, a low outward swoop, then curling
/// up to meet the spoon's stem.
private struct ArmPath: Shape {
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

#Preview {
    HStack(spacing: 24) {
        ForEach(SpatchMood.allCases, id: \.self) { mood in
            SpatchCharacterView(mood: mood)
                .frame(width: 60, height: 130)
        }
    }
    .padding()
}

#Preview("Mirrored") {
    HStack(spacing: 24) {
        SpatchCharacterView(mood: .happy, isMirrored: false)
            .frame(width: 60, height: 130)
        SpatchCharacterView(mood: .happy, isMirrored: true)
            .frame(width: 60, height: 130)
    }
    .padding()
}
