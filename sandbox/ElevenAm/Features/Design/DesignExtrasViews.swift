import SwiftUI

/// A design at any size: pixels for screens, millimetres or inches for print (at 300 dots an inch).
struct CustomSizeSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var studio: DesignStudio
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var unit: PrintUnit = .millimetres
    @State private var width = "210"
    @State private var height = "297"
    @State private var template: CanvasTemplate = .blank

    private var pixels: (Double, Double)? {
        guard let w = Double(width.replacingOccurrences(of: ",", with: ".")), let h = Double(height.replacingOccurrences(of: ",", with: ".")), w > 0, h > 0 else { return nil }
        let size = (unit.pixels(w), unit.pixels(h))
        return size.0 <= 12_000 && size.1 <= 12_000 ? size : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Custom size")
                .font(theme.display(20))
                .foregroundStyle(theme.ink(scheme))
            HStack(spacing: 8) {
                TextField("Width", text: $width).frame(width: 80)
                Text("×").foregroundStyle(theme.inkTertiary(scheme))
                TextField("Height", text: $height).frame(width: 80)
                Picker("", selection: $unit) {
                    ForEach(PrintUnit.allCases) { unit in Text(unit.title).tag(unit) }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: unit) { old, new in convert(from: old, to: new) }
            }
            .textFieldStyle(.roundedBorder)
            Menu("Paper sizes") {
                ForEach(PrintUnit.paper.indices, id: \.self) { index in
                    let paper = PrintUnit.paper[index]
                    Button("\(paper.name) · \(number(paper.width)) × \(number(paper.height)) mm") {
                        unit = .millimetres
                        width = number(paper.width)
                        height = number(paper.height)
                    }
                }
            }
            .fixedSize()
            Text(pixels.map { "\(Int($0.0)) × \(Int($0.1)) pixels" + (unit == .pixels ? "" : ", ready to print at 300 dots an inch") } ?? "Type a width and height (up to 12,000 pixels each).")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkTertiary(scheme))
            Picker("Start from", selection: $template) {
                ForEach(CanvasTemplate.allCases) { item in Text(item.title).tag(item) }
            }
            .fixedSize()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Make it") {
                    guard let size = pixels else { return }
                    let name = unit == .pixels ? "\(Int(size.0)) × \(Int(size.1))" : "\(width) × \(height) \(unit.rawValue)"
                    studio.create(template, preset: CanvasPreset(id: "custom", name: name, size: CanvasSize(width: size.0, height: size.1), group: "Custom"))
                    dismiss()
                }
                .buttonStyle(.vellumPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(pixels == nil)
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Keeps the same size when the unit changes.
    private func convert(from old: PrintUnit, to new: PrintUnit) {
        guard let w = Double(width), let h = Double(height) else { return }
        width = number(new.value(old.pixels(w)))
        height = number(new.value(old.pixels(h)))
    }
}
