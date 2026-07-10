#!/usr/bin/env swift
import SwiftUI
import AppKit

// Renders the app icon (Spatch, the app's mascot) to the two 1024x1024 PNGs
// used by AppIcon.appiconset, since there's no image-generation tool in this
// pipeline — the icon is vector SwiftUI art rasterized via ImageRenderer.
// Usage: swift scripts/render_app_icon.swift <light-out.png> <dark-out.png>
// Re-run after any tweak to SpatchIconArt below to regenerate both variants.

struct SpatchIconArt: View {
    var dark: Bool

    var body: some View {
        ZStack {
            backgroundGradient
            spatch
        }
        .frame(width: 1024, height: 1024)
    }

    private var backgroundGradient: some View {
        ZStack {
            // Warm kitchen cream (light) / deep slate-teal (dark) — calmer
            // than the old flat terracotta, and it lets the teal mascot carry
            // the color.
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.135, green: 0.20, blue: 0.195), Color(red: 0.075, green: 0.115, blue: 0.11)]
                    : [Color(red: 0.984, green: 0.953, blue: 0.898), Color(red: 0.945, green: 0.871, blue: 0.755)],
                startPoint: .top, endPoint: .bottom
            )
            // A soft halo behind Spatch so he pops off the background.
            RadialGradient(
                colors: dark
                    ? [Color.white.opacity(0.10), .clear]
                    : [Color.white.opacity(0.75), Color.white.opacity(0)],
                center: .init(x: 0.5, y: 0.42),
                startRadius: 40, endRadius: 430
            )
            sparkles
        }
    }

    /// A few saffron accent sparkles (the app's "suggestion" ✦ motif) so the
    /// icon reads as playful rather than a character on an empty field.
    private var sparkles: some View {
        let saffron = dark ? Color(red: 0.94, green: 0.70, blue: 0.33) : Color(red: 0.91, green: 0.63, blue: 0.23)
        return ZStack {
            SparkleShape().fill(saffron.opacity(0.95)).frame(width: 92, height: 92).offset(x: -330, y: -300)
            SparkleShape().fill(saffron.opacity(0.75)).frame(width: 56, height: 56).offset(x: -252, y: -180)
            SparkleShape().fill(saffron.opacity(0.9)).frame(width: 74, height: 74).offset(x: 330, y: -238)
            SparkleShape().fill(saffron.opacity(0.7)).frame(width: 52, height: 52).offset(x: -318, y: 300)
        }
    }

    private var spatch: some View {
        ZStack {
            armAndSpoon
            VStack(spacing: -8) {
                head
                handle
            }
        }
        .rotationEffect(.degrees(-6))
        .scaleEffect(0.8)
        .offset(y: -14)
        .shadow(color: .black.opacity(dark ? 0.45 : 0.22), radius: 26, y: 18)
    }

    /// The wire arm + measuring spoon from the character view, scaled for the
    /// icon — emerges from behind the handle, spoon held up beside the paddle.
    private var armAndSpoon: some View {
        let wire = dark ? Color(red: 0.65, green: 0.67, blue: 0.68) : Color(red: 0.56, green: 0.57, blue: 0.59)
        let bowl = dark ? Color(red: 0.76, green: 0.78, blue: 0.79) : Color(red: 0.71, green: 0.72, blue: 0.74)
        return ZStack {
            IconArmPath()
                .stroke(wire, style: StrokeStyle(lineWidth: 19, lineCap: .round))
                .frame(width: 300, height: 250)
                .offset(x: 190, y: 250)
            VStack(spacing: -12) {
                ZStack {
                    Ellipse().fill(
                        LinearGradient(colors: [bowl, wire], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    Ellipse().fill(Color.white.opacity(0.35)).frame(width: 30, height: 24).offset(x: -14, y: -22)
                }
                .frame(width: 84, height: 100)
                Capsule().fill(wire).frame(width: 19, height: 95)
            }
            .offset(x: 342, y: 120)
        }
    }

    // Mirrors SpatchCharacterView's teal-silicone palette (the mascot's own
    // colors, independent of the brand palette).
    private var teal: Color {
        dark ? Color(red: 0.325, green: 0.737, blue: 0.690) : Color(red: 0.310, green: 0.690, blue: 0.647)
    }
    private var tealDeep: Color {
        dark ? Color(red: 0.259, green: 0.616, blue: 0.573) : Color(red: 0.243, green: 0.584, blue: 0.545)
    }
    private var blushPink: Color { Color(red: 0.941, green: 0.549, blue: 0.549) }

    private var head: some View {
        ZStack {
            IconHeadShape()
                .fill(LinearGradient(colors: [teal, tealDeep], startPoint: .top, endPoint: .bottom))
                .frame(width: 520, height: 540)
            // Silicone sheen, top-leading like the character view.
            Ellipse()
                .fill(Color.white.opacity(0.14))
                .frame(width: 190, height: 80)
                .rotationEffect(.degrees(-18))
                .offset(x: -115, y: -195)
            VStack(spacing: 30) {
                eyes
                mouth
            }
            .offset(y: -16)
            blush
        }
    }

    private var eyes: some View {
        HStack(spacing: 14) {
            eye
            eye
        }
    }

    private var eye: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 150, height: 150)
                .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 9))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 4)
            ZStack {
                Circle().fill(Color.black).frame(width: 68, height: 68)
                Circle().fill(Color.white.opacity(0.9)).frame(width: 20, height: 20)
                    .offset(x: -14, y: -14)
            }
            .offset(x: 6, y: 6)
        }
    }

    private var mouth: some View {
        ZStack(alignment: .bottom) {
            IconSmileShape()
                .fill(Color.black.opacity(0.85))
            Ellipse()
                .fill(blushPink)
                .frame(width: 110, height: 46)
                .offset(y: 14)
        }
        .frame(width: 175, height: 95)
        .clipShape(IconSmileShape())
    }

    private var blush: some View {
        HStack(spacing: 320) {
            Ellipse().fill(blushPink.opacity(0.65)).frame(width: 74, height: 42)
            Ellipse().fill(blushPink.opacity(0.65)).frame(width: 74, height: 42)
        }
        .offset(y: 60)
    }

    private var handle: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.753, green: 0.541, blue: 0.322), Color(red: 0.612, green: 0.424, blue: 0.235)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            Circle()
                .fill(Color.black.opacity(0.28))
                .frame(width: 44, height: 44)
                .padding(.bottom, 42)
        }
        .frame(width: 100, height: 300)
    }
}

/// The paddle silhouette from SpatchCharacterView, scaled for the icon: big
/// rounded top slanting gently toward the trailing side, sides tapering to
/// the neck.
private struct IconHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let topLeading = CGPoint(x: rect.minX, y: rect.minY)
        let topTrailing = CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.13)
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

/// A four-point star sparkle, like the app's "Suggested for You" ✦ motif.
private struct SparkleShape: Shape {
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

/// The wire arm for the icon: out from behind the handle, swooping out and up.
private struct IconArmPath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY * 0.86))
        p.addCurve(
            to: CGPoint(x: rect.maxX * 0.77, y: rect.maxY * 0.55),
            control1: CGPoint(x: rect.maxX * 0.5, y: rect.maxY * 1.05),
            control2: CGPoint(x: rect.maxX * 0.82, y: rect.maxY * 0.85)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX * 0.85, y: rect.minY + rect.height * 0.14),
            control: CGPoint(x: rect.maxX * 0.72, y: rect.maxY * 0.28)
        )
        return p
    }
}

/// The open grin from SpatchCharacterView: curved top lip, deep round bottom.
private struct IconSmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 1.9)
        )
        p.closeSubpath()
        return p
    }
}

@MainActor
func renderPNG(dark: Bool, to path: String) {
    let view = SpatchIconArt(dark: dark)
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: 1024, height: 1024)
    renderer.scale = 1
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
MainActor.assumeIsolated {
    renderPNG(dark: false, to: args[1])
    renderPNG(dark: true, to: args[2])
}
