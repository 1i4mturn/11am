import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Robert's app: quick on-brand graphics, image tools that run on this Mac, and the brand kit every agent uses.
struct DesignView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var studio: DesignStudio

    enum DesignTab: String, CaseIterable, Identifiable {
        case designs, graphic, images, brand
        var id: String { rawValue }
        var title: String {
            switch self {
            case .designs: return "Designs"
            case .graphic: return "Quick graphic"
            case .images: return "Image tools"
            case .brand: return "Brand kit"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "design", subtitle: "Robert · a considered look for everything") {
                Picker("", selection: $studio.tab) {
                    ForEach(DesignTab.allCases) { tab in Text(tab.title).tag(tab) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ZStack {
                switch studio.tab {
                case .designs: DesignsPanel().transition(.rise(theme.rise))
                case .graphic: QuickGraphic().transition(.rise(theme.rise))
                case .images: ImageToolsPanel().transition(.rise(theme.rise))
                case .brand: BrandKit().transition(.rise(theme.rise))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(theme.spring, value: studio.tab)
        }
        .padding(24)
    }
}

// MARK: Quick graphic

private struct QuickGraphic: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var design: DesignModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Template", selection: Binding(get: { design.template }, set: { newValue in
                        withAnimation(theme.spring) { DesignSamples.switchTemplate(design, to: newValue) }
                    })) {
                        ForEach(GraphicTemplate.allCases) { template in Text(template.title).tag(template) }
                    }
                    Picker("Size", selection: $design.size) {
                        ForEach(GraphicSize.allCases) { size in Text(size.title).tag(size) }
                    }
                    labelled("Headline") {
                        TextField("Headline", text: $design.headline, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                    }
                    labelled(design.template == .quote ? "Who said it" : "Supporting line") {
                        TextField("Supporting line", text: $design.detail, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                    }
                    labelled("Footer") {
                        TextField("Footer", text: $design.footer)
                            .textFieldStyle(.roundedBorder)
                    }
                    Toggle("Dark", isOn: $design.dark)
                    Toggle("11am mark", isOn: $design.showsMark)

                    HStack(spacing: 8) {
                        Button("Suggest headlines") { design.suggestHeadlines() }
                            .buttonStyle(.vellumSecondary)
                            .disabled(brain.isBusy)
                        Button("Export PNG") { export() }
                            .buttonStyle(.vellumPrimary)
                    }
                    if let run = design.headlineRun {
                        HeadlineChoices(run: run)
                    }
                }
                .font(.brand(size: 12.5))
                .padding(.trailing, 4)
            }
            .frame(width: 270)
            .scrollContentBackground(.hidden)

            GeometryReader { proxy in
                let pixels = design.size.pixels
                let scale = min(proxy.size.width / pixels.width, proxy.size.height / pixels.height)
                canvas
                    .frame(width: pixels.width, height: pixels.height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: pixels.width * scale, height: pixels.height * scale, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(theme.spring, value: design.size)
            }
        }
    }

    private var canvas: GraphicCanvas {
        GraphicCanvas(
            template: design.template,
            size: design.size,
            headline: design.headline,
            detail: design.detail,
            footer: design.footer,
            dark: design.dark,
            showsMark: design.showsMark
        )
    }

    /// Renders the graphic at full size, on this Mac.
    private func export() {
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        guard let image = renderer.cgImage, let data = ImageTools.pngData(image) else { return }
        DesignModel.save(data, suggestedName: "11am-\(design.template.rawValue).png")
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: label)
            content()
        }
    }
}

private struct HeadlineChoices: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var design: DesignModel
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var run: BrainRun

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if run.status == .done {
                ForEach(DesignModel.headlines(in: run.text), id: \.self) { line in
                    Button {
                        withAnimation(theme.spring) { design.headline = line }
                    } label: {
                        Text(line)
                            .font(.brand(size: 12))
                            .foregroundStyle(theme.ink(scheme))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 0).fill(theme.well(scheme)))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                RunView(run: run)
            }
        }
    }
}

/// The graphic itself, drawn at its real pixel size. Pure: no environment, so it renders the same on screen and in export.
struct GraphicCanvas: View {
    var template: GraphicTemplate
    var size: GraphicSize
    var headline: String
    var detail: String
    var footer: String
    var dark: Bool
    var showsMark: Bool

    var body: some View {
        let pixels = size.pixels
        let unit = min(pixels.width, pixels.height) / 1080
        let ink = dark ? BrandTokens.paperHex : BrandTokens.inkHex
        let paper = dark ? BrandTokens.inkHex : BrandTokens.paperHex
        ZStack(alignment: .topLeading) {
            paper
            Tooth()
            VStack(alignment: .leading, spacing: 0) {
                switch template {
                case .announcement:
                    Text("ANNOUNCEMENT")
                        .font(.brand(size: 26 * unit, weight: .semibold))
                        .tracking(4 * unit)
                        .foregroundStyle(ink.opacity(0.55)) // brand-lint: allow the graphic being made, not the interface
                    Spacer(minLength: 0)
                    Text(headline)
                        .font(.custom("SchibstedGrotesk-Black", size: 104 * unit))
                        .tracking(-2 * unit)
                        .lineSpacing(-8 * unit)
                        .foregroundStyle(ink)
                        .minimumScaleFactor(0.4)
                    Text(detail)
                        .font(.brand(size: 38 * unit))
                        .foregroundStyle(ink.opacity(0.7)) // brand-lint: allow the graphic being made, not the interface
                        .padding(.top, 28 * unit)
                case .quote:
                    Text("“")
                        .font(.custom("SchibstedGrotesk-Black", size: 260 * unit))
                        .foregroundStyle(ink)
                        .frame(height: 170 * unit, alignment: .top)
                    Spacer(minLength: 0)
                    Text(headline)
                        .font(.custom("SchibstedGrotesk-Black", size: 78 * unit))
                        .tracking(-1.5 * unit)
                        .foregroundStyle(ink)
                        .minimumScaleFactor(0.4)
                    Text("— \(detail)")
                        .font(.brand(size: 36 * unit, weight: .medium))
                        .foregroundStyle(ink.opacity(0.65)) // brand-lint: allow the graphic being made, not the interface
                        .padding(.top, 30 * unit)
                case .stat:
                    Spacer(minLength: 0)
                    Text(headline)
                        .font(.custom("SchibstedGrotesk-Black", size: 230 * unit))
                        .tracking(-8 * unit)
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.3)
                    Text(detail)
                        .font(.brand(size: 44 * unit, weight: .medium))
                        .foregroundStyle(ink.opacity(0.7)) // brand-lint: allow the graphic being made, not the interface
                        .padding(.top, 10 * unit)
                }
                Spacer(minLength: 0)
                HStack(alignment: .center) {
                    if showsMark {
                        Image("wordmark-solid")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 44 * unit)
                            .foregroundStyle(ink)
                    }
                    Spacer()
                    Text(footer)
                        .font(.brand(size: 26 * unit, weight: .medium))
                        .foregroundStyle(ink.opacity(0.55)) // brand-lint: allow the graphic being made, not the interface
                }
            }
            .padding(84 * unit)
        }
        .frame(width: pixels.width, height: pixels.height)
        .clipped()
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

enum DesignSamples {
    static let text: [GraphicTemplate: (String, String)] = [
        .announcement: ("We closed our first enterprise pilot.", "Acme is rolling 11am out to 40 people this month."),
        .quote: ("Software you own, on the Mac you have.", "The 11am team"),
        .stat: ("14 months", "of runway, with revenue up half since May"),
    ]

    /// Switching template swaps in that template's sample, unless you've written your own.
    @MainActor
    static func switchTemplate(_ design: DesignModel, to template: GraphicTemplate) {
        let isSample = text.values.contains { $0.0 == design.headline }
        design.template = template
        if isSample, let sample = text[template] {
            design.headline = sample.0
            design.detail = sample.1
        }
    }
}

// MARK: Image tools

private struct ImageToolsPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var design: DesignModel
    @Environment(\.colorScheme) private var scheme
    @State private var importing = false
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button("Open image…") { importing = true }
                    .buttonStyle(.vellumSecondary)
                Button("Lift subject") { design.liftSubject() }
                    .buttonStyle(.vellumPrimary)
                    .disabled(design.original == nil || design.isProcessing)
                Button("Black & white") { design.monochrome() }
                    .buttonStyle(.vellumSecondary)
                    .disabled(design.original == nil || design.isProcessing)
                Button("Undo") { withAnimation(theme.spring) { design.resetImage() } }
                    .buttonStyle(.vellumSecondary)
                    .disabled(design.result == nil)
                Spacer()
                if design.isProcessing { ProgressView().controlSize(.small) }
                Button("Save PNG") { design.saveResult() }
                    .buttonStyle(.vellumPrimary)
                    .disabled(design.original == nil)
            }
            if let notice = design.imageNotice {
                Text(notice).font(.brand(size: 12)).foregroundStyle(theme.inkSecondary(scheme))
            }
            HStack(spacing: 12) {
                ImageWell(title: "Original", image: design.original, emptyText: "Drop an image here, or open one. It never leaves this Mac.")
                ImageWell(title: "Result", image: design.result, emptyText: "Lift the subject to cut out the background, or make it black and white.")
            }
            .frame(maxHeight: .infinity)
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: theme.radius).strokeBorder(theme.ink(scheme).opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                withAnimation(theme.spring) { design.load(url) }
                return true
            } isTargeted: { dropTargeted = $0 }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { withAnimation(theme.spring) { design.load(url) } }
        }
    }
}

private struct ImageWell: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var title: String
    var image: CGImage?
    var emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            ZStack {
                Checkerboard()
                    .opacity(image == nil ? 0 : 1)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(10)
                        .transition(.opacity)
                } else {
                    Text(emptyText)
                        .font(.brand(size: 12))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .multilineTextAlignment(.center)
                        .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: theme.radius).fill(theme.well(scheme)))
            .overlay(RoundedRectangle(cornerRadius: theme.radius).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius))
        }
    }
}

/// Shows where an image is transparent.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            for row in 0..<Int(size.height / cell) + 1 {
                for column in 0..<Int(size.width / cell) + 1 where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(Color.gray.opacity(0.14))) // brand-lint: allow the transparency grid behind a picture
                }
            }
        }
    }
}

// MARK: Brand kit

private struct BrandKit: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false

    private let swatches: [(name: String, hex: String, color: Color)] = [
        // Brand v2: two colours at full strength, the drop's black, and the vellum note that carries text.
        ("Ink", "#0A0A0A", BrandTokens.inkHex),
        ("Paper", "#FFFFFF", BrandTokens.paperHex),
        ("Drop", "#000000", BrandTokens.drop),
        ("Note", "paper 82%", BrandTokens.note),
    ]

    private let agents = ["le", "mc", "wm", "bn", "jm", "ge", "cr", "rt", "co", "hr", "jo"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Logo")
                        // Big enough for the outline mark, which glitches now and then.
                        Wordmark(height: 72)
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .background(RoundedRectangle(cornerRadius: 0).fill(theme.raised(scheme)))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                            ForEach(agents, id: \.self) { code in
                                Monogram(text: code, size: 38)
                                    .help(AgentLogo.name(for: code))
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .vellum(level: 3, radius: theme.radius)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Palette")
                        ForEach(swatches, id: \.name) { swatch in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 0)
                                    .fill(swatch.color)
                                    .overlay(RoundedRectangle(cornerRadius: 0).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                                    .frame(width: 36, height: 28)
                                Text(swatch.name).font(.brand(size: 12.5, weight: .medium))
                                Spacer()
                                Text(swatch.hex).font(.brand(size: 11.5).monospaced()).foregroundStyle(theme.inkTertiary(scheme))
                            }
                            .foregroundStyle(theme.ink(scheme))
                        }
                    }
                    .padding(16)
                    .frame(width: 260, alignment: .topLeading)
                    .vellum(level: 3, radius: theme.radius)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Type")
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("Aa").font(.custom("SchibstedGrotesk-Black", size: 48))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Schibsted Grotesk").font(.brand(size: 13, weight: .semibold))
                            Text("The wordmark, numerals and every heading").font(.brand(size: 11.5)).foregroundStyle(theme.inkTertiary(scheme))
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("Aa").font(BrandFont.body(48))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Instrument Sans").font(.brand(size: 13, weight: .semibold))
                            Text("Reading and the interface; Courier Prime for labels, Hack for code").font(.brand(size: 11.5)).foregroundStyle(theme.inkTertiary(scheme))
                        }
                    }
                }
                .foregroundStyle(theme.ink(scheme))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .vellum(level: 3, radius: theme.radius)

                HStack(spacing: 8) {
                    Button(copied ? "Copied" : "Copy brand tokens") { copyTokens() }
                        .buttonStyle(.vellumPrimary)
                    Button("Brand voice lives with William") { model.go(to: .write) }
                        .buttonStyle(.vellumSecondary)
                    Spacer()
                }
                Text("Every agent draws from this kit: Robert's graphics, Conner's decks, Cole's captions.")
                    .font(.brand(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func copyTokens() {
        var colours: [String: String] = [:]
        for swatch in swatches { colours[swatch.name.lowercased()] = swatch.hex }
        let tokens: [String: Any] = [
            "colours": colours,
            "type": ["headings": "Schibsted Grotesk", "reading": "Instrument Sans", "labels": "Courier Prime", "code": "Hack"],
            "radius": 0,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: tokens, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
