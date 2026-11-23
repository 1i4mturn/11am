import SwiftUI

// MARK: - The drop

/// Home on the iPhone is the drop: true black, the eleven agents and the 11 as circles, white notices, the apps as
/// pills, and "hold the 11 to talk".
struct DropHome: View {
    @EnvironmentObject private var model: PhoneModel

    var body: some View {
        ZStack(alignment: .top) {
            PhoneBrand.drop.ignoresSafeArea()
            PhoneTooth().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    circles
                    notices
                    apps
                    Text("hold the 11 to talk")
                        .font(BrandFace.label(13))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Text("the drop · \(Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))")
                .font(BrandFace.label(13))
            Spacer()
            Image("wordmark-solid")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 18)
                .accessibilityLabel("11am")
        }
    }

    /// Agents with something for you are white: Leo with the brief or a meeting soon, Bolton with things on their way.
    private var lit: Set<String> {
        var codes: Set<String> = []
        if model.brief != nil { codes.insert("le") }
        if model.outbox.contains(where: { $0.status == .waiting }) { codes.insert("bn") }
        if !model.energy.isEmpty { codes.insert("hr") }
        return codes
    }

    private var circles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 14) {
            ForEach(PhoneAgents.order, id: \.self) { code in
                Button {
                    model.open(PhoneModel.screen(for: code))
                } label: {
                    PhoneAgentCircle(code: code, size: 48, style: lit.contains(code) ? .paper : .sheetInk)
                        .frame(minWidth: PhoneBrand.hit, minHeight: PhoneBrand.hit)
                }
                .buttonStyle(.plain)
                .accessibilityHint(PhoneAgents.role(code))
            }
            // The twelfth: the 11 with its two rings. Hold it to talk; a tap starts talking too.
            TalkCircle(size: 48)
                .onLongPressGesture(minimumDuration: 0.25) { model.startTalking() }
                .onTapGesture { model.startTalking() }
                .accessibilityLabel("Talk to 11am")
                .accessibilityAddTraits(.isButton)
        }
        .padding(.vertical, 6)
    }

    private struct Notice: Identifiable {
        var id: String
        var agent: String
        var text: String
        var action: String
        var open: PhoneTab
    }

    private var noticeList: [Notice] {
        var list: [Notice] = []
        if let brief = model.brief {
            if let next = brief.events.first(where: { $0.end > Date() }) {
                list.append(Notice(id: "event", agent: "le", text: "\(next.title) at \(next.start.formatted(date: .omitted, time: .shortened))",
                                   action: "Open", open: .today))
            }
            list.append(Notice(id: "brief", agent: "le", text: "your brief is ready", action: "Read", open: .today))
        } else {
            list.append(Notice(id: "pair", agent: "le", text: "your brief comes from your Mac once they're paired", action: "Pair", open: .mac))
        }
        let latest = model.reading
        if let reading = EnergyInsight.reading(today: latest.today, yesterday: latest.yesterday, baseline: latest.baseline) {
            list.append(Notice(id: "energy", agent: "hr", text: reading.headline.prefix(1).lowercased() + reading.headline.dropFirst(), action: "Open", open: .energy))
        }
        let waiting = model.outbox.filter { $0.status == .waiting }.count
        if waiting > 0 {
            list.append(Notice(id: "outbox", agent: "bn", text: waiting == 1 ? "1 capture waiting for your Mac" : "\(waiting) captures waiting for your Mac",
                               action: "Open", open: .capture))
        }
        return Array(list.prefix(3))
    }

    private var notices: some View {
        VStack(spacing: 8) {
            ForEach(noticeList) { notice in
                HStack(spacing: 12) {
                    (Text(PhoneAgents.name(notice.agent)).font(.brand(size: 15, weight: .semibold))
                        + Text(" · \(notice.text)").font(.brand(size: 15)))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button(notice.action) { model.open(notice.open) }
                        .font(.brand(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 34)
                        .background(Capsule().fill(PhoneBrand.inkHex))
                }
                .foregroundStyle(PhoneBrand.inkHex)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: PhoneBrand.radiusNotice, style: .continuous).fill(Color.white))
            }
        }
    }

    private var apps: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PhoneTab.allCases) { tab in
                    Button(tab.title) { model.open(tab) }
                        .font(.brand(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: PhoneBrand.hit)
                        .background(Capsule().fill(PhoneBrand.sheetInk))
                }
            }
        }
    }
}

/// The 11 in a white circle with two soft rings; a halo spreads behind it while it listens.
struct TalkCircle: View {
    var size: CGFloat = 48
    var halo = false

    var body: some View {
        PhoneAgentCircle(code: "11", size: size, style: .paper)
            .background {
                Circle().stroke(Color.white.opacity(0.28), lineWidth: 6).padding(-3)
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 7).padding(-9.5)
            }
            .background {
                if halo {
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0.5), .clear], center: .center,
                                             startRadius: 0, endRadius: size * 1.2))
                        .frame(width: size * 2.6, height: size * 2.6)
                        .blur(radius: 14)
                }
            }
            .frame(minWidth: PhoneBrand.hit, minHeight: PhoneBrand.hit)
    }
}

// MARK: - An app's screen

/// An app as a screen: the ink title bar in Courier (`leo · today`), "pull down for the drop", the app, and the puck
/// small in the corner.
struct AppScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.colorScheme) private var scheme
    @State private var pull: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Group {
                switch model.tab {
                case .today: TodayScreen()
                case .energy: EnergyScreen()
                case .capture: CaptureScreen()
                case .mac: MacScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Ink.paper(scheme))
        }
        .offset(y: pull)
        .overlay(alignment: .bottomTrailing) {
            PhonePuck()
                .padding(.trailing, 18)
                .padding(.bottom, 64)
        }
    }

    private var titleBar: some View {
        VStack(spacing: 3) {
            Text("\(PhoneAgents.name(model.tab.agent).lowercased()) · \(model.tab.title.lowercased())")
                .font(BrandFace.label(14))
            Text("pull down for the drop")
                .font(BrandFace.label(11))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(PhoneBrand.inkHex.ignoresSafeArea(edges: .top))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in pull = max(0, value.translation.height * 0.6) }
                .onEnded { value in
                    if value.translation.height > 80 { model.showDrop() }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { pull = 0 }
                }
        )
        .onTapGesture(count: 2) { model.showDrop() }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Pull down, or double-tap, for the drop")
        .accessibilityAction(named: "Back to the drop") { model.showDrop() }
    }
}

/// The puck, small: the 11 on ink in the corner of every screen. Tap or hold it to talk.
struct PhonePuck: View {
    @EnvironmentObject private var model: PhoneModel

    var body: some View {
        PhoneAgentCircle(code: "11", size: 56, style: .ink)
            .overlay { PhoneTooth().clipShape(Circle()) }
            .shadow(color: .black.opacity(0.1), radius: 2, y: 2)
            .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
            .frame(minWidth: PhoneBrand.hit, minHeight: PhoneBrand.hit)
            .contentShape(Circle())
            .onTapGesture { model.startTalking() }
            .onLongPressGesture(minimumDuration: 0.25) { model.startTalking() }
            .accessibilityLabel("Talk to 11am")
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Talking

/// The note that opens to talk: it listens, writes out what it heard on this iPhone, and asks your Mac's team.
struct TalkSheet: View {
    @EnvironmentObject private var model: PhoneModel
    @StateObject private var recorder = VoiceRecorder()
    @State private var heard = ""
    @State private var writing = false

    private var exchange: AskExchange? { model.exchanges.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())) · \(recorder.isRecording ? "listening" : "you")")
                    .font(BrandFace.label(13))
                Spacer()
            }
            HStack(alignment: .center, spacing: 18) {
                TalkCircle(size: 52, halo: recorder.isRecording)
                    .padding(10)
                Text(recorder.isRecording ? "Listening…" : (writing ? "Writing it down…" : (model.talkQuestion ?? "Ask the team anything.")))
                    .font(BrandFace.heading(24))
                    .tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            if let exchange, !recorder.isRecording, model.talkQuestion != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("leo · chief of staff").font(BrandFace.label(12))
                    Text(exchange.answer.isEmpty ? "Thinking…" : exchange.answer)
                        .font(.brand(size: 16))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(PhoneBrand.inkHex)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: PhoneBrand.radiusNotice, style: .continuous).fill(Color.white))
            }
            Spacer(minLength: 0)
            Button {
                if recorder.isRecording { finish() } else { start() }
            } label: {
                Text(recorder.isRecording ? "Send" : "Talk")
            }
            .buttonStyle(InkButtonStyle())
            .disabled(writing)
        }
        .padding(20)
        .background(PhoneBrand.drop.ignoresSafeArea())
        .foregroundStyle(.white)
        .presentationDetents([.medium, .large])
        .presentationBackground(PhoneBrand.drop)
        .environment(\.colorScheme, .dark)
        .task {
            if model.talkQuestion == nil { start() }
        }
        .onDisappear {
            _ = recorder.stop()
            LiveActivities.listening(false)
            model.talkQuestion = nil
        }
    }

    private func start() {
        Task {
            if !(await recorder.start()) {
                model.notice = "11am needs the microphone to listen (Settings › 11am)."
            } else {
                LiveActivities.listening(true)
            }
        }
    }

    private func finish() {
        guard let url = recorder.stop() else { return }
        writing = true
        LiveActivities.listening(false)
        Task {
            let text = await VoiceRecorder.transcribe(url)
            writing = false
            guard !text.isEmpty else {
                model.notice = "Didn't catch that. Try again a little closer."
                return
            }
            model.talkQuestion = text
            model.ask(text)
        }
    }
}
