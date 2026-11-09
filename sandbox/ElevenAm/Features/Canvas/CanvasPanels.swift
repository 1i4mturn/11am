import AppKit
import SwiftUI

/// The fonts offered in the inspector: the system's, plus families every Mac has.
enum CanvasFonts {
    static let families = ["System", "New York", "Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Georgia", "Didot", "Baskerville", "Menlo", "Rockwell", "Optima"]
}

/// Add text, shapes, pictures and QR codes; undo; arrange.
struct CanvasToolbar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var controller: CanvasController
    var brand: CanvasBrand
    var addPicture: () -> Void
    @State private var askingQR = false
    @State private var qrText = "https://"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ToolButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)") { controller.undo() }
                    .disabled(!controller.canUndo)
                ToolButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { controller.redo() }
                    .disabled(!controller.canRedo)
                divider
                Menu {
                    Button("Heading") { controller.addText("Add a heading", heading: true, brand: brand) }
                    Button("Body text") { controller.addText("Add a little text", heading: false, brand: brand) }
                } label: {
                    Label("Text", systemImage: "textformat")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .padding(.horizontal, 4)
                Menu {
                    ForEach(ShapeKind.allCases) { kind in
                        Button(kind.title) { controller.addShape(kind, brand: brand) }
                    }
                } label: {
                    Label("Shape", systemImage: "square.on.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .padding(.horizontal, 4)
                ToolButton(symbol: "photo", help: "Add a picture (or drop one on the canvas)", action: addPicture)
                Menu {
                    ForEach(PhotoGrid.allCases) { grid in
                        Button(grid.title) { controller.addFrames(grid, fill: brand.soft) }
                    }
                } label: {
                    Label("Frames", systemImage: "rectangle.split.2x2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .padding(.horizontal, 4)
                .help("Picture frames: drop a picture on one to fill it")
                Menu {
                    if controller.selectedChart != nil {
                        Section("This chart") {
                            ForEach(CanvasChartKind.allCases) { kind in
                                Button("Show as \(kind.title.lowercased())") { controller.redrawChart { $0.kind = kind } }
                            }
                            if controller.selectedChart?.link != nil {
                                Button("Refresh from Sheets") { controller.refreshCharts { sheets.workbook(named: $0) } }
                            }
                        }
                    }
                    Section("From Sheets") {
                        ForEach(sheets.entries) { entry in
                            Menu(entry.name) {
                                ForEach(sheets.workbook(named: entry.name)?.sheets.map(\.name) ?? [], id: \.self) { name in
                                    Button(name) { addChart(workbook: entry.name, sheet: name) }
                                }
                            }
                        }
                    }
                    Button("A sample chart") {
                        controller.addChart(CanvasChart(kind: .columns, points: [ChartPoint(label: "Jul", value: 12), ChartPoint(label: "Aug", value: 19),
                                                                                ChartPoint(label: "Sep", value: 31), ChartPoint(label: "Oct", value: 48)],
                                                        color: brand.soft, accent: brand.accent, ink: brand.primary, font: brand.bodyFont))
                    }
                } label: {
                    Label("Chart", systemImage: "chart.bar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .padding(.horizontal, 4)
                .help("A chart from a sheet in George's Sheets; it stays linked")
                ToolButton(symbol: "qrcode", help: "Add a QR code") { askingQR = true }
                    .popover(isPresented: $askingQR, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("QR code for").font(.system(size: 12.5, weight: .semibold))
                            TextField("A link or any text", text: $qrText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                                .onSubmit(addQR)
                            HStack {
                                Spacer()
                                Button("Add", action: addQR).buttonStyle(.vellumPrimary)
                            }
                        }
                        .padding(14)
                    }
                divider
                Menu {
                    Section("Align") {
                        ForEach(AlignEdge.allCases) { edge in Button(edge.title) { controller.align(edge) } }
                    }
                    Section("Distribute") {
                        Button("Across") { controller.distribute(horizontally: true) }
                        Button("Down") { controller.distribute(horizontally: false) }
                    }
                } label: {
                    Image(systemName: "align.horizontal.center")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 30, height: 24)
                .help("Align and distribute (one layer aligns to the page)")
                .disabled(controller.selection.isEmpty)
                Menu {
                    Button("Bring to front") { controller.reorder(.front) }
                    Button("Bring forward") { controller.reorder(.forward) }
                    Button("Send backward") { controller.reorder(.backward) }
                    Button("Send to back") { controller.reorder(.back) }
                } label: {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 30, height: 24)
                .help("Layer order")
                .disabled(controller.selection.isEmpty)
                ToolButton(symbol: "rectangle.3.group", help: "Group (⌘G)") { controller.group() }
                    .disabled(controller.selection.count < 2)
                ToolButton(symbol: "plus.square.on.square", help: "Duplicate (⌘D)") { controller.duplicate() }
                    .disabled(controller.selection.isEmpty)
                ToolButton(symbol: controller.selectedLayers.allSatisfy(\.locked) && !controller.selection.isEmpty ? "lock" : "lock.open",
                           help: "Lock in place (⌘L)", on: !controller.selection.isEmpty && controller.selectedLayers.allSatisfy(\.locked)) { controller.toggleLock() }
                    .disabled(controller.selection.isEmpty)
                ToolButton(symbol: "trash", help: "Delete (⌫)") { controller.delete() }
                    .disabled(controller.selection.isEmpty)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)) }
        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5) }
    }

    private var divider: some View {
        Rectangle().fill(theme.edge(scheme)).frame(width: 1, height: 16).padding(.horizontal, 4)
    }

    private func addChart(workbook name: String, sheet: String) {
        guard let book = sheets.workbook(named: name), let guess = DeckCharts.suggest(book, sheet: sheet) else { return }
        let link = ChartLink(workbook: book.name, sheet: sheet, labels: guess.labels, values: guess.values, updated: Date())
        guard let points = DeckCharts.points(link, in: book), !points.isEmpty else { return }
        controller.addChart(CanvasChart(kind: points.count > 7 ? .bars : .columns, points: points, link: link,
                                        color: brand.soft, accent: brand.accent, ink: brand.primary, font: brand.bodyFont))
    }

    private func addQR() {
        let text = qrText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text != "https://" else { return }
        controller.addQR(text)
        askingQR = false
    }
}

/// Everything about the selection (or the page, when nothing is selected).
struct CanvasInspector: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var controller: CanvasController
    var brand: CanvasBrand
    var removeBackground: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if controller.selection.isEmpty {
                    pageSection
                } else {
                    if let layer = controller.single {
                        geometrySection(layer)
                        if let chart = controller.selectedChart { chartSection(chart) }
                        if let style = layer.textStyle { textSection(style) }
                        if case .image(_, let fit) = layer.content { imageSection(fit) }
                        appearanceSection(layer)
                    } else if let chart = controller.selectedChart {
                        Text("Chart")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.ink(scheme))
                        chartSection(chart)
                    } else {
                        Text("\(controller.selection.count) layers selected")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.ink(scheme))
                        colourRow("Fill", current: controller.selectedLayers.first?.fill.firstColor) { color in controller.update { $0.fill = .solid(color) } }
                    }
                }
                layersSection
            }
            .padding(12)
        }
    }

    private var swatches: [CanvasColor] {
        var colours = [brand.primary, brand.accent, brand.paper, brand.soft, .white, .black]
        let extras = ["#2463A6", "#2E7D4F", "#C0392B", "#E9C46A", "#8E6CC0", "#5C5C5C"].compactMap { CanvasColor(hex: $0) }
        colours += extras
        return colours
    }

    private func colourRow(_ title: String, current: CanvasColor?, allowsNone: Bool = false, apply: @escaping (CanvasColor) -> Void, clear: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: 7), alignment: .leading, spacing: 6) {
                if let clear {
                    Button(action: clear) {
                        ZStack {
                            Circle().strokeBorder(theme.edge(scheme), lineWidth: 1)
                            Rectangle().fill(Color.red.opacity(0.7)).frame(width: 1.5, height: 22).rotationEffect(.degrees(45))
                        }
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("None")
                }
                ForEach(swatches, id: \.self) { color in
                    Button { apply(color) } label: {
                        Circle()
                            .fill(color.color)
                            .overlay { Circle().strokeBorder(current.map { $0.hex == color.hex } == true ? theme.ink(scheme) : theme.edge(scheme), lineWidth: current.map { $0.hex == color.hex } == true ? 2 : 1) }
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker("", selection: Binding(get: { current?.color ?? .black }, set: { apply(CanvasColor($0)) }), supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 22, height: 22)
            }
        }
    }

    private var pageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(controller.document.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(2)
            Text("\(Int(controller.document.size.width)) × \(Int(controller.document.size.height))")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
            colourRow("Background", current: controller.document.background.firstColor) { color in controller.setBackground(.solid(color)) }
            HStack {
                Button("Gradient") {
                    let base = controller.document.background.firstColor ?? brand.primary
                    controller.setBackground(.linear(base, brand.accent, angle: 60))
                }
                .buttonStyle(.vellumSecondary)
                Button("Transparent") { controller.setBackground(.none) }
                    .buttonStyle(.vellumSecondary)
            }
        }
    }

    private func number(_ title: String, _ value: Double, _ apply: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(theme.inkTertiary(scheme)).frame(width: 14, alignment: .leading)
            TextField("", value: Binding(get: { (value * 10).rounded() / 10 }, set: apply), format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5).monospacedDigit())
        }
    }

    private func geometrySection(_ layer: CanvasLayer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(layer.kindTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink(scheme))
                Spacer()
                if layer.locked { Image(systemName: "lock.fill").foregroundStyle(theme.inkTertiary(scheme)) }
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    number("X", layer.frame.x) { value in controller.update { $0.frame.x = value } }
                    number("Y", layer.frame.y) { value in controller.update { $0.frame.y = value } }
                }
                GridRow {
                    number("W", layer.frame.width) { value in controller.update { $0.frame.width = max(1, value) } }
                    number("H", layer.frame.height) { value in controller.update { $0.frame.height = max(1, value) } }
                }
                GridRow {
                    number("°", layer.rotation) { value in controller.update { $0.rotation = value.truncatingRemainder(dividingBy: 360) } }
                    HStack(spacing: 4) {
                        Image(systemName: "circle.lefthalf.filled").font(.system(size: 10)).foregroundStyle(theme.inkTertiary(scheme))
                        Slider(value: Binding(get: { layer.opacity }, set: { value in controller.update { $0.opacity = value } }), in: 0...1)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func textSection(_ style: TextStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Text")
            Picker("", selection: Binding(get: { style.font }, set: { font in controller.updateText { $0.font = font } })) {
                ForEach(CanvasFonts.families, id: \.self) { family in Text(family == "System" ? "San Francisco" : family).tag(family) }
            }
            .labelsHidden()
            HStack(spacing: 6) {
                TextField("", value: Binding(get: { style.size }, set: { size in controller.updateText { $0.size = max(4, size) } }), format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Picker("", selection: Binding(get: { style.weight }, set: { weight in controller.updateText { $0.weight = weight } })) {
                    ForEach(TextWeight.allCases) { weight in Text(weight.title).tag(weight) }
                }
                .labelsHidden()
            }
            HStack(spacing: 2) {
                ToolButton(symbol: "italic", help: "Italic", on: style.italic) { controller.updateText { $0.italic.toggle() } }
                ToolButton(symbol: "textformat", help: "Capitals", on: style.uppercase) { controller.updateText { $0.uppercase.toggle() } }
                ToolButton(symbol: "character.textbox", help: "Outline", on: style.outline != nil) {
                    controller.updateText { $0.outline = $0.outline == nil ? brand.primary : nil }
                }
                Spacer().frame(width: 8)
                ToolButton(symbol: "text.alignleft", help: "Left", on: style.alignment == .left) { controller.updateText { $0.alignment = .left } }
                ToolButton(symbol: "text.aligncenter", help: "Centre", on: style.alignment == .center) { controller.updateText { $0.alignment = .center } }
                ToolButton(symbol: "text.alignright", help: "Right", on: style.alignment == .right) { controller.updateText { $0.alignment = .right } }
            }
            HStack {
                Text("Line").font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme))
                Slider(value: Binding(get: { style.lineHeight }, set: { value in controller.updateText { $0.lineHeight = value } }), in: 0.8...2).controlSize(.small)
            }
            HStack {
                Text("Spacing").font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme))
                Slider(value: Binding(get: { style.tracking }, set: { value in controller.updateText { $0.tracking = value } }), in: -10...30).controlSize(.small)
            }
            colourRow("Text colour", current: style.color) { color in controller.updateText { $0.color = color } }
        }
    }

    /// The chart's own settings: drawn as columns or bars, its colours, and where its numbers come from.
    private func chartSection(_ chart: CanvasChart) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Chart")
            Picker("", selection: Binding(get: { chart.kind }, set: { kind in controller.redrawChart { $0.kind = kind } })) {
                ForEach(CanvasChartKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            colourRow("Bars", current: chart.color) { color in controller.redrawChart { $0.color = color } }
            colourRow("The biggest", current: chart.accent) { color in controller.redrawChart { $0.accent = color } }
            if let link = chart.link {
                VStack(alignment: .leading, spacing: 4) {
                    Label("From \(link.sheet) in \(link.workbook)", systemImage: "tablecells")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .lineLimit(2)
                    if let updated = link.updated {
                        Text("Checked \(updated.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
                Button("Refresh from Sheets") { controller.refreshCharts { sheets.workbook(named: $0) } }
                    .buttonStyle(.vellumSecondary)
                    .help("Draws the chart again if the numbers in the sheet changed")
            } else {
                Text("\(chart.points.count) \(chart.points.count == 1 ? "point" : "points"), typed in. Make a chart from Sheets to keep it up to date.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func imageSection(_ fit: ImageFit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Picture")
            Picker("", selection: Binding(get: { fit }, set: { value in
                controller.update { layer in if case .image(let id, _) = layer.content { layer.content = .image(id, value) } }
            })) {
                Text("Fill the frame").tag(ImageFit.fill)
                Text("Show it all").tag(ImageFit.fit)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let removeBackground {
                Button("Remove background", action: removeBackground)
                    .buttonStyle(.vellumSecondary)
                    .help("On this Mac, with the same engine as Photos")
            }
        }
    }

    private func appearanceSection(_ layer: CanvasLayer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            colourRow(layer.isText ? "Box fill" : "Fill", current: layer.fill.firstColor, apply: { color in controller.update { $0.fill = .solid(color) } },
                      clear: { controller.update { $0.fill = .none } })
            colourRow("Outline", current: layer.stroke, apply: { color in
                controller.update {
                    $0.stroke = color
                    if $0.strokeWidth == 0 { $0.strokeWidth = 4 }
                }
            }, clear: { controller.update { $0.stroke = nil; $0.strokeWidth = 0 } })
            if layer.stroke != nil {
                HStack {
                    Text("Width").font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme))
                    Slider(value: Binding(get: { layer.strokeWidth }, set: { value in controller.update { $0.strokeWidth = value } }), in: 0...40).controlSize(.small)
                }
            }
            HStack {
                Text("Corners").font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme))
                Slider(value: Binding(get: { layer.cornerRadius }, set: { value in controller.update { $0.cornerRadius = value } }),
                       in: 0...max(1, min(layer.frame.width, layer.frame.height) / 2)).controlSize(.small)
            }
            Toggle("Shadow", isOn: Binding(get: { layer.shadow }, set: { value in controller.update { $0.shadow = value } }))
                .toggleStyle(.checkbox)
        }
    }

    private var layersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Layers")
            ForEach(controller.document.layers.reversed()) { layer in
                let selected = controller.selection.contains(layer.id)
                HStack(spacing: 8) {
                    Image(systemName: symbol(layer))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .frame(width: 16)
                    Text(layer.text.map { String($0.prefix(28)) } ?? layer.name)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(layer.hidden ? theme.inkTertiary(scheme) : theme.ink(scheme))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        controller.update([layer.id]) { $0.hidden.toggle() }
                    } label: {
                        Image(systemName: layer.hidden ? "eye.slash" : "eye").font(.system(size: 10.5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                    Button {
                        controller.update([layer.id]) { $0.locked.toggle() }
                    } label: {
                        Image(systemName: layer.locked ? "lock.fill" : "lock.open").font(.system(size: 10.5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background { if selected { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.raised(scheme)) } }
                .contentShape(Rectangle())
                .onTapGesture { controller.select(layer.id, adding: NSEvent.modifierFlags.contains(.shift)) }
            }
        }
    }

    private func symbol(_ layer: CanvasLayer) -> String {
        switch layer.content {
        case .text: return "textformat"
        case .image: return "photo"
        case .qr: return "qrcode"
        case .shape(let kind):
            switch kind {
            case .rectangle: return "rectangle"
            case .ellipse: return "circle"
            case .triangle: return "triangle"
            case .star: return "star"
            case .line: return "line.diagonal"
            case .arrow: return "arrow.right"
            }
        }
    }
}
