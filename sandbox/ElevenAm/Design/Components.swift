import SwiftUI

/// The two-letter agent monogram, set in Alte Haas.
struct Monogram: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var text: String
    var size: CGFloat = 26
    var inverted = false

    var body: some View {
        Text(text)
            .font(theme.monogramFont(size * 0.5))
            .foregroundStyle(inverted ? theme.paper(scheme) : theme.ink(scheme))
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(inverted ? theme.ink(scheme) : theme.well(scheme))
            }
            .accessibilityLabel("\(text) monogram")
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
                RoundedRectangle(cornerRadius: max(theme.radius - 6, 8), style: .continuous)
                    .fill(theme.well(scheme).opacity(0.7))
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(theme.radius - 6, 8), style: .continuous)
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
                Capsule().fill(kind == .primary ? theme.ink(scheme) : Color.clear)
            }
            .overlay {
                Capsule().strokeBorder(kind == .primary ? Color.clear : theme.edge(scheme).opacity(2), lineWidth: 0.75)
            }
            .opacity(isPressed ? 0.7 : 1)
            .contentShape(Capsule())
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
