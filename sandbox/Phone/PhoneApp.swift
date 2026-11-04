import SwiftUI

@main
struct ElevenAmPhoneApp: App {
    @StateObject private var model = PhoneModel()
    @Environment(\.scenePhase) private var phase
    @State private var forcedScheme: ColorScheme?

    var body: some Scene {
        WindowGroup {
            PhoneRoot()
                .environmentObject(model)
                .preferredColorScheme(forcedScheme)
                .onOpenURL { url in
                    if model.pair(with: url.absoluteString) { model.tab = .mac }
                }
                .onChange(of: phase) { _, now in
                    switch now {
                    case .active:
                        model.connect()
                        Task { await model.refreshHealth() }
                    case .background:
                        model.disconnect()
                    default:
                        break
                    }
                }
                .onAppear(perform: applyLaunchArguments)
        }
    }

    /// For screenshots: -phoneSample YES, -phoneTab energy, -phoneAppearance dark.
    private func applyLaunchArguments() {
        let arguments = UserDefaults.standard
        if arguments.bool(forKey: "phoneSample") { model.loadSample() }
        if let tab = arguments.string(forKey: "phoneTab").flatMap(PhoneTab.init(rawValue:)) { model.tab = tab }
        switch arguments.string(forKey: "phoneAppearance") {
        case "dark": forcedScheme = .dark
        case "light": forcedScheme = .light
        default: break
        }
    }
}

/// The phone's look: the same warm paper and ink as 11am on the Mac.
enum Ink {
    static let accent = Color(red: 0.96, green: 0.42, blue: 0.24)

    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.07, green: 0.07, blue: 0.08) : Color(red: 0.965, green: 0.955, blue: 0.935)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color.white.opacity(0.92)
    }

    static func well(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)
    }

    static func edge(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.94, green: 0.93, blue: 0.9) : Color(red: 0.09, green: 0.09, blue: 0.1)
    }

    static func secondary(_ scheme: ColorScheme) -> Color { ink(scheme).opacity(0.64) }

    static func tertiary(_ scheme: ColorScheme) -> Color { ink(scheme).opacity(0.42) }

    static func tone(_ tone: EnergyInsight.Tone) -> Color {
        switch tone {
        case .good: return Color(red: 0.3, green: 0.68, blue: 0.42)
        case .usual: return Color(red: 0.45, green: 0.5, blue: 0.58)
        case .easy: return accent
        }
    }
}

struct PhoneRoot: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TabView(selection: $model.tab) {
            TodayScreen()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(PhoneTab.today)
            EnergyScreen()
                .tabItem { Label("Energy", systemImage: "bolt.heart") }
                .tag(PhoneTab.energy)
            CaptureScreen()
                .tabItem { Label("Capture", systemImage: "viewfinder") }
                .tag(PhoneTab.capture)
            MacScreen()
                .tabItem { Label("Mac", systemImage: "laptopcomputer.and.iphone") }
                .tag(PhoneTab.mac)
        }
        .tint(Ink.ink(scheme))
        .overlay(alignment: .top) {
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Ink.ink(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: notice) {
                        try? await Task.sleep(nanoseconds: 3_200_000_000)
                        withAnimation(.easeOut(duration: 0.25)) { model.notice = nil }
                    }
                    .onTapGesture { model.notice = nil }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.notice)
    }
}

/// Big lowercase title, like the Mac.
struct ScreenHeader: View {
    @Environment(\.colorScheme) private var scheme
    var title: String
    var subtitle: String
    var monogram: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 38, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(Ink.ink(scheme))
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.tertiary(scheme))
            }
            Spacer()
            if let monogram {
                Text(monogram)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Ink.paper(scheme))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Ink.ink(scheme)))
            }
        }
        .padding(.top, 8)
    }
}

/// A card on the paper.
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Ink.card(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Ink.edge(scheme), lineWidth: 0.5))
    }
}

struct Label2: View {
    @Environment(\.colorScheme) private var scheme
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Ink.tertiary(scheme))
    }
}

/// A full-width button in ink.
struct InkButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    var secondary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15.5, weight: .semibold))
            .foregroundStyle(secondary ? Ink.ink(scheme) : Ink.paper(scheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(secondary ? Ink.well(scheme) : Ink.ink(scheme)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
