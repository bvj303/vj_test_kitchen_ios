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
