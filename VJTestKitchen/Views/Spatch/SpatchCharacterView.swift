import SwiftUI

/// Spatch: the app's mascot — a sage-green silicone spatula with a wooden
/// handle and reactive googly eyes. Pure vector SwiftUI (no image assets),
/// shared verbatim between iOS and macOS. Eyes drift on their own when idle,
/// follow a drag within a small radius (the "reactive googly eyes" bit — like
/// the real toy, they track whatever's nudging them), and the whole head gives
/// a little spring wobble on release, like bopping a googly-eye toy.
struct SpatchCharacterView: View {
    var mood: SpatchMood = .idle

    @State private var isBlinking = false
    @State private var idleLookOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var wobble: Angle = .zero
    @State private var isDragging = false

    /// How far the pupils can travel from center, in points.
    private let pupilTravel: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            VStack(spacing: 0) {
                head(width: width, height: height * 0.72)
                handle(width: width * 0.22, height: height * 0.30)
            }
            .frame(width: width, height: height)
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

    private func clamp(_ translation: CGSize) -> CGSize {
        let distance = (translation.width * translation.width + translation.height * translation.height).squareRoot()
        guard distance > pupilTravel else { return translation }
        let scale = pupilTravel / distance
        return CGSize(width: translation.width * scale, height: translation.height * scale)
    }

    private var pupilOffset: CGSize {
        isDragging ? dragOffset : idleLookOffset
    }

    // MARK: - Head

    private func head(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.42, style: .continuous)
                .fill(Color.brandSage)
            VStack(spacing: height * 0.06) {
                eyes(width: width, height: height)
                mouth(width: width, height: height)
            }
            .padding(.top, height * 0.2)
            blush(width: width, height: height)
        }
        .frame(width: width, height: height)
    }

    private func eyes(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: width * 0.16) {
            eye(size: width * 0.24)
            eye(size: width * 0.24, isRightEye: true)
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
                Circle()
                    .fill(Color.black)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .offset(pupilOffset)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(y: isBlinking ? 0.15 : 1, anchor: .center)
    }

    private func mouth(width: CGFloat, height: CGFloat) -> some View {
        MouthShape(curve: mood.mouthCurve, isOpen: mood.mouthIsOpen)
            .fill(Color.black.opacity(mood.mouthIsOpen ? 0.75 : 1))
            .frame(width: width * 0.42, height: height * 0.18)
            .padding(.top, height * 0.08)
    }

    private func blush(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: width * 0.4) {
            Capsule().fill(Color.brandSaffron.opacity(0.4)).frame(width: width * 0.14, height: width * 0.07)
            Capsule().fill(Color.brandSaffron.opacity(0.4)).frame(width: width * 0.14, height: width * 0.07)
        }
        .offset(y: height * 0.16)
    }

    // MARK: - Handle

    private func handle(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: width * 0.3, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.62, green: 0.44, blue: 0.27), Color(red: 0.5, green: 0.34, blue: 0.2)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: width, height: height)
    }
}

/// A closed smile/frown curve, or an open laugh oval when `isOpen` — driven by
/// `SpatchMood.mouthCurve` (-1 frown ... +1 big smile).
private struct MouthShape: Shape {
    var curve: CGFloat
    var isOpen: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isOpen {
            path.addEllipse(in: rect.insetBy(dx: rect.width * 0.12, dy: 0))
            return path
        }
        let start = CGPoint(x: rect.minX, y: rect.midY)
        let end = CGPoint(x: rect.maxX, y: rect.midY)
        let control = CGPoint(x: rect.midX, y: rect.midY + rect.height * curve)
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path.strokedPath(StrokeStyle(lineWidth: max(2, rect.height * 0.18), lineCap: .round))
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
