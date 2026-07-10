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
        VStack(spacing: -6) {
            head
            handle
        }
        .offset(y: -10)
    }

    private var sage: Color {
        dark ? Color(red: 0.541, green: 0.659, blue: 0.463) : Color(red: 0.431, green: 0.545, blue: 0.357)
    }

    private var head: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 210, style: .continuous)
                .fill(sage)
                .frame(width: 500, height: 560)
            VStack(spacing: 34) {
                eyes
                mouth
            }
            .offset(y: -30)
            blush
        }
    }

    private var eyes: some View {
        HStack(spacing: 62) {
            eye
            eye
        }
    }

    private var eye: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
            Circle().fill(Color.black).frame(width: 54, height: 54)
                .offset(x: 8, y: 6)
        }
    }

    private var mouth: some View {
        SmilePath()
            .stroke(Color.black, style: StrokeStyle(lineWidth: 24, lineCap: .round))
            .frame(width: 200, height: 60)
    }

    private var blush: some View {
        HStack(spacing: 250) {
            Capsule().fill(Color.orange.opacity(0.5)).frame(width: 68, height: 32)
            Capsule().fill(Color.orange.opacity(0.5)).frame(width: 68, height: 32)
        }
        .offset(y: 26)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 55, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.62, green: 0.44, blue: 0.27), Color(red: 0.46, green: 0.31, blue: 0.17)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 130, height: 280)
    }
}

private struct SmilePath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY))
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
