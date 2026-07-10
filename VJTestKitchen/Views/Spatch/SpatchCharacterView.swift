import SwiftUI

/// Spatch: the app's mascot — a sage-green silicone spatula with a wooden
/// handle, a curled wire arm holding a spoon (echoing the reference photo),
/// and reactive googly eyes. Pure vector SwiftUI (no image assets), shared
/// verbatim between iOS and macOS. Eyes drift on their own when idle, follow a
/// drag within a small radius (the "reactive googly eyes" bit — like the real
/// toy, they track whatever's nudging them), and the whole head gives a
/// little spring wobble on release, like bopping a googly-eye toy. A subtle
/// breathing scale keeps him feeling alive even at rest.
///
/// He always renders at a fixed, deliberately narrow aspect ratio (a real
/// spatula silhouette, not a rounded blob) regardless of the frame he's given
/// — `fittedSize(in:)` fits that ratio inside the available space and centers
/// it, so callers can just hand him a bounding box.
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

    /// How far the pupils can travel from center, in points.
    private let pupilTravel: CGFloat = 6
    /// Width ÷ height of the whole character — narrower than a plain blob so
    /// he reads as an actual spatula silhouette.
    private let aspectRatio: CGFloat = 0.42

    var body: some View {
        GeometryReader { proxy in
            let size = fittedSize(in: proxy.size)

            ZStack(alignment: .top) {
                VStack(spacing: -size.height * 0.03) {
                    head(width: size.width, height: size.height * 0.68)
                    handle(width: size.width * 0.3, height: size.height * 0.34)
                }
                .frame(width: size.width, height: size.height, alignment: .top)

                arm(characterSize: size)
            }
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .scaleEffect(x: isMirrored ? -1 : 1, y: isBreathing ? 1.03 : 1, anchor: .bottom)
            .rotationEffect(wobble, anchor: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragOffset = clamp(value.translation)
                    }
                    .onEnded { _ in
                        isDragging = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                            dragOffset = .zero
                        }
                        bop()
                    }
            )
        }
        .task { await runIdleLoop() }
        .task { await runBreathingLoop() }
    }

    /// Fits `aspectRatio` inside `available`, centered — so he's always the
    /// same narrow shape no matter what bounding box a caller provides.
    private func fittedSize(in available: CGSize) -> CGSize {
        let widthFromHeight = available.height * aspectRatio
        if widthFromHeight <= available.width {
            return CGSize(width: widthFromHeight, height: available.height)
        } else {
            return CGSize(width: available.width, height: available.width / aspectRatio)
        }
    }

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
                    width: .random(in: -pupilTravel...pupilTravel),
                    height: .random(in: -pupilTravel * 0.6...pupilTravel * 0.6)
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
    private func clamp(_ translation: CGSize) -> CGSize {
        let signed = isMirrored ? CGSize(width: -translation.width, height: translation.height) : translation
        let distance = (signed.width * signed.width + signed.height * signed.height).squareRoot()
        guard distance > pupilTravel else { return signed }
        let scale = pupilTravel / distance
        return CGSize(width: signed.width * scale, height: signed.height * scale)
    }

    private var pupilOffset: CGSize {
        isDragging ? dragOffset : idleLookOffset
    }

    // MARK: - Head

    /// Flatter and more rectangular than a plain rounded blob — rounded top
    /// corners (the paddle face), tighter bottom corners (the neck meeting the
    /// handle) — via `UnevenRoundedRectangle`, closer to a real spatula head.
    private func head(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: width * 0.34,
                bottomLeadingRadius: width * 0.1,
                bottomTrailingRadius: width * 0.1,
                topTrailingRadius: width * 0.34,
                style: .continuous
            )
            .fill(Color.brandSage)

            // A faint center seam, like the mold-line on a real silicone spatula.
            Capsule()
                .fill(Color.black.opacity(0.06))
                .frame(width: max(1.5, width * 0.02), height: height * 0.55)
                .offset(y: height * 0.18)

            VStack(spacing: height * 0.04) {
                eyebrows(width: width, height: height)
                eyes(width: width, height: height)
                mouth(width: width, height: height)
            }
            .padding(.top, height * 0.16)

            blush(width: width, height: height)
        }
        .frame(width: width, height: height)
    }

    private func eyebrows(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: width * 0.16) {
            eyebrow(width: width * 0.26, height: height)
                .rotationEffect(.degrees(Double(-mood.eyebrowTilt) * 16))
            eyebrow(width: width * 0.26, height: height)
                .rotationEffect(.degrees(Double(mood.eyebrowTilt) * 16))
        }
    }

    private func eyebrow(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(Color.black.opacity(0.6))
            .frame(width: width, height: max(2.5, height * 0.03))
    }

    private func eyes(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: width * 0.1) {
            eye(size: width * 0.28)
            eye(size: width * 0.28, isRightEye: true)
        }
    }

    private func eye(size: CGFloat, isRightEye: Bool = false) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            if mood.isWinking && isRightEye {
                Capsule()
                    .fill(Color.black)
                    .frame(width: size * 0.7, height: size * 0.12)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: size * 0.44, height: size * 0.44)
                    // A small catch-light so the pupil doesn't read as a flat dot.
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: size * 0.12, height: size * 0.12)
                        .offset(x: -size * 0.1, y: -size * 0.1)
                }
                .offset(pupilOffset)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(y: isBlinking ? 0.15 : 1, anchor: .center)
    }

    @ViewBuilder
    private func mouth(width: CGFloat, height: CGFloat) -> some View {
        switch mood.openMouthKind {
        case .laugh:
            ZStack {
                Ellipse().fill(Color.black.opacity(0.85))
                Ellipse()
                    .fill(Color.white.opacity(0.9))
                    .frame(height: height * 0.06)
                    .offset(y: -height * 0.055)
            }
            .frame(width: width * 0.44, height: height * 0.22)
        case .surprised:
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: width * 0.18, height: width * 0.18)
        case nil:
            MouthShape(curve: mood.mouthCurve)
                .fill(Color.black)
                .frame(width: width * 0.5, height: height * 0.18)
        }
    }

    private func blush(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: width * 0.32) {
            Capsule().fill(Color.brandSaffron.opacity(0.4)).frame(width: width * 0.16, height: width * 0.08)
            Capsule().fill(Color.brandSaffron.opacity(0.4)).frame(width: width * 0.16, height: width * 0.08)
        }
        .offset(y: height * 0.2)
    }

    // MARK: - Handle

    private func handle(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: width * 0.3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.62, green: 0.44, blue: 0.27), Color(red: 0.5, green: 0.34, blue: 0.2)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            // The hang-hole near the base, like a real spatula handle.
            Circle()
                .fill(Color.black.opacity(0.2))
                .frame(width: width * 0.4, height: width * 0.4)
                .padding(.bottom, height * 0.14)
        }
        .frame(width: width, height: height)
    }

    // MARK: - Arm + spoon

    /// A little curled wire arm holding a spoon, emerging from the trailing
    /// side of the neck — the asymmetric detail from the reference photo, and
    /// what makes `isMirrored` visually read as "facing the other way" rather
    /// than a no-op flip of an otherwise-symmetric face.
    private func arm(characterSize: CGSize) -> some View {
        let armWidth = characterSize.width * 0.55
        let armHeight = characterSize.height * 0.2

        return ZStack(alignment: .topLeading) {
            ArmPath()
                .stroke(Color(white: 0.6), style: StrokeStyle(lineWidth: max(1.5, characterSize.width * 0.05), lineCap: .round))
            spoon(width: characterSize.width * 0.26)
                .position(x: armWidth * 0.95, y: armHeight * 0.92)
        }
        .frame(width: armWidth, height: armHeight)
        .position(x: characterSize.width * 0.78, y: characterSize.height * 0.64)
    }

    private func spoon(width: CGFloat) -> some View {
        VStack(spacing: -width * 0.08) {
            Ellipse()
                .fill(Color(white: 0.7))
                .frame(width: width * 0.6, height: width * 0.85)
            Capsule()
                .fill(Color(white: 0.62))
                .frame(width: width * 0.18, height: width)
        }
    }
}

/// A closed smile/frown curve, driven by `SpatchMood.mouthCurve` (-1 frown ...
/// +1 big smile). Open-mouth moods (laugh/surprised) are drawn separately by
/// `SpatchCharacterView.mouth`.
private struct MouthShape: Shape {
    var curve: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.midY)
        let end = CGPoint(x: rect.maxX, y: rect.midY)
        let control = CGPoint(x: rect.midX, y: rect.midY + rect.height * curve)
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path.strokedPath(StrokeStyle(lineWidth: max(2, rect.height * 0.18), lineCap: .round))
    }
}

/// A gently curled wire, like the reference photo's spoon-holding arm —
/// bowing outward from the neck before curling back in toward the spoon.
private struct ArmPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX * 0.92, y: rect.maxY * 0.88),
            control1: CGPoint(x: rect.maxX * 0.75, y: rect.minY + rect.height * 0.05),
            control2: CGPoint(x: rect.maxX * 0.55, y: rect.maxY * 0.75)
        )
        return path
    }
}

#Preview {
    HStack(spacing: 24) {
        ForEach(SpatchMood.allCases, id: \.self) { mood in
            SpatchCharacterView(mood: mood)
                .frame(width: 90, height: 130)
        }
    }
    .padding()
}

#Preview("Mirrored") {
    HStack(spacing: 24) {
        SpatchCharacterView(mood: .happy, isMirrored: false)
            .frame(width: 90, height: 130)
        SpatchCharacterView(mood: .happy, isMirrored: true)
            .frame(width: 90, height: 130)
    }
    .padding()
}
