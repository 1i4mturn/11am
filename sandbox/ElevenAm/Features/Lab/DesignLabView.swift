import AppKit
import SwiftUI

/// Tune the vellum live. Every change applies to the whole app; "Copy values" hands them back to us.
struct DesignLabView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: "design lab", subtitle: "Set the look you want, then copy the values into your feedback.") {
                    HStack(spacing: 8) {
                        Button("Reset") { theme.reset() }
                            .buttonStyle(.vellumSecondary)
                        Button(copied ? "Copied" : "Copy Values") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(theme.exportJSON(), forType: .string)
                            copied = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                copied = false
                            }
                        }
                        .buttonStyle(.vellumPrimary)
                    }
                }

                // Side by side when there's room, stacked when the window is narrow.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 22) {
                        controls
                            .frame(width: 270)
                        preview
                            .frame(minWidth: 420, maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        preview
                        controls
                    }
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabSlider(title: "Paper tone", detail: "Pure white → warm vellum", value: $theme.values.paperTone)
            LabSlider(title: "Frost", detail: "Clear glass → white paper", value: $theme.values.frost)
            LabSlider(title: "Clarity", detail: "All frosted → see the desktop through it", value: $theme.values.clarity)
            LabSlider(title: "Grain", detail: "Smooth → fibrous", value: $theme.values.grain)
            LabSlider(title: "Depth", detail: "Flat → layered", value: $theme.values.depth)
            LabSlider(title: "Ink softness", detail: "Black → graphite", value: $theme.values.inkSoftness)
            LabSlider(title: "Motion", detail: "Still → lively (Reduce Motion always wins)", value: $theme.values.motion)
            VStack(alignment: .leading, spacing: 4) {
                Text("Corner radius: \(Int(theme.values.cornerRadius))")
                    .font(.system(size: 12.5, weight: .medium))
                Slider(value: $theme.values.cornerRadius, in: 6...30)
            }
            Picker("Display face", selection: $theme.values.displayFace) {
                ForEach(DisplayFace.allCases) { face in Text(face.title).tag(face) }
            }
            Picker("Backdrop", selection: $theme.values.backdrop) {
                ForEach(BackdropMaterial.allCases) { material in Text(material.title).tag(material) }
            }
            Picker("Appearance", selection: $theme.values.appearance) {
                ForEach(Appearance.allCases) { appearance in Text(appearance.title).tag(appearance) }
            }
            .pickerStyle(.segmented)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(theme.ink(scheme))
    }

    /// A stack of three vellum sheets over busy shapes, to judge blur, tint and grain together.
    private var preview: some View {
        ZStack {
            // Something busy underneath so the frost has something to blur.
            Canvas { context, size in
                let shades: [Double] = [0.15, 0.55, 0.85, 0.35, 0.7]
                for index in 0..<14 {
                    let x = Double((index * 97) % 100) / 100 * size.width
                    let y = Double((index * 53) % 100) / 100 * size.height
                    let d = 60 + Double((index * 37) % 90)
                    let rect = CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)
                    context.fill(Path(ellipseIn: rect), with: .color(Color(white: shades[index % shades.count])))
                }
                context.draw(Text("vellum").font(.system(size: 120, weight: .black)).foregroundColor(Color(white: 0.2)), at: CGPoint(x: size.width / 2, y: size.height / 2))
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Layer 1 · sheet")
                Text("Text printed on vellum.")
                    .font(theme.display(26))
                    .foregroundStyle(theme.ink(scheme))
            }
            .padding(20)
            .frame(width: 260, height: 140, alignment: .topLeading)
            .vellum(level: 1, blending: .withinWindow)
            .offset(x: -80, y: -80)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Layer 2 · main sheet")
                Text("Marc drafted three replies in your voice. Two need a quick look.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.ink(scheme))
                HStack(spacing: 6) {
                    ModelBadge(label: "Apple on-device", isLocal: true)
                    Chip(text: "3 sources")
                }
            }
            .padding(20)
            .frame(width: 260, height: 150, alignment: .topLeading)
            .vellum(level: 2, blending: .withinWindow)
            .offset(x: 30, y: 20)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Layer 3 · card")
                Text("14.2 mo")
                    .font(theme.display(34))
                    .foregroundStyle(theme.ink(scheme))
                Text("runway")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            .padding(18)
            .frame(width: 180, height: 120, alignment: .topLeading)
            .vellum(level: 3)
            .offset(x: 120, y: 120)
        }
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
    }
}

private struct LabSlider: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var title: String
    var detail: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            Slider(value: $value, in: 0...1)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
    }
}
