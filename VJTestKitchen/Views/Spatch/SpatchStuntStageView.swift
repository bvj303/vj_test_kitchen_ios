import SwiftUI

/// The full-screen layer Spatch's surprise stunts play on — hosted once in
/// `MainTabView` above the tabs, drawing whatever `SpatchStuntCoordinator`
/// says is running. Purely decorative: hit-testing is off for the whole
/// layer, so a flyby never blocks a tap on the content underneath.
struct SpatchStuntStageView: View {
    // Optional so previews without the app root's injection still build.
    @Environment(SpatchStuntCoordinator.self) private var coordinator: SpatchStuntCoordinator?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let run = coordinator?.activeRun {
                    SpatchStuntPerformanceView(
                        run: run,
                        stageSize: proxy.size,
                        // Same regular-width upsizing as his cameos — stunt
                        // Spatch would read as a speck on iPad/Mac at phone size.
                        characterSize: horizontalSizeClass == .regular
                            ? CGSize(width: 72, height: 152)
                            : CGSize(width: 48, height: 101)
                    )
                    // Keyed on the run, not the stunt, so two consecutive runs
                    // of the same stunt still restart the animation cleanly.
                    .id(run.id)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// One performance: assembles the right prop rig around the character and
/// drives one linear 0→1 progress through `StuntMotionModifier`, which maps it
/// per-frame onto the stunt's real path (hops, sways, rolls) via
/// `SpatchStuntChoreography`.
struct SpatchStuntPerformanceView: View {
    let run: SpatchStuntRun
    let stageSize: CGSize
    let characterSize: CGSize
    /// Freeze the flyby at a fixed progress instead of animating — lets
    /// previews (and snapshot checks) show each stunt's rig mid-flight.
    var frozenAtProgress: CGFloat?

    @State private var progress: CGFloat = 0

    init(run: SpatchStuntRun, stageSize: CGSize, characterSize: CGSize, frozenAtProgress: CGFloat? = nil) {
        self.run = run
        self.stageSize = stageSize
        self.characterSize = characterSize
        self.frozenAtProgress = frozenAtProgress
    }

    var body: some View {
        performer
            .frame(width: performerSize.width, height: performerSize.height)
            .modifier(
                StuntMotionModifier(
                    progress: frozenAtProgress ?? progress,
                    run: run,
                    stageSize: stageSize,
                    performerSize: performerSize
                )
            )
            .onAppear {
                guard frozenAtProgress == nil else { return }
                withAnimation(.linear(duration: run.stunt.duration)) {
                    progress = 1
                }
            }
    }

    /// Faces the way he's traveling — the arm/spoon side flips with him, same
    /// as cameo pop-ins facing inward from their screen edge.
    private var facesReversed: Bool { run.isReversed }

    /// The prop rig's footprint. Balloons stack well above him; the spacewalk
    /// pads out for the helmet and stars.
    private var performerSize: CGSize {
        switch run.stunt {
        case .balloonRide:
            CGSize(width: characterSize.width * 2.3, height: characterSize.height * 1.8)
        case .spacewalk:
            CGSize(width: characterSize.width * 2.6, height: characterSize.height * 1.25)
        case .dash:
            CGSize(width: characterSize.width * 3.2, height: characterSize.height)
        case .somersault:
            CGSize(width: characterSize.width, height: characterSize.height)
        case .paperPlane:
            CGSize(width: characterSize.width * 2.4, height: characterSize.height * 1.15)
        case .rocketRide:
            CGSize(width: characterSize.width * 1.4, height: characterSize.height * 1.35)
        case .parachuteDrop:
            CGSize(width: characterSize.width * 2.6, height: characterSize.height * 1.62)
        case .bubbleBounce:
            CGSize(width: characterSize.height * 1.12, height: characterSize.height * 1.12)
        case .whiskBroom:
            CGSize(width: characterSize.width * 2.8, height: characterSize.height * 1.12)
        case .pizzaSurf:
            CGSize(width: characterSize.width * 2.2, height: characterSize.height * 1.15)
        case .rollingPin:
            CGSize(width: characterSize.width * 2.0, height: characterSize.height * 1.12)
        case .toastPop:
            CGSize(width: characterSize.width * 1.7, height: characterSize.height * 1.05)
        case .potSail:
            CGSize(width: characterSize.width * 2.0, height: characterSize.height * 1.05)
        }
    }

    @ViewBuilder
    private var performer: some View {
        switch run.stunt {
        case .somersault:
            character(mood: .laughing)

        case .dash:
            // Motion lines trail *behind* the sprint, whichever way he's headed.
            HStack(spacing: characterSize.width * 0.18) {
                if run.isReversed {
                    character(mood: .laughing)
                    motionLines
                } else {
                    motionLines
                    character(mood: .laughing)
                }
            }

        case .balloonRide:
            VStack(spacing: -characterSize.height * 0.02) {
                BalloonBunchView()
                    .frame(width: characterSize.width * 2.1, height: characterSize.height * 0.82)
                character(mood: .happy)
            }

        case .spacewalk:
            ZStack {
                spacewalkStars
                character(mood: .surprised)
                    .overlay(alignment: .topLeading) { helmet }
            }

        case .paperPlane:
            // He rides just above the fold; the plane mirrors with him so the
            // nose always points the way he's flying.
            VStack(spacing: -characterSize.height * 0.08) {
                character(mood: .happy)
                PaperPlaneShape()
                    .fill(Color.white)
                    .overlay(
                        PaperPlaneShape()
                            .stroke(Color.black.opacity(0.25), lineWidth: max(1, characterSize.width * 0.02))
                    )
                    .frame(width: characterSize.width * 2.4, height: characterSize.height * 0.23)
                    .scaleEffect(x: facesReversed ? -1 : 1)
            }

        case .rocketRide:
            // He *is* the rocket — flame right off the handle tip.
            VStack(spacing: -characterSize.height * 0.03) {
                character(mood: .surprised)
                rocketFlame
            }

        case .parachuteDrop:
            VStack(spacing: -characterSize.height * 0.02) {
                ParachuteCanopyView()
                    .frame(width: characterSize.width * 2.6, height: characterSize.height * 0.64)
                character(mood: .winking)
            }

        case .bubbleBounce:
            ZStack {
                character(mood: .laughing)
                soapBubble
            }

        case .whiskBroom:
            // Witch-style: astride the whisk's rod, bristle cage trailing
            // behind — the whisk mirrors with him like the paper plane.
            ZStack {
                WhiskView()
                    .frame(width: characterSize.width * 2.7, height: characterSize.width * 0.85)
                    .scaleEffect(x: facesReversed ? -1 : 1)
                    .rotationEffect(.degrees(facesReversed ? 8 : -8))
                    .offset(y: characterSize.height * 0.30)
                // Astride the rod (not the collar), bristle cage behind him.
                character(mood: .laughing)
                    .offset(
                        x: characterSize.width * 0.55 * (facesReversed ? -1 : 1),
                        y: -characterSize.height * 0.06
                    )
            }

        case .pizzaSurf:
            VStack(spacing: -characterSize.height * 0.10) {
                character(mood: .happy)
                PizzaView()
                    .frame(width: characterSize.width * 2.1, height: characterSize.width * 0.62)
            }

        case .rollingPin:
            VStack(spacing: -characterSize.height * 0.07) {
                character(mood: .thinking)
                RollingPinView()
                    .frame(width: characterSize.width * 1.9, height: characterSize.width * 0.34)
            }

        case .toastPop:
            // He rides up hugging the slice — toast behind, Spatch in front.
            ZStack {
                ToastShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.91, green: 0.72, blue: 0.42), Color(red: 0.78, green: 0.55, blue: 0.28)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        // The pale crumb face inside the crust.
                        ToastShape()
                            .fill(Color(red: 0.96, green: 0.87, blue: 0.64))
                            .scaleEffect(0.82)
                    )
                    .frame(width: characterSize.width * 1.55, height: characterSize.width * 1.65)
                    .offset(x: characterSize.width * (facesReversed ? -0.18 : 0.18), y: -characterSize.height * 0.14)
                character(mood: .surprised)
            }

        case .potSail:
            // Sitting in the pot: his handle end hides behind it, steam
            // curling up off the broth beside him.
            ZStack(alignment: .bottom) {
                character(mood: .winking)
                    .offset(y: -characterSize.height * 0.16)
                StockpotView(steamColor: Color.white.opacity(0.55))
                    .frame(width: characterSize.width * 1.9, height: characterSize.height * 0.52)
            }
        }
    }

    private func character(mood: SpatchMood) -> some View {
        SpatchCharacterView(mood: mood, isMirrored: facesReversed)
            .frame(width: characterSize.width, height: characterSize.height)
    }

    private var motionLines: some View {
        VStack(alignment: run.isReversed ? .leading : .trailing, spacing: characterSize.height * 0.12) {
            motionLine(relativeWidth: 0.9)
            motionLine(relativeWidth: 1.5)
            motionLine(relativeWidth: 0.7)
        }
    }

    private func motionLine(relativeWidth: CGFloat) -> some View {
        Capsule()
            .fill(SpatchPalette.teal.opacity(0.45))
            .frame(width: characterSize.width * relativeWidth, height: max(3, characterSize.height * 0.035))
    }

    /// A bubble space helmet over his head. The head sits left of the design
    /// space's center (the arm claims the trailing side), and mirroring flips
    /// that, so the helmet's anchor flips with him.
    private var helmet: some View {
        let diameter: CGFloat = characterSize.width * 1.02
        let headCenterX: CGFloat = characterSize.width * (facesReversed ? 0.59 : 0.41)
        let headCenterY: CGFloat = characterSize.height * 0.22
        let glareSize = CGSize(width: diameter * 0.28, height: diameter * 0.12)
        let glareOffset = CGSize(width: -diameter * 0.22, height: -diameter * 0.28)
        // A little glass glare on the upper-leading curve.
        let glare = Ellipse()
            .fill(Color.white.opacity(0.35))
            .frame(width: glareSize.width, height: glareSize.height)
            .rotationEffect(.degrees(-24))
            .offset(x: glareOffset.width, y: glareOffset.height)
        return Circle()
            .fill(Color.white.opacity(0.12))
            .overlay(
                Circle().stroke(Color.white.opacity(0.75), lineWidth: max(1.5, diameter * 0.035))
            )
            .overlay(glare)
            .frame(width: diameter, height: diameter)
            .offset(x: headCenterX - diameter / 2, y: headCenterY - diameter / 2)
    }

    /// A two-tone thrust flame off the handle tip, with a couple of faint
    /// smoke puffs peeling away beside it.
    private var rocketFlame: some View {
        let flameWidth: CGFloat = characterSize.width * 0.42
        let flameHeight: CGFloat = characterSize.height * 0.30
        let innerFlame = Ellipse()
            .fill(Color.yellow.opacity(0.9))
            .frame(width: flameWidth * 0.5, height: flameHeight * 0.6)
            .offset(y: -flameHeight * 0.12)
        let puffColor = Color.white.opacity(0.55)
        return ZStack {
            Ellipse()
                .fill(Color.orange)
                .overlay(innerFlame)
                .frame(width: flameWidth, height: flameHeight)
            Circle()
                .fill(puffColor)
                .frame(width: flameWidth * 0.5, height: flameWidth * 0.5)
                .offset(x: -flameWidth * 0.85, y: flameHeight * 0.30)
            Circle()
                .fill(puffColor.opacity(0.6))
                .frame(width: flameWidth * 0.36, height: flameWidth * 0.36)
                .offset(x: flameWidth * 0.8, y: flameHeight * 0.38)
        }
    }

    /// The soap bubble he's sealed inside — a faint teal-tinted sphere with a
    /// bright rim and a couple of glares, big enough to clear his whole body.
    private var soapBubble: some View {
        let diameter: CGFloat = characterSize.height * 1.10
        let mainGlare = Ellipse()
            .fill(Color.white.opacity(0.45))
            .frame(width: diameter * 0.22, height: diameter * 0.10)
            .rotationEffect(.degrees(-32))
            .offset(x: -diameter * 0.24, y: -diameter * 0.30)
        let smallGlare = Circle()
            .fill(Color.white.opacity(0.3))
            .frame(width: diameter * 0.06, height: diameter * 0.06)
            .offset(x: diameter * 0.3, y: diameter * 0.22)
        return Circle()
            .fill(SpatchPalette.teal.opacity(0.10))
            .overlay(
                Circle().stroke(Color.white.opacity(0.8), lineWidth: max(1.5, diameter * 0.02))
            )
            .overlay(mainGlare)
            .overlay(smallGlare)
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
    }

    /// A few twinkly companions drifting along with the spacewalk.
    private var spacewalkStars: some View {
        ZStack {
            star(size: 0.16, x: -0.95, y: -0.42, opacity: 0.9)
            star(size: 0.11, x: 0.9, y: -0.25, opacity: 0.6)
            star(size: 0.09, x: -0.75, y: 0.35, opacity: 0.5)
            star(size: 0.13, x: 0.8, y: 0.42, opacity: 0.75)
        }
    }

    private func star(size: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: characterSize.width * size * 2))
            .foregroundStyle(Color.brandSaffron.opacity(opacity))
            .offset(
                x: x * characterSize.width,
                y: y * characterSize.height * 0.5
            )
    }
}

/// Applies the choreography per animation frame. `Animatable` is what makes
/// the arcs real: the driving animation is a plain linear 0→1, and every
/// interpolated progress value re-runs the placement math, so hops and sways
/// render as smooth curves rather than a straight lerp between endpoints.
// `@preconcurrency` because `ViewModifier` is MainActor-isolated in the iOS 26
// SDK while `Animatable.animatableData` is a nonisolated requirement — the
// interpolator only ever touches this value-type copy on the render path.
private struct StuntMotionModifier: ViewModifier, @preconcurrency Animatable {
    var progress: CGFloat
    let run: SpatchStuntRun
    let stageSize: CGSize
    let performerSize: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let placement = SpatchStuntChoreography.placement(
            run: run,
            progress: progress,
            stage: stageSize,
            performer: performerSize
        )
        content
            .rotationEffect(.degrees(placement.rotationDegrees))
            // Placement is the rig's center; the rig itself is laid out at the
            // stage's top-leading origin. `.offset` only, per the Spatch
            // layout lesson — never `.position`.
            .offset(
                x: placement.x - performerSize.width / 2,
                y: placement.y - performerSize.height / 2
            )
    }
}

/// Three party balloons on strings converging to where Spatch holds on.
private struct BalloonBunchView: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack(alignment: .topLeading) {
                BalloonStringsShape()
                    .stroke(Color.white.opacity(0.7), lineWidth: max(1, h * 0.014))
                balloon(color: SpatchPalette.blushPink, w: w, h: h, centerX: 0.24, centerY: 0.30)
                balloon(color: Color.brandSaffron, w: w, h: h, centerX: 0.52, centerY: 0.22)
                balloon(color: SpatchPalette.teal, w: w, h: h, centerX: 0.78, centerY: 0.32)
            }
        }
    }

    private func balloon(color: Color, w: CGFloat, h: CGFloat, centerX: CGFloat, centerY: CGFloat) -> some View {
        let width: CGFloat = w * 0.30
        let height: CGFloat = h * 0.44
        let sheenSize = CGSize(width: width * 0.28, height: height * 0.18)
        let sheenOffset = CGSize(width: -width * 0.2, height: -height * 0.26)
        let sheen = Ellipse()
            .fill(Color.white.opacity(0.35))
            .frame(width: sheenSize.width, height: sheenSize.height)
            .offset(x: sheenOffset.width, y: sheenOffset.height)
        return Ellipse()
            .fill(color)
            .overlay(sheen)
            .frame(width: width, height: height)
            .offset(x: w * centerX - width / 2, y: h * centerY - height / 2)
    }
}

/// A giant balloon whisk lying broom-style: rod to the right (where he sits),
/// wire cage trailing at the back like bristles.
private struct WhiskView: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let wire = max(1, h * 0.05)
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [SpatchPalette.woodLight, SpatchPalette.woodDark],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: w * 0.58, height: h * 0.16)
                    .offset(x: w * 0.21)
                // Real whisk wires share both endpoints (collar and tip) and
                // differ in how far they bow out — same width, nested heights.
                // Concentric same-center loops read as a target, not a whisk.
                loop(width: w * 0.52, height: h, wire: wire, w: w)
                loop(width: w * 0.52, height: h * 0.60, wire: wire, w: w)
                loop(width: w * 0.52, height: h * 0.26, wire: wire, w: w)
                // The collar where the wires gather into the handle.
                RoundedRectangle(cornerRadius: h * 0.05, style: .continuous)
                    .fill(SpatchPalette.spoonGray)
                    .frame(width: w * 0.07, height: h * 0.24)
                    .offset(x: -w * 0.045)
            }
            .frame(width: w, height: h)
        }
    }

    private func loop(width: CGFloat, height: CGFloat, wire: CGFloat, w: CGFloat) -> some View {
        Ellipse()
            .stroke(SpatchPalette.wireGray, lineWidth: wire)
            .frame(width: width, height: height)
            .offset(x: -w * 0.26)
    }
}

/// The pepperoni pizza he surfs — a flattened perspective disc: crust ring,
/// cheese, and a scatter of pepperoni.
private struct PizzaView: View {
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

/// The rolling pin he log-rolls on: a wooden barrel with stub handles.
private struct RollingPinView: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Capsule()
                    .fill(SpatchPalette.woodDark)
                    .frame(width: w, height: h * 0.42)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [SpatchPalette.woodLight, SpatchPalette.woodDark],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: w * 0.72, height: h)
            }
            .frame(width: w, height: h)
        }
    }
}

/// A slice of toast: rounded bottom, two humps on top.
private struct ToastShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.08, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.92, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.88),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.42))
        // Two crown humps meeting in a slight center dip.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.52, y: rect.minY + h * 0.30),
            control: CGPoint(x: rect.maxX - w * 0.02, y: rect.minY - h * 0.05)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + h * 0.42),
            control: CGPoint(x: rect.minX + w * 0.02, y: rect.minY - h * 0.05)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.88))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.08, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

/// The stockpot he sails in: steel body, rolled rim, side handles, and steam
/// curling off the broth.
private struct StockpotView: View {
    var steamColor: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                steam(size: w * 0.10, x: -w * 0.24, y: -h * 0.42, opacity: 1.0)
                steam(size: w * 0.07, x: -w * 0.30, y: -h * 0.78, opacity: 0.7)
                steam(size: w * 0.09, x: w * 0.26, y: -h * 0.52, opacity: 0.85)
                // Side handles peek out from behind the rim.
                Capsule()
                    .fill(SpatchPalette.wireGray)
                    .frame(width: w * 0.16, height: h * 0.10)
                    .offset(x: -w * 0.44, y: -h * 0.10)
                Capsule()
                    .fill(SpatchPalette.wireGray)
                    .frame(width: w * 0.16, height: h * 0.10)
                    .offset(x: w * 0.44, y: -h * 0.10)
                RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SpatchPalette.spoonGray, SpatchPalette.wireGray],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: w * 0.78, height: h * 0.60)
                    .offset(y: h * 0.18)
                Capsule()
                    .fill(SpatchPalette.spoonGray)
                    .frame(width: w * 0.86, height: h * 0.16)
                    .offset(y: -h * 0.16)
            }
            .frame(width: w, height: h)
        }
    }

    private func steam(size: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(steamColor.opacity(opacity))
            .frame(width: size, height: size)
            .offset(x: x, y: y)
    }
}

/// A paper dart seen from the side, nose pointing trailing (right) — the
/// performer mirrors it when he flies the other way. Two triangles: the big
/// top wing and the lower fin he perches above.
private struct PaperPlaneShape: Shape {
    func path(in rect: CGRect) -> Path {
        let nose = CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.45)
        let tailTop = CGPoint(x: rect.minX, y: rect.minY)
        let notch = CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.55)
        let finTip = CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY)

        var path = Path()
        path.move(to: nose)
        path.addLine(to: tailTop)
        path.addLine(to: notch)
        path.closeSubpath()
        path.move(to: nose)
        path.addLine(to: notch)
        path.addLine(to: finTip)
        path.closeSubpath()
        return path
    }
}

/// The parachute rig: a saffron dome with white panel seams over suspension
/// lines converging to where Spatch hangs.
private struct ParachuteCanopyView: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack(alignment: .topLeading) {
                CanopyStringsShape()
                    .stroke(Color.white.opacity(0.75), lineWidth: max(1, h * 0.02))
                CanopyShape()
                    .fill(Color.brandSaffron)
                    .frame(width: w, height: h * 0.62)
                CanopySeamsShape()
                    .stroke(Color.white.opacity(0.55), lineWidth: max(1, h * 0.025))
                    .frame(width: w, height: h * 0.62)
            }
        }
    }
}

/// The dome: a high arc over a gently scalloped bottom edge.
private struct CanopyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let hemLeft = CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.86)
        let hemRight = CGPoint(x: rect.minX + rect.width * 0.95, y: rect.minY + rect.height * 0.86)

        var path = Path()
        path.move(to: hemLeft)
        path.addQuadCurve(
            to: hemRight,
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.75)
        )
        // Scalloped hem back to the left: three shallow dips.
        let dip = rect.height * 0.14
        for (from, to) in [(0.95, 0.65), (0.65, 0.35), (0.35, 0.05)] {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + rect.width * to, y: hemLeft.y),
                control: CGPoint(x: rect.minX + rect.width * (from + to) / 2, y: hemLeft.y + dip)
            )
        }
        path.closeSubpath()
        return path
    }
}

/// Two curved panel seams from the crown down to the hem.
private struct CanopySeamsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let crown = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04)
        for hemX in [0.30, 0.70] {
            path.move(to: crown)
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + rect.width * hemX, y: rect.minY + rect.height * 0.86),
                control: CGPoint(x: rect.minX + rect.width * (0.5 + (hemX - 0.5) * 0.8), y: rect.minY + rect.height * 0.3)
            )
        }
        return path
    }
}

/// Suspension lines from the hem down to the hold point at bottom center.
private struct CanopyStringsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let anchor = CGPoint(x: rect.midX, y: rect.maxY)
        for hemX in [0.08, 0.5, 0.92] {
            path.move(to: CGPoint(x: rect.minX + rect.width * hemX, y: rect.minY + rect.height * 0.5))
            path.addLine(to: anchor)
        }
        return path
    }
}

/// The strings: one curve from under each balloon down to a shared hold point
/// at the bottom center of the bunch.
private struct BalloonStringsShape: Shape {
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

#Preview("Stunts mid-flight") {
    let stage = CGSize(width: 393, height: 700)
    VStack(spacing: 0) {
        ForEach(Array(SpatchStunt.allCases.enumerated()), id: \.offset) { _, stunt in
            ZStack(alignment: .topLeading) {
                Color.gray.opacity(0.15)
                SpatchStuntPerformanceView(
                    run: SpatchStuntRun(id: UUID(), stunt: stunt, isReversed: false, lane: 0.5),
                    stageSize: CGSize(width: stage.width, height: stage.height / 4),
                    characterSize: CGSize(width: 48, height: 101),
                    frozenAtProgress: 0.5
                )
            }
            .frame(width: stage.width, height: stage.height / 4)
            .clipped()
        }
    }
}
