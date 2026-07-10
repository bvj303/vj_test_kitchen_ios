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
        LinearGradient(
            colors: dark
                ? [Color(red: 0.30, green: 0.24, blue: 0.16), Color(red: 0.18, green: 0.14, blue: 0.09)]
                : [Color(red: 0.95, green: 0.68, blue: 0.48), Color(red: 0.87, green: 0.46, blue: 0.28)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var spatch: some View {
        VStack(spacing: -8) {
            head
            handle
        }
        .offset(y: -6)
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
