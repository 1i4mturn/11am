import AppIntents
import SwiftUI

@main
struct ElevenAmPhoneApp: App {
    @StateObject private var model = PhoneModel()
    @Environment(\.scenePhase) private var phase
    @State private var forcedScheme: ColorScheme?

    init() {
        // Before the first view draws, or it keeps a fallback face.
        PhoneBrand.registerFonts()
        ElevenShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            PhoneRoot()
                .environmentObject(model)
                .preferredColorScheme(forcedScheme)
                .onOpenURL { url in
                    // elevenam://talk comes from the Control Center control and the Action button.
                    if url.host == "talk" {
                        model.startTalking()
                    } else if model.pair(with: url.absoluteString) {
                        model.open(.mac)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: TalkIntent.requested)) { _ in model.startTalking() }
                .onChange(of: phase) { _, now in
                    switch now {
                    case .active:
                        model.connect()
                        Task { await model.refreshHealth() }
                        if TalkIntent.pending {
                            TalkIntent.pending = false
                            model.startTalking()
                        }
                    case .background:
                        model.disconnect()
                    default:
                        break
                    }
                }
                .onAppear(perform: applyLaunchArguments)
        }
    }

    /// For screenshots: -phoneSample YES, -phoneTab energy (an app screen; without it the drop), -phoneAppearance dark,
    /// -phoneTalk YES (the talk note), -phoneActivityPreview YES (the Live Activity and Dynamic Island, drawn in the app).
    private func applyLaunchArguments() {
        let arguments = UserDefaults.standard
        if arguments.bool(forKey: "phoneSample") { model.loadSample() }
        if let tab = arguments.string(forKey: "phoneTab").flatMap(PhoneTab.init(rawValue:)) { model.open(tab) }
        if arguments.bool(forKey: "phoneTalk") { model.previewTalk() }
        if arguments.bool(forKey: "phoneActivityPreview") { model.showsActivityPreview = true }
        switch arguments.string(forKey: "phoneAppearance") {
        case "dark": forcedScheme = .dark
        case "light": forcedScheme = .light
        default: break
        }
    }
}

/// The phone's palette: brand v2's two colours at full strength. Text is never faded; what recedes goes under vellum.
enum Ink {
    static var accent: Color { PhoneBrand.inkHex }

    static func paper(_ scheme: ColorScheme) -> Color { PhoneBrand.paper(scheme) }

    /// A card: paper lifted off paper, or sheet-ink on the ink theme.
    static func card(_ scheme: ColorScheme) -> Color { scheme == .dark ? PhoneBrand.sheetInk : .white }

    static func well(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.045) }

    static func edge(_ scheme: ColorScheme) -> Color { Color.clear }

    static func ink(_ scheme: ColorScheme) -> Color { PhoneBrand.ink(scheme) }

    static func secondary(_ scheme: ColorScheme) -> Color { ink(scheme) }

    static func tertiary(_ scheme: ColorScheme) -> Color { ink(scheme) }

    static func tone(_ tone: EnergyInsight.Tone) -> Color { PhoneBrand.inkHex }
}

/// Home is the drop. Each app opens as a screen under an ink title bar; pull the bar down to go back to the drop.
struct PhoneRoot: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if model.showsDrop {
                DropHome()
                    .transition(.move(edge: .top))
            } else {
                AppScreen()
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: model.showsDrop)
        .overlay(alignment: .top) {
            if let notice = model.notice {
                // Notifications are notes: vellum with the 22pt iPhone corner, led by the agent who sent it.
                HStack(alignment: .top, spacing: 10) {
                    PhoneAgentCircle(code: model.noticeAgent, size: 28, style: .ink)
                    Text(notice)
                        .font(.brand(size: 14, weight: .medium))
                        .foregroundStyle(PhoneBrand.inkHex)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: PhoneBrand.radiusNotification, style: .continuous).fill(.ultraThinMaterial))
                .background(RoundedRectangle(cornerRadius: PhoneBrand.radiusNotification, style: .continuous).fill(PhoneBrand.note))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .environment(\.colorScheme, .light)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: notice) {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    withAnimation(.easeOut(duration: 0.25)) { model.notice = nil }
                }
                .onTapGesture { model.notice = nil }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.notice)
        .sheet(isPresented: $model.talking) {
            TalkSheet()
                .environmentObject(model)
        }
        .fullScreenCover(isPresented: $model.showsActivityPreview) {
            ActivityPreview()
                .environmentObject(model)
        }
    }
}

/// A screen's opening: the title in Schibsted, the line under it in Instrument Sans.
struct ScreenHeader: View {
    @Environment(\.colorScheme) private var scheme
    var title: String
    var subtitle: String
    var monogram: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.prefix(1).uppercased() + title.dropFirst())
                .font(BrandFace.heading(36))
                .tracking(-1.1)
                .foregroundStyle(Ink.ink(scheme))
            Text(subtitle)
                .font(.brand(size: 15))
                .foregroundStyle(Ink.ink(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

/// A card: square, white, lifted off the paper with no outline (sheet-ink on the ink theme).
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Rectangle().fill(Ink.card(scheme)))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 1, y: 1)
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.08), radius: 10, y: 6)
    }
}

/// A label: Courier Prime, lowercase, full ink.
struct Label2: View {
    @Environment(\.colorScheme) private var scheme
    var text: String

    var body: some View {
        Text(text.lowercased())
            .font(BrandFace.label(12.5))
            .foregroundStyle(Ink.ink(scheme))
    }
}

/// A pill: ink with paper words, or open with an ink ring. 44pt tall on the iPhone.
struct InkButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    var secondary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.brand(size: 15.5, weight: .semibold))
            .foregroundStyle(secondary ? Ink.ink(scheme) : Ink.paper(scheme))
            .frame(maxWidth: .infinity, minHeight: PhoneBrand.hit)
            .background {
                if secondary {
                    Capsule().strokeBorder(Ink.ink(scheme), lineWidth: PhoneBrand.ruleOpen)
                } else {
                    Capsule().fill(Ink.ink(scheme))
                }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Talking from anywhere

/// "Talk to 11am": for Shortcuts, Siri and the Action button. Opens the app listening.
struct TalkIntent: AppIntent {
    static var title: LocalizedStringResource = "Talk to 11am"
    static var description = IntentDescription("Opens 11am listening, to ask your Mac's team anything.")
    static var openAppWhenRun = true
    static let requested = Notification.Name("ElevenTalkRequested")
    /// Set when the intent runs before the app's views are ready.
    static var pending = false

    @MainActor
    func perform() async throws -> some IntentResult {
        TalkIntent.pending = true
        NotificationCenter.default.post(name: TalkIntent.requested, object: nil)
        return .result()
    }
}

struct ElevenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TalkIntent(), phrases: ["Talk to \(.applicationName)", "Ask \(.applicationName)"],
                    shortTitle: "Talk to 11am", systemImageName: "waveform")
    }
}
