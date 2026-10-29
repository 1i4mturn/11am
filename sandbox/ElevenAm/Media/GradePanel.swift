import CoreImage
import SwiftUI
import UniformTypeIdentifiers

/// The colour controls shared by Photo and Video: looks, light, colour, wheels, colour by colour, curve, detail, effects, LUT.
struct GradePanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var looks: LookLibrary
    @Environment(\.colorScheme) private var scheme
    @Binding var settings: GradeSettings
    /// Picture used for Auto; nil hides the button.
    var autoSource: (() -> CIImage?)?
    @State private var band = 0
    @State private var importingLUT = false
    @State private var naming = false
    @State private var lookName = ""
    @State private var open: Set<String> = ["Looks", "Light", "Colour"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let autoSource {
                    Button("Auto") {
                        if let image = autoSource() {
                            withAnimation(theme.spring) { settings = GradeAuto.settings(for: image, keeping: settings) }
                        }
                    }
                    .buttonStyle(.vellumPrimary)
                    .help("Let Core Image suggest exposure, curve and colour, then fine-tune")
                }
                Button("Copy") { GradeClipboard.settings = settings }
                    .buttonStyle(.vellumSecondary)
                Button("Paste") { if let copied = GradeClipboard.settings { settings = copied } }
                    .buttonStyle(.vellumSecondary)
                Button("Reset") { withAnimation(theme.spring) { settings = GradeSettings() } }
                    .buttonStyle(.vellumSecondary)
            }

            section("Looks") {
                FlowLayout(spacing: 6) {
                    ForEach(looks.all) { look in
                        Button(look.name) { withAnimation(theme.spring) { settings = look.settings } }
                            .buttonStyle(.vellumSecondary)
                            .contextMenu {
                                if !look.builtIn {
                                    Button("Delete look", role: .destructive) { looks.delete(look) }
                                }
                            }
                    }
                    Button {
                        lookName = ""
                        naming = true
                    } label: {
                        Label("Save look", systemImage: "plus")
                    }
                    .buttonStyle(.vellumPrimary)
                    .popover(isPresented: $naming, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name this look").font(.system(size: 12.5, weight: .semibold))
                            TextField("Golden hour", text: $lookName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                                .onSubmit(saveLook)
                            Button("Save", action: saveLook)
                                .buttonStyle(.vellumPrimary)
                        }
                        .padding(14)
                    }
                }
            }

            section("Light") {
                GradeSlider(title: "Exposure", value: $settings.exposure, range: -3...3, format: "%+.2f")
                GradeSlider(title: "Contrast", value: $settings.contrast)
                GradeSlider(title: "Highlights", value: $settings.highlights)
                GradeSlider(title: "Shadows", value: $settings.shadows)
            }

            section("Colour") {
                GradeSlider(title: "Temperature", value: $settings.temperature, low: "Cool", high: "Warm")
                GradeSlider(title: "Tint", value: $settings.tint, low: "Green", high: "Magenta")
                GradeSlider(title: "Vibrance", value: $settings.vibrance)
                GradeSlider(title: "Saturation", value: $settings.saturation)
            }

            section("Wheels") {
                HStack(alignment: .top, spacing: 8) {
                    WheelColumn(title: "Shadows", wheel: $settings.lift)
                    WheelColumn(title: "Midtones", wheel: $settings.gamma)
                    WheelColumn(title: "Highlights", wheel: $settings.gain)
                }
            }

            section("Colour by colour") {
                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { index in
                        Button {
                            band = index
                        } label: {
                            Circle()
                                .fill(Color(hue: GradeSettings.bandHues[index] / 360, saturation: 0.75, brightness: 0.9))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(theme.ink(scheme), lineWidth: band == index ? 2 : 0))
                                .overlay(alignment: .topTrailing) {
                                    if !settings.hsl[index].isNeutral {
                                        Circle().fill(theme.ink(scheme)).frame(width: 5, height: 5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(GradeSettings.bandNames[index])
                    }
                }
                Text(GradeSettings.bandNames[band])
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.inkSecondary(scheme))
                GradeSlider(title: "Hue", value: $settings.hsl[band].hue)
                GradeSlider(title: "Saturation", value: $settings.hsl[band].saturation)
                GradeSlider(title: "Luminance", value: $settings.hsl[band].luminance)
            }

            section("Curve") {
                CurveEditor(points: $settings.curve)
                    .frame(height: 170)
            }

            section("Detail") {
                GradeSlider(title: "Sharpen", value: $settings.sharpen, range: 0...1)
                GradeSlider(title: "Noise reduction", value: $settings.noiseReduction, range: 0...1)
            }

            section("Effects") {
                GradeSlider(title: "Fade", value: $settings.fade, range: 0...1)
                GradeSlider(title: "Vignette", value: $settings.vignette, range: 0...1)
                GradeSlider(title: "Grain", value: $settings.grain, range: 0...1)
            }

            section("LUT") {
                HStack(spacing: 6) {
                    Picker("LUT", selection: $settings.lutName) {
                        Text("None").tag(String?.none)
                        ForEach(looks.luts, id: \.self) { name in Text(name).tag(String?.some(name)) }
                    }
                    .labelsHidden()
                    Button("Import .cube…") { importingLUT = true }
                        .buttonStyle(.vellumSecondary)
                }
                if settings.lutName != nil {
                    GradeSlider(title: "Amount", value: $settings.lutAmount, range: 0...1)
                }
                Text("Film emulations and camera LUTs from Resolve, Premiere or a LUT pack.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
        .fileImporter(isPresented: $importingLUT, allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data, .data]) { result in
            if case .success(let url) = result, let name = looks.importLUT(from: url) {
                settings.lutName = name
            }
        }
    }

    private func saveLook() {
        looks.save(settings, as: lookName)
        naming = false
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let isOpen = open.contains(title)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(theme.spring) {
                    if isOpen { open.remove(title) } else { open.insert(title) }
                }
            } label: {
                HStack {
                    SectionLabel(text: title)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                VStack(alignment: .leading, spacing: 8, content: content)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5).offset(y: 4) }
    }
}

/// A labelled slider with its value; double-click the label to reset.
struct GradeSlider: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -1...1
    var format = "%+.2f"
    var low: String?
    var high: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink(scheme))
                    .onTapGesture(count: 2) { value = range.contains(0) ? 0 : range.lowerBound }
                    .help("Double-click to reset")
                Spacer()
                Text(String(format: range.lowerBound >= 0 ? "%.2f" : format, value))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(abs(value) > 0.001 ? theme.ink(scheme) : theme.inkTertiary(scheme))
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
            if let low, let high {
                HStack {
                    Text(low)
                    Spacer()
                    Text(high)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
    }
}

private struct WheelColumn: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var title: String
    @Binding var wheel: ColorWheel

    var body: some View {
        VStack(spacing: 6) {
            ColorWheelControl(wheel: $wheel)
                .frame(width: 76, height: 76)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.inkSecondary(scheme))
            Slider(value: $wheel.luma, in: -1...1)
                .controlSize(.mini)
                .help("Brightness")
        }
        .frame(maxWidth: .infinity)
    }
}

/// Drag the puck towards a colour; the further out, the stronger. Double-click to reset.
struct ColorWheelControl: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @Binding var wheel: ColorWheel

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let angle = wheel.hue * .pi / 180
            let puck = CGPoint(x: center.x + cos(angle) * wheel.amount * radius, y: center.y - sin(angle) * wheel.amount * radius)
            ZStack {
                Circle()
                    .fill(AngularGradient(
                        colors: stride(from: 0.0, through: 360, by: 30).map { Color(hue: $0 / 360, saturation: 0.7, brightness: 0.95) },
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(-360)
                    ))
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.6), Color(white: 0.6).opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle().strokeBorder(theme.edge(scheme), lineWidth: 0.75)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1.5))
                    .frame(width: 11, height: 11)
                    .position(puck)
            }
            .frame(width: size, height: size)
            .position(center)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let dx = drag.location.x - center.x
                let dy = center.y - drag.location.y
                var degrees = atan2(dy, dx) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                wheel.hue = degrees
                wheel.amount = min(1, hypot(dx, dy) / radius)
            })
            .onTapGesture(count: 2) { wheel = ColorWheel() }
        }
        .help("Drag towards a colour. Double-click to reset.")
    }
}

/// Five points you drag to shape brightness. Double-click to reset.
struct CurveEditor: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @Binding var points: [CurvePoint]
    @State private var dragging: Int?

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let curve = ToneCurve(points: points)
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(theme.well(scheme))
                Path { path in
                    for i in 1..<4 {
                        let x = w * CGFloat(i) / 4
                        let y = h * CGFloat(i) / 4
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: h))
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(theme.edge(scheme), lineWidth: 0.5)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: w, y: 0))
                }
                .stroke(theme.edge(scheme), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                Path { path in
                    for step in 0...80 {
                        let x = Double(step) / 80
                        let point = CGPoint(x: w * x, y: h * (1 - min(max(curve.value(x), 0), 1)))
                        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(theme.ink(scheme), lineWidth: 1.5)
                ForEach(points.indices, id: \.self) { index in
                    Circle()
                        .fill(theme.paper(scheme))
                        .overlay(Circle().strokeBorder(theme.ink(scheme), lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                        .position(x: w * points[index].x, y: h * (1 - points[index].y))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if dragging == nil {
                        dragging = points.indices.min { a, b in
                            hypot(w * points[a].x - drag.startLocation.x, h * (1 - points[a].y) - drag.startLocation.y)
                                < hypot(w * points[b].x - drag.startLocation.x, h * (1 - points[b].y) - drag.startLocation.y)
                        }
                    }
                    guard let index = dragging else { return }
                    var x = min(max(drag.location.x / w, 0), 1)
                    let y = min(max(1 - drag.location.y / h, 0), 1)
                    // End points slide only up and down; middle points stay between their neighbours.
                    if index == 0 { x = 0 }
                    else if index == points.count - 1 { x = 1 }
                    else { x = min(max(x, points[index - 1].x + 0.02), points[index + 1].x - 0.02) }
                    points[index] = CurvePoint(x: x, y: y)
                }
                .onEnded { _ in dragging = nil }
            )
            .onTapGesture(count: 2) { points = GradeSettings.identityCurve }
        }
        .help("Drag a point to shape brightness. Double-click to reset.")
    }
}
