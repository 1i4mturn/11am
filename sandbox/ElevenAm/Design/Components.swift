import SwiftUI

/// An agent's monogram from the brand SVGs (Resources/Assets.xcassets/Logos), tinted like ink.
/// Every monogram shares one box, so letter size and baseline match across the team.
struct AgentLogo: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var code: String
    var size: CGFloat = 20
    var color: Color?

    var body: some View {
        Image(AgentLogo.assetName(for: code))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(color ?? theme.ink(scheme))
            .accessibilityLabel(AgentLogo.name(for: code))
    }

    static func assetName(for code: String) -> String {
        code == "11" ? "logo-11am" : "logo-\(code)"
    }

    static func name(for code: String) -> String {
        switch code {
        case "le": return "Leo"
        case "bn": return "Bolton"
        case "mc": return "Marc"
        case "wm": return "William"
        case "jm": return "James"
        case "ge": return "George"
        case "cr": return "Conner"
        case "rt": return "Robert"
        case "co": return "Cole"
        case "hr": return "Harris"
        case "jo": return "Johnny"
        default: return "11am"
        }
    }
}

/// The 11am wordmark from the brand SVG.
struct Wordmark: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var height: CGFloat = 20
    var color: Color?

    var body: some View {
        Image("logo-11am")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .foregroundStyle(color ?? theme.ink(scheme))
            .accessibilityLabel("11am")
    }
}

/// An agent monogram on a small tile: ink on white, or inverted for the agent that's working.
struct Monogram: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var text: String
    var size: CGFloat = 26
    var inverted = false

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        AgentLogo(code: text, size: size * 0.76, color: inverted ? theme.paper(scheme) : theme.ink(scheme))
            .frame(width: size, height: size)
            .background { tile.fill(inverted ? theme.ink(scheme) : theme.well(scheme)) }
            .overlay { tile.strokeBorder(inverted ? Color.clear : theme.edge(scheme), lineWidth: 0.5) }
    }
}

struct SectionLabel: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(theme.inkTertiary(scheme))
    }
}

struct DisplayTitle: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String
    var size: CGFloat = 34

    var body: some View {
        Text(text)
            .font(theme.display(size))
            .tracking(-size * 0.02)
            .foregroundStyle(theme.ink(scheme))
            .lineSpacing(-2)
    }
}

/// The top of every app: a big display title printed on the sheet, a quiet subtitle, optional actions.
struct SectionHeader<Trailing: View>: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                DisplayTitle(text: title, size: 36)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkTertiary(scheme))
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

/// A card pressed onto the main sheet: a faint well with a hairline.
struct Card<Content: View>: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous)
                    .fill(theme.well(scheme))
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous)
                    .strokeBorder(theme.edge(scheme), lineWidth: 0.5)
            }
    }
}

/// Small pill used for sources, statuses and tags.
struct Chip: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var text: String
    var systemImage: String?
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9.5, weight: .semibold))
            }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .foregroundStyle(filled ? theme.paper(scheme) : theme.inkSecondary(scheme))
        .background {
            Capsule().fill(filled ? theme.ink(scheme) : Color.clear)
        }
        .overlay {
            Capsule().strokeBorder(filled ? Color.clear : theme.edge(scheme).opacity(1.6), lineWidth: 0.75)
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
        label
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(kind == .primary ? theme.paper(scheme) : theme.ink(scheme))
            .background {
                Capsule().fill(kind == .primary ? theme.ink(scheme).opacity(hovering ? 0.86 : 1) : (hovering ? theme.raised(scheme) : theme.well(scheme).opacity(0.5)))
            }
            .overlay {
                Capsule().strokeBorder(kind == .primary ? Color.clear : theme.edge(scheme).opacity(2), lineWidth: 0.75)
            }
            .opacity(isEnabled ? (isPressed ? 0.75 : 1) : 0.45)
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

/// A text field pressed into the paper, with a submit action.
struct AskField: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(theme.inkTertiary(scheme))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.ink(scheme))
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button(action: onSubmit) {
                    Image(systemName: "return")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkSecondary(scheme))
                .accessibilityLabel("Ask")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.well(scheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
        }
    }
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
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
            if !run.text.isEmpty {
                Text(run.text)
                    .font(.system(size: 13))
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

/// A quiet "working" indicator: a soft luminance sweep, no spinner.
struct ThinkingLine: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String
    @State private var phase: CGFloat = -1

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(theme.inkTertiary(scheme))
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, theme.ink(scheme).opacity(0.55), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.4)
                    .offset(x: phase * proxy.size.width)
                }
                .mask(Text(text).font(.system(size: 12.5)))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}
