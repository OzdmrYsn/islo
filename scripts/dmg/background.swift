import AppKit
import SwiftUI

// Draws the background of islo.'s disk image window.
// Regenerate with:
//   swiftc -O scripts/dmg/background.swift -o /tmp/islo-dmg-background
//   /tmp/islo-dmg-background scripts/dmg
//   tiffutil -cathidpicheck scripts/dmg/background.png scripts/dmg/background@2x.png -out scripts/dmg/background.tiff
//
// The window is 640 x 470 points with its title bar (see settings.py), so
// 438–448 points of this image show depending on the macOS version; the
// rest is spare gradient, and nothing important sits below y = 420. Icons sit
// at (160, 238) and (480, 238); Finder writes their names below them.
let width: CGFloat = 640, height: CGFloat = 460

struct MiniMark: View {
    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.height / 562
            ZStack(alignment: .topLeading) {
                Capsule().fill(LinearGradient(colors: [Color(red: 0.48, green: 0.7, blue: 1), Color(red: 0.24, green: 0.42, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 250 * s, height: 118 * s)
                Capsule().fill(Color.white).frame(width: 150 * s, height: 390 * s).offset(x: 50 * s, y: 172 * s)
                Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.44, blue: 0.65), Color(red: 1, green: 0.6, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 150 * s, height: 150 * s).offset(x: 283 * s, y: 412 * s)
            }
            .frame(width: 433 * s, height: 562 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct Arrow: View {
    var body: some View {
        ZStack {
            // Soft light under the arrow.
            Capsule().fill(Color(red: 0.45, green: 0.6, blue: 1).opacity(0.35)).frame(width: 150, height: 10).blur(radius: 12)
            HStack(spacing: 7) {
                ForEach(0..<3) { index in
                    Circle().fill(Color.white.opacity(0.18 + Double(index) * 0.14)).frame(width: 4, height: 4)
                }
                Capsule()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.45), Color.white], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 92, height: 2.5)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.leading, -12)
            }
        }
    }
}

/// islo. isn't notarized yet, so macOS asks once on first launch; this says
/// where to click before anyone gets stuck on the warning.
struct FirstLaunchHint: View {
    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.48, green: 0.7, blue: 1), Color(red: 0.24, green: 0.42, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                (Text("İlk açılışta uyarı çıkarsa: ").foregroundColor(.white.opacity(0.6))
                    + Text("Sistem Ayarları › Gizlilik ve Güvenlik › ").foregroundColor(.white.opacity(0.92))
                    + Text("Yine de Aç").foregroundColor(Color(red: 0.62, green: 0.76, blue: 1)).fontWeight(.bold))
                    .font(.system(size: 11, weight: .medium))
                Text("If macOS warns on first launch: System Settings › Privacy & Security › Open Anyway")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        )
    }
}

struct Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.035, blue: 0.047)
            RadialGradient(colors: [Color(red: 0.24, green: 0.42, blue: 1).opacity(0.55), .clear], center: UnitPoint(x: 0.1, y: -0.05), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(red: 1, green: 0.37, blue: 0.62).opacity(0.28), .clear], center: UnitPoint(x: 1.0, y: 1.05), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [Color(red: 0.55, green: 0.4, blue: 1).opacity(0.18), .clear], center: UnitPoint(x: 0.5, y: 0.6), startRadius: 0, endRadius: 260)
            Canvas { context, size in
                var path = Path()
                stride(from: 0, through: size.width, by: 32).forEach { x in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
                stride(from: 0, through: size.height, by: 32).forEach { y in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
                context.stroke(path, with: .color(.white.opacity(0.045)), lineWidth: 0.5)
            }
            .mask(RadialGradient(colors: [.black, .clear], center: UnitPoint(x: 0.5, y: 0.45), startRadius: 40, endRadius: 330))

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    MiniMark().frame(width: 18, height: 22)
                    Text("islo.").font(.system(size: 19, weight: .bold, design: .rounded))
                }
                .padding(.top, 30)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Sürükle, ").font(.system(size: 30, weight: .bold)).tracking(-0.8)
                    Text("başla.").font(.system(size: 33, weight: .regular, design: .serif)).italic()
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.62, green: 0.76, blue: 1), Color(red: 0.75, green: 0.64, blue: 1), Color(red: 1, green: 0.62, blue: 0.84)], startPoint: .leading, endPoint: .trailing))
                }
                .padding(.top, 14)
                Text("islo.'yu Uygulamalar klasörüne bırak  ·  Drag islo. into Applications")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 8)
                Spacer()
                FirstLaunchHint()
                    .padding(.bottom, 44)
            }
            .foregroundStyle(.white)

            Arrow().position(x: 320, y: 238)

            // Name tags under the icons. Finder writes the names in black
            // in Light Mode and white in Dark Mode; this middle grey keeps
            // both readable (about 4.5:1 either way).
            ForEach([(160.0, 76.0), (480.0, 118.0)], id: \.0) { x, tagWidth in
                Capsule()
                    .fill(Color(red: 0.46, green: 0.46, blue: 0.5))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                    .frame(width: tagWidth, height: 22)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    .position(x: x, y: 312)
            }
        }
        .frame(width: width, height: height)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor func write(scale: CGFloat, to path: String) {
    let renderer = ImageRenderer(content: Background())
    renderer.scale = scale
    guard let cg = renderer.cgImage else { return }
    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = NSSize(width: width, height: height)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}
MainActor.assumeIsolated {
    write(scale: 1, to: CommandLine.arguments[1] + "/background.png")
    write(scale: 2, to: CommandLine.arguments[1] + "/background@2x.png")
}
print("drawn")
