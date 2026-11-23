import SwiftUI

/// The agents' codes. Brand v2 renamed four (Marc mr, William wi, Robert rb, Cole ce); older code and saved data may
/// still use the earlier ones, so everything that draws a monogram goes through here.
enum AgentCode {
    static func brand(_ code: String) -> String {
        switch code {
        case "mc": return "mr"
        case "wm": return "wi"
        case "rt": return "rb"
        case "co": return "ce"
        default: return code
        }
    }

    static func name(_ code: String) -> String {
        switch brand(code) {
        case "le": return "Leo"
        case "bn": return "Bolton"
        case "mr": return "Marc"
        case "wi": return "William"
        case "jm": return "James"
        case "ge": return "George"
        case "cr": return "Conner"
        case "rb": return "Robert"
        case "ce": return "Cole"
        case "hr": return "Harris"
        case "jo": return "Johnny"
        default: return "11am"
        }
    }
}

/// An agent's monogram, the locked brand SVG, tinted like ink. On its own it's for places that already sit in a
/// circle or a row; in interface, agents show as `AgentCircle`.
struct AgentLogo: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var code: String
    var size: CGFloat = 20
    var color: Color?
    /// The files are drawn on their circle (letters about 0.45 of it). On their own they scale up to fill the box.
    var scale: CGFloat = 1.7

    var body: some View {
        Image(AgentLogo.assetName(for: code))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size * scale, height: size * scale)
            .frame(width: size, height: size)
            .foregroundStyle(color ?? theme.ink(scheme))
            .accessibilityLabel(AgentLogo.name(for: code))
    }

    static func assetName(for code: String) -> String {
        let brand = AgentCode.brand(code)
        return brand == "11" || brand == "11am" ? "logo-11" : "logo-\(brand)"
    }

    static func name(for code: String) -> String { AgentCode.name(code) }
}

/// Agents are always circles: the monogram centred in a disc. Ink disc on paper, paper disc on ink, an open ring
/// for an agent at rest, or sheet-ink for the resting circles in the drop.
struct AgentCircle: View {
    enum Style { case ink, paper, ring, sheetInk }

    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var code: String
    var size: CGFloat = 32
    var style: Style = .ink

    var body: some View {
        let ink = theme.ink(scheme), paper = theme.paper(scheme)
        let fill: Color = {
            switch style {
            case .ink: return ink
            case .paper: return paper
            case .ring: return .clear
            case .sheetInk: return BrandTokens.sheetInk
            }
        }()
        let glyph: Color = style == .ink ? paper : (style == .sheetInk ? .white : ink)
        AgentLogo(code: code, size: size, color: glyph, scale: 1)
            .background { Circle().fill(fill) }
            .overlay {
                if style == .ring { Circle().strokeBorder(ink, lineWidth: BrandTokens.ruleOpen) }
            }
            .accessibilityLabel(AgentCode.name(code))
    }
}

/// The wordmark: the solid file under 160pt wide, the outline above. Never under vellum, never recoloured.
struct Wordmark: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var height: CGFloat = 20
    var color: Color?

    var body: some View {
        Image(height * 1876 / 796 < 160 ? "wordmark-solid" : "wordmark-outline")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .foregroundStyle(color ?? theme.ink(scheme))
            .accessibilityLabel("11am")
    }
}

/// An agent in a circle, kept under its old name: solid ink for the agent that's working, an open ring at rest.
struct Monogram: View {
    var text: String
    var size: CGFloat = 26
    var inverted = false

    var body: some View {
        AgentCircle(code: text, size: size, style: inverted ? .ink : .ring)
    }
}

/// Labels and metadata: Courier Prime 12, lowercase, full ink.
struct SectionLabel: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String

    var body: some View {
        Text(text.lowercased())
            .font(BrandFont.label(12))
            .foregroundStyle(theme.ink(scheme))
    }
}

struct DisplayTitle: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String
    var size: CGFloat = 34

    var body: some View {
        Text(DisplayTitle.sentenceCase(text))
            .font(theme.display(size))
            .tracking(-size * 0.035)
            .foregroundStyle(theme.ink(scheme))
    }

    /// Headings are sentence case: "calendar" reads "Calendar".
    static func sentenceCase(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

/// The top of every app: a Schibsted heading, the line under it in Instrument Sans, optional actions.
/// True inside an app's own window, whose ink title bar already says `marc · mail`.
private struct InAppWindowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var inAppWindow: Bool {
        get { self[InAppWindowKey.self] }
        set { self[InAppWindowKey.self] = newValue }
    }
}

struct SectionHeader<Trailing: View>: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.inAppWindow) private var inAppWindow
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                // In its own window the title bar carries the label, so it isn't said twice.
                if !inAppWindow, let section = AppSection.allCases.first(where: { $0.title.lowercased() == title.lowercased() }) {
                    AppLabel(section: section)
                        .padding(.bottom, 2)
                }
                DisplayTitle(text: title, size: 34)
                Text(subtitle)
                    .font(BrandFont.body(14))
                    .foregroundStyle(theme.ink(scheme))
            }
            Spacer()
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A card: white paper lifted off the page, square, no outline (sheet-ink on the ink theme).
struct Card<Content: View>: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .vellum(level: 3)
    }
}

/// Status and tag labels in Courier: filled when settled (done, a tag), open while running or waiting.
struct Chip: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var text: String
    var systemImage: String?
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.brand(size: 9, weight: .regular))
            }
            Text(text.lowercased()).font(BrandFont.label(12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .foregroundStyle(filled ? theme.paper(scheme) : theme.ink(scheme))
        .background { Capsule().fill(filled ? theme.ink(scheme) : Color.clear) }
        .overlay {
            if !filled { Capsule().strokeBorder(theme.ink(scheme), lineWidth: BrandTokens.ruleOpen) }
        }
    }
}

/// Says where an answer came from: on this Mac (filled dot) or the cloud (ring).
struct ModelBadge: View {
    var label: String
    var isLocal: Bool

    var body: some View {
        Chip(text: label, systemImage: isLocal ? "circle.fill" : "circle", filled: false)
            .help(isLocal ? "Ran on this Mac. Nothing left the device." : "Ran in the cloud with your API key.")
    }
}

/// Pills, sentence case: an ink pill for the main action, an open pill (the `rule-open` outline) for the rest.
struct VellumButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        VellumButtonBody(label: configuration.label, isPressed: configuration.isPressed, kind: kind)
    }
}

private struct VellumButtonBody: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let kind: VellumButtonStyle.Kind

    var body: some View {
        let ink = theme.ink(scheme), paper = theme.paper(scheme)
        label
            .font(BrandFont.body(13.5, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 16)
            .frame(minHeight: 32)
            .foregroundStyle(kind == .primary ? paper : ink)
            .background {
                Capsule().fill(kind == .primary ? ink : (hovering ? theme.well(scheme) : paper))
            }
            .overlay {
                if kind == .secondary { Capsule().strokeBorder(ink, lineWidth: BrandTokens.ruleOpen) }
            }
            .opacity(isEnabled ? (isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(isPressed && theme.motionEnabled ? 0.97 : 1)
            .contentShape(Capsule())
            .onHover { inside in
                withAnimation(theme.motionEnabled ? .easeOut(duration: 0.15) : nil) { hovering = inside && isEnabled }
            }
            .animation(theme.motionEnabled ? .spring(response: 0.25, dampingFraction: 0.7) : nil, value: isPressed)
    }
}

extension ButtonStyle where Self == VellumButtonStyle {
    static var vellumPrimary: VellumButtonStyle { VellumButtonStyle(kind: .primary) }
    static var vellumSecondary: VellumButtonStyle { VellumButtonStyle(kind: .secondary) }
}

/// A field: a white card lifted off the page; the field in use lifts further.
struct AskField: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Icon("sparkle.magnifyingglass")
                .foregroundStyle(theme.ink(scheme))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(BrandFont.body(14))
                .foregroundStyle(theme.ink(scheme))
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button(action: onSubmit) {
                    Icon("arrow.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.ink(scheme))
                .accessibilityLabel("Ask")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background { Rectangle().fill(theme.well(scheme)).lift(hi: focused) }
    }
}

// MARK: - Choices

/// A checkbox is a circle that fills in.
struct BrandCheckStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        BrandCheckBody(configuration: configuration)
    }
}

private struct BrandCheckBody: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ToggleStyleConfiguration

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(configuration.isOn ? theme.ink(scheme) : Color.clear)
                    .overlay { Circle().strokeBorder(theme.ink(scheme), lineWidth: BrandTokens.ruleOpen) }
                    .frame(width: 16, height: 16)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A toggle is a pill that turns ink when it's on.
struct BrandSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        BrandSwitchBody(configuration: configuration)
    }
}

private struct BrandSwitchBody: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ToggleStyleConfiguration

    var body: some View {
        let ink = theme.ink(scheme), paper = theme.paper(scheme)
        HStack(spacing: 8) {
            configuration.label
            Button {
                withAnimation(theme.spring) { configuration.isOn.toggle() }
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? ink : Color.clear)
                    Capsule().strokeBorder(ink, lineWidth: BrandTokens.ruleOpen)
                    Circle()
                        .fill(configuration.isOn ? paper : ink)
                        .frame(width: 14, height: 14)
                        .padding(4)
                }
                .frame(width: 38, height: 22)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

extension ToggleStyle where Self == BrandCheckStyle {
    static var brandCheck: BrandCheckStyle { BrandCheckStyle() }
}

extension ToggleStyle where Self == BrandSwitchStyle {
    static var brandSwitch: BrandSwitchStyle { BrandSwitchStyle() }
}

/// Shows a brain run: streamed text, where it ran and what it cost.
struct RunView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var run: BrainRun

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch run.status {
            case .routing:
                ThinkingLine(text: "Choosing the right brain…")
            case .working where run.text.isEmpty:
                ThinkingLine(text: "Working on this Mac…")
            case .failed(let message):
                Text(message)
                    .font(.brand(size: 12.5))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
            if !run.text.isEmpty {
                Text(run.text)
                    .font(.brand(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(theme.ink(scheme))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !run.providerLabel.isEmpty {
                HStack(spacing: 6) {
                    ModelBadge(label: run.providerLabel, isLocal: run.isLocal)
                    if run.costUSD > 0 {
                        Chip(text: Pricing.format(run.costUSD))
                    }
                }
            }
        }
    }
}

/// Loading: the words in Hack with a block caret that blinks. Stops under reduced motion.
struct ThinkingLine: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String
    @State private var on = true

    var body: some View {
        HStack(spacing: 2) {
            Text(text)
                .font(BrandFont.code(12))
            Rectangle()
                .fill(theme.ink(scheme))
                .frame(width: 7, height: 13)
                .opacity(on ? 1 : 0)
        }
        .foregroundStyle(theme.ink(scheme))
        .task {
            guard theme.motionEnabled else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 530_000_000)
                on.toggle()
            }
        }
    }
}
