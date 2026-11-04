import Charts
import PhotosUI
import SwiftUI

// MARK: Today

struct TodayScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.colorScheme) private var scheme
    @State private var question = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "today", subtitle: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)), monogram: "le")
                let latest = model.reading
                if let reading = EnergyInsight.reading(today: latest.today, yesterday: latest.yesterday, baseline: latest.baseline) {
                    Button { model.tab = .energy } label: { EnergyLine(reading: reading) }
                        .buttonStyle(.plain)
                }
                if let brief = model.brief {
                    BriefCard(brief: brief)
                } else {
                    Card {
                        Label2(text: "Leo's brief")
                        Text(model.pairing == nil
                             ? "Pair with 11am on your Mac to see your brief and your day here."
                             : "Your brief arrives when your Mac and iPhone are on the same Wi-Fi.")
                            .font(.system(size: 15))
                            .foregroundStyle(Ink.secondary(scheme))
                        if model.pairing == nil {
                            Button("Pair with your Mac") { model.tab = .mac }
                                .buttonStyle(InkButtonStyle())
                        }
                    }
                }
                Card {
                    Label2(text: "Ask your Mac")
                    HStack(spacing: 8) {
                        TextField("What do I need for the Acme review?", text: $question, axis: .vertical)
                            .font(.system(size: 15))
                            .lineLimit(1...4)
                            .submitLabel(.send)
                            .onSubmit(send)
                        Button(action: send) {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 26))
                        }
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.well(scheme)))
                    ForEach(model.exchanges) { exchange in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exchange.question)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Ink.ink(scheme))
                            Text(exchange.answer.isEmpty ? "Thinking on your Mac…" : exchange.answer)
                                .font(.system(size: 14.5))
                                .foregroundStyle(exchange.answer.isEmpty ? Ink.tertiary(scheme) : Ink.secondary(scheme))
                        }
                        .padding(.top, 4)
                    }
                    Text("Answered by your Mac's brain, with your files and notes. Nothing goes anywhere else unless you've allowed cloud help on the Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.tertiary(scheme))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Ink.paper(scheme).ignoresSafeArea())
    }

    private func send() {
        model.ask(question)
        question = ""
    }
}

struct EnergyLine: View {
    @Environment(\.colorScheme) private var scheme
    var reading: EnergyInsight.Reading

    var body: some View {
        Card {
            HStack(spacing: 8) {
                Circle().fill(Ink.tone(reading.tone)).frame(width: 9, height: 9)
                Text(reading.headline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Ink.ink(scheme))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.tertiary(scheme))
            }
            if !reading.detail.isEmpty {
                Text(reading.detail)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Ink.secondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let first = reading.suggestions.first {
                Text(first)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Ink.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct BriefCard: View {
    @Environment(\.colorScheme) private var scheme
    var brief: LinkBrief

    var body: some View {
        Card {
            HStack {
                Label2(text: "Leo's brief")
                Spacer()
                if let written = brief.written {
                    Text("\(written.formatted(date: .omitted, time: .shortened)) · \(brief.macName)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Ink.tertiary(scheme))
                }
            }
            Text(brief.text.isEmpty ? "Leo hasn't written today's brief yet." : brief.text)
                .font(.system(size: 16))
                .lineSpacing(2)
                .foregroundStyle(Ink.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if !brief.events.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(Array(brief.events.enumerated()), id: \.offset) { _, event in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 13.5).monospacedDigit())
                            .foregroundStyle(Ink.tertiary(scheme))
                            .frame(width: 70, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Ink.ink(scheme))
                            if let location = event.location, !location.isEmpty {
                                Text(location)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Ink.tertiary(scheme))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: Energy

struct EnergyScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "energy", subtitle: model.usingSample ? "Sample data, for trying it out" : "From Apple Health, compared with your own usual", monogram: "le")
                if model.energy.isEmpty {
                    ConnectHealthCard()
                } else {
                    let latest = model.reading
                    LastNightCard(today: latest.today, baseline: latest.baseline,
                                  reading: EnergyInsight.reading(today: latest.today, yesterday: latest.yesterday, baseline: latest.baseline))
                    SleepChart(days: Array(model.energy.suffix(14)), usual: latest.baseline.sleepMinutes)
                    StepsChart(days: Array(model.energy.suffix(14)), usual: latest.baseline.steps)
                    HeartChart(days: Array(model.energy.suffix(28)), baseline: latest.baseline)
                    WorkoutsCard(days: Array(model.energy.suffix(7)))
                    Card {
                        Label2(text: "Private by design")
                        Text("Health data stays on this iPhone. Only a short daily summary (sleep, steps, heart rate) goes to your own Mac, sealed, over your own network. It's never sent to a cloud model unless you say so on the Mac. None of this is medical advice.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Ink.secondary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                        if model.pairing != nil && !model.usingSample {
                            Button("Send to my Mac now") { model.sendEnergyNow() }
                                .buttonStyle(InkButtonStyle(secondary: true))
                        }
                        if model.usingSample {
                            Button("Use my Apple Health instead") {
                                model.useSample(false)
                                Task { await model.connectHealth() }
                            }
                            .buttonStyle(InkButtonStyle(secondary: true))
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .refreshable { await model.refreshHealth() }
        .background(Ink.paper(scheme).ignoresSafeArea())
    }
}

private struct ConnectHealthCard: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Card {
            Image(systemName: "heart.text.square")
                .font(.system(size: 34))
                .foregroundStyle(Ink.accent)
            Text("See how you slept and how your body's doing, against your own usual.")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Ink.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Text("Leo reads sleep, steps, active energy, exercise, stand hours, resting heart rate, heart-rate variability and workouts from Apple Health, and plans your day around a short night. 11am only reads; it never writes to Health.")
                .font(.system(size: 14.5))
                .foregroundStyle(Ink.secondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if model.healthState == .unavailable {
                Text("Apple Health isn't available on this device.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Ink.accent)
            } else {
                Button("Connect Apple Health") { Task { await model.connectHealth() } }
                    .buttonStyle(InkButtonStyle())
            }
            Button("Try it with sample data") { model.useSample(true) }
                .buttonStyle(InkButtonStyle(secondary: true))
        }
    }
}

private struct LastNightCard: View {
    @Environment(\.colorScheme) private var scheme
    var today: DayEnergy?
    var baseline: EnergyBaseline
    var reading: EnergyInsight.Reading?

    var body: some View {
        Card {
            HStack {
                Label2(text: "Last night")
                Spacer()
                if let reading {
                    Text(reading.headline)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Ink.tone(reading.tone))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Ink.tone(reading.tone).opacity(0.14)))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(today?.sleepMinutes.map(EnergyFormat.duration) ?? "No sleep recorded")
                    .font(.system(size: today?.sleepMinutes == nil ? 20 : 40, weight: .bold).monospacedDigit())
                    .tracking(-1)
                    .foregroundStyle(Ink.ink(scheme))
                if let usual = baseline.sleepMinutes {
                    Text("usual \(EnergyFormat.duration(usual))")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.tertiary(scheme))
                }
            }
            if let bed = today?.bedtime, let wake = today?.wakeTime {
                Text("Asleep \(bed.formatted(date: .omitted, time: .shortened)) to \(wake.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Ink.secondary(scheme))
            }
            if let reading {
                if !reading.detail.isEmpty {
                    Text(reading.detail)
                        .font(.system(size: 14.5))
                        .foregroundStyle(Ink.secondary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(reading.suggestions, id: \.self) { suggestion in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.tertiary(scheme))
                        Text(suggestion)
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(Ink.ink(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 0) {
                Stat(title: "Steps", value: today?.steps.map(EnergyFormat.number) ?? "–")
                Stat(title: "Resting HR", value: today?.restingHeartRate.map { "\(Int($0))" } ?? "–")
                Stat(title: "HRV", value: today?.heartRateVariability.map { "\(Int($0)) ms" } ?? "–")
            }
            .padding(.top, 4)
        }
    }
}

private struct Stat: View {
    @Environment(\.colorScheme) private var scheme
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundStyle(Ink.ink(scheme))
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(Ink.tertiary(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func shortDay(_ day: DayEnergy) -> Date { day.date ?? Date() }

private struct SleepChart: View {
    @Environment(\.colorScheme) private var scheme
    var days: [DayEnergy]
    var usual: Double?

    var body: some View {
        Card {
            Label2(text: "Sleep · two weeks")
            Chart {
                ForEach(days) { day in
                    if let minutes = day.sleepMinutes {
                        BarMark(x: .value("Night", shortDay(day), unit: .day), y: .value("Hours", minutes / 60))
                            .foregroundStyle(day.id == days.last?.id ? Ink.accent : Ink.ink(scheme).opacity(0.75))
                            .cornerRadius(4)
                    }
                }
                if let usual {
                    RuleMark(y: .value("Usual", usual / 60))
                        .foregroundStyle(Ink.tertiary(scheme))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("usual").font(.system(size: 10.5)).foregroundStyle(Ink.tertiary(scheme))
                        }
                }
            }
            .chartYAxis { AxisMarks(position: .leading, values: [0, 4, 8]) { value in
                AxisGridLine().foregroundStyle(Ink.edge(scheme))
                AxisValueLabel { if let hours = value.as(Int.self) { Text("\(hours) h") } }
            } }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            } }
            .frame(height: 150)
        }
    }
}

private struct StepsChart: View {
    @Environment(\.colorScheme) private var scheme
    var days: [DayEnergy]
    var usual: Double?

    var body: some View {
        Card {
            Label2(text: "Steps · two weeks")
            Chart {
                ForEach(days) { day in
                    if let steps = day.steps {
                        BarMark(x: .value("Day", shortDay(day), unit: .day), y: .value("Steps", steps))
                            .foregroundStyle(Ink.ink(scheme).opacity(day.id == days.last?.id ? 0.35 : 0.75))
                            .cornerRadius(4)
                    }
                }
                if let usual {
                    RuleMark(y: .value("Usual", usual))
                        .foregroundStyle(Ink.tertiary(scheme))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 3)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .frame(height: 130)
            Text("Today so far is the lighter bar.")
                .font(.system(size: 11.5))
                .foregroundStyle(Ink.tertiary(scheme))
        }
    }
}

private struct HeartChart: View {
    @Environment(\.colorScheme) private var scheme
    var days: [DayEnergy]
    var baseline: EnergyBaseline

    var body: some View {
        Card {
            Label2(text: "Heart · four weeks")
            HStack(alignment: .top, spacing: 14) {
                mini(title: "Resting heart rate", unit: "bpm", values: days.compactMap { day in day.restingHeartRate.map { (shortDay(day), $0) } },
                     usual: baseline.restingHeartRate, colour: Ink.accent)
                mini(title: "Heart-rate variability", unit: "ms", values: days.compactMap { day in day.heartRateVariability.map { (shortDay(day), $0) } },
                     usual: baseline.heartRateVariability, colour: Ink.ink(scheme))
            }
            Text("Lower resting heart rate and higher variability than your usual tend to mean you're well recovered. These compare you with you; they aren't medical readings.")
                .font(.system(size: 11.5))
                .foregroundStyle(Ink.tertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mini(title: String, unit: String, values: [(Date, Double)], usual: Double?, colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ink.secondary(scheme))
            if let last = values.last {
                Text("\(Int(last.1)) \(unit)")
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Ink.ink(scheme))
            }
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Day", point.0, unit: .day), y: .value(title, point.1))
                        .foregroundStyle(colour)
                        .interpolationMethod(.catmullRom)
                }
                if let usual {
                    RuleMark(y: .value("Usual", usual))
                        .foregroundStyle(Ink.tertiary(scheme))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 70)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkoutsCard: View {
    @Environment(\.colorScheme) private var scheme
    var days: [DayEnergy]

    var body: some View {
        let workouts = days.flatMap { day in day.workouts.map { (day, $0) } }
        Card {
            Label2(text: "This week")
            HStack(spacing: 0) {
                Stat(title: "Exercise", value: EnergyFormat.duration(days.compactMap(\.exerciseMinutes).reduce(0, +)))
                Stat(title: "Active energy", value: "\(EnergyFormat.number(days.compactMap(\.activeEnergy).reduce(0, +))) kcal")
                Stat(title: "Workouts", value: "\(workouts.count)")
            }
            ForEach(Array(workouts.enumerated()), id: \.offset) { _, entry in
                HStack {
                    Text(entry.1.kind)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Ink.ink(scheme))
                    Spacer()
                    Text("\(EnergyFormat.duration(entry.1.minutes)) · \(shortDay(entry.0).formatted(.dateTime.weekday(.abbreviated)))")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Ink.tertiary(scheme))
                }
            }
        }
    }
}

// MARK: Capture

/// A capture being looked over before it goes.
struct CaptureDraft: Identifiable {
    let id = UUID()
    var kind: LinkCapture.Kind
    var title: String
    var text: String
    var attachments: [LinkAttachment]
    var destination: LinkCapture.Destination = .notes
    var destinations: [LinkCapture.Destination] = [.notes]
    var preview: UIImage?
}

struct CaptureScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.colorScheme) private var scheme
    @State private var scanning = false
    @State private var shooting = false
    @State private var recording = false
    @State private var writing = false
    @State private var linking = false
    @State private var library: PhotosPickerItem?
    @State private var draft: CaptureDraft?
    @State private var working: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "capture", subtitle: "Scan it, snap it or say it. It goes to your Mac.", monogram: "bn")
                LazyVGrid(columns: columns, spacing: 12) {
                    Tile(symbol: "doc.viewfinder", title: "Scan a document", detail: "Text recognised, saved as a PDF") {
                        if DocumentScanner.isAvailable { scanning = true } else { model.notice = "Scanning needs the camera, so it works on an iPhone, not here." }
                    }
                    Tile(symbol: "camera", title: "Photo", detail: "A whiteboard, a receipt, anything") {
                        if CameraPicker.isAvailable { shooting = true } else { model.notice = "There's no camera here. Choose from your photos instead." }
                    }
                    Tile(symbol: "waveform", title: "Voice note", detail: "Transcribed on this iPhone") { recording = true }
                    Tile(symbol: "square.and.pencil", title: "Note", detail: "Straight into Notes") { writing = true }
                    Tile(symbol: "link", title: "Link", detail: "From the clipboard") { linking = true }
                    PhotosPicker(selection: $library, matching: .images) {
                        TileFace(symbol: "photo.on.rectangle", title: "From Photos", detail: "Pick a picture you've taken")
                    }
                    .buttonStyle(.plain)
                }
                if let working {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(working).font(.system(size: 14)).foregroundStyle(Ink.secondary(scheme))
                    }
                }
                if !model.outbox.isEmpty {
                    Label2(text: "Recent")
                        .padding(.top, 4)
                    ForEach(model.outbox) { item in
                        OutboxRow(item: item)
                            .contextMenu {
                                Button("Remove from this list", role: .destructive) { model.remove(item) }
                            }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Ink.paper(scheme).ignoresSafeArea())
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner(onFinish: { images in
                scanning = false
                Task { await scanned(images) }
            }, onCancel: { scanning = false })
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $shooting) {
            CameraPicker { image in
                shooting = false
                if let image { photographed(image) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $recording) { VoiceSheet { draft = $0 } }
        .sheet(isPresented: $writing) { NoteSheet { model.add($0) } }
        .sheet(isPresented: $linking) { LinkSheet { model.add($0) } }
        .sheet(item: $draft) { draft in ReviewSheet(draft: draft) }
        .onChange(of: library) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { photographed(image) }
                library = nil
            }
        }
    }

    private func scanned(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        working = "Reading the text…"
        let text = await TextReader.text(in: images)
        working = nil
        let title = text.split(separator: "\n").first.map { String($0.prefix(60)) } ?? "Scan"
        draft = CaptureDraft(kind: .scan, title: title.isEmpty ? "Scan · \(CaptureFiles.stamp())" : title, text: text,
                             attachments: [LinkAttachment(name: "Scan \(CaptureFiles.stamp()).pdf", kind: "pdf", data: CaptureFiles.pdf(from: images))],
                             destination: .pdf, destinations: [.pdf, .notes, .receipt], preview: images.first)
    }

    private func photographed(_ image: UIImage) {
        guard let data = CaptureFiles.jpeg(image) else { return }
        working = "Looking for text…"
        Task {
            let text = await TextReader.text(in: [image])
            working = nil
            draft = CaptureDraft(kind: .photo, title: "Photo · \(CaptureFiles.stamp())", text: text,
                                 attachments: [LinkAttachment(name: "Photo \(CaptureFiles.stamp()).jpeg", kind: "jpeg", data: data)],
                                 destinations: [.notes, .receipt], preview: image)
        }
    }
}

private struct TileFace: View {
    @Environment(\.colorScheme) private var scheme
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Ink.ink(scheme))
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(Ink.ink(scheme))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Ink.tertiary(scheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Ink.card(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Ink.edge(scheme), lineWidth: 0.5))
        .contentShape(Rectangle())
    }
}

private struct Tile: View {
    var symbol: String
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) { TileFace(symbol: symbol, title: title, detail: detail) }
            .buttonStyle(.plain)
    }
}

private struct OutboxRow: View {
    @Environment(\.colorScheme) private var scheme
    var item: OutboxItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Ink.secondary(scheme))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Ink.well(scheme)))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.capture.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.ink(scheme))
                    .lineLimit(1)
                Text(status)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.tertiary(scheme))
            }
            Spacer()
            Text(item.capture.created.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Ink.tertiary(scheme))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.card(scheme)))
    }

    private var symbol: String {
        switch item.capture.kind {
        case .scan: return "doc.viewfinder"
        case .photo: return "camera"
        case .voice: return "waveform"
        case .note: return "square.and.pencil"
        case .link: return "link"
        }
    }

    private var status: String {
        switch item.status {
        case .waiting: return "Waiting for your Mac"
        case .sent(let place): return "On your Mac · \(place)"
        }
    }
}

struct ReviewSheet: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State var draft: CaptureDraft

    var body: some View {
        NavigationStack {
            Form {
                if let preview = draft.preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section("Title") {
                    TextField("Title", text: $draft.title)
                }
                if draft.destinations.count > 1 {
                    Section("Send to") {
                        Picker("Send to", selection: $draft.destination) {
                            ForEach(draft.destinations, id: \.self) { destination in Text(destination.title).tag(destination) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section(draft.kind == .voice ? "What you said" : "Text found") {
                    TextEditor(text: $draft.text)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle(draft.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        model.add(LinkCapture(kind: draft.kind, destination: draft.destination, title: draft.title, text: draft.text,
                                              attachments: draft.attachments))
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}

private struct VoiceSheet: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @StateObject private var recorder = VoiceRecorder()
    @State private var transcribing = false
    var onDone: (CaptureDraft) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(recorder.isRecording ? "Listening" : (transcribing ? "Writing it down…" : "Voice note"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Ink.ink(scheme))
            Text(String(format: "%d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60))
                .font(.system(size: 48, weight: .light).monospacedDigit())
                .foregroundStyle(Ink.ink(scheme))
            Capsule()
                .fill(Ink.accent)
                .frame(width: max(12, CGFloat(recorder.level) * 240), height: 8)
                .animation(.easeOut(duration: 0.1), value: recorder.level)
            Button {
                if recorder.isRecording { finish() } else { Task { if !(await recorder.start()) { model.notice = "11am needs the microphone for voice notes (Settings › 11am)." } } }
            } label: {
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Ink.paper(scheme))
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(recorder.isRecording ? Ink.accent : Ink.ink(scheme)))
            }
            .disabled(transcribing)
            Text("Transcribed on this iPhone. The recording and the words go to Notes on your Mac.")
                .font(.system(size: 13))
                .foregroundStyle(Ink.tertiary(scheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 32)
        .presentationDetents([.medium])
        .onDisappear { _ = recorder.stop() }
    }

    private func finish() {
        guard let url = recorder.stop() else { return }
        transcribing = true
        Task {
            let text = await VoiceRecorder.transcribe(url)
            let data = (try? Data(contentsOf: url)) ?? Data()
            transcribing = false
            dismiss()
            onDone(CaptureDraft(kind: .voice, title: text.isEmpty ? "Voice note · \(CaptureFiles.stamp())" : String(text.prefix(60)), text: text,
                                attachments: [LinkAttachment(name: "Voice note \(CaptureFiles.stamp()).m4a", kind: "m4a", data: data)]))
        }
    }
}

private struct NoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool
    var onSend: (LinkCapture) -> Void

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .padding(.horizontal, 12)
                .navigationTitle("Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            let title = text.split(separator: "\n").first.map { String($0.prefix(60)) } ?? "Note"
                            onSend(LinkCapture(kind: .note, title: title, text: text))
                            dismiss()
                        }
                        .bold()
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { focused = true }
        }
    }
}

private struct LinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var link = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string ?? ""
    @State private var note = ""
    var onSend: (LinkCapture) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Link") {
                    TextField("https://", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Why you saved it (optional)") {
                    TextField("For the pricing page rewrite", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
                        let host = URL(string: trimmed)?.host ?? trimmed
                        onSend(LinkCapture(kind: .link, title: note.isEmpty ? host : note, text: note.isEmpty ? trimmed : "\(trimmed)\n\n\(note)"))
                        dismiss()
                    }
                    .bold()
                    .disabled(URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: Mac

struct MacScreen: View {
    @EnvironmentObject private var model: PhoneModel
    @Environment(\.colorScheme) private var scheme
    @State private var scanningCode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "your mac", subtitle: "Paired once, then they find each other on your Wi-Fi", monogram: nil)
                if let pairing = model.pairing {
                    Card {
                        HStack(spacing: 12) {
                            Image(systemName: "laptopcomputer")
                                .font(.system(size: 26))
                                .foregroundStyle(Ink.ink(scheme))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pairing.macName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Ink.ink(scheme))
                                HStack(spacing: 6) {
                                    Circle().fill(statusColour).frame(width: 7, height: 7)
                                    Text(statusText)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Ink.secondary(scheme))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        if !model.link.isConnected {
                            Button("Look again") {
                                model.disconnect()
                                model.connect()
                            }
                            .buttonStyle(InkButtonStyle())
                        }
                        Button("Send Energy now") { model.sendEnergyNow() }
                            .buttonStyle(InkButtonStyle(secondary: true))
                            .disabled(!model.link.isConnected)
                        Button("Unpair", role: .destructive) { model.unpair() }
                            .font(.system(size: 14.5, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                } else {
                    Card {
                        Label2(text: "Pair with your Mac")
                        Text("On your Mac, open 11am and choose Today › Pair your iPhone (or 11am › Settings › iPhone). Then scan the code it shows.")
                            .font(.system(size: 15))
                            .foregroundStyle(Ink.secondary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Scan the code") { scanningCode = true }
                            .buttonStyle(InkButtonStyle())
                            .disabled(!CodeScanner.isAvailable)
                        Button("Paste the pairing link") {
                            if let text = UIPasteboard.general.string, model.pair(with: text) {
                                model.notice = "Paired. Looking for your Mac…"
                            } else if UIPasteboard.general.string == nil {
                                model.notice = "Copy the pairing link on your Mac first (it arrives here by Universal Clipboard)."
                            }
                        }
                        .buttonStyle(InkButtonStyle(secondary: true))
                    }
                }
                Card {
                    Label2(text: "What goes between them")
                    Bullet("Your Mac sends Leo's brief and today's events.")
                    Bullet("This iPhone sends what you capture and a daily Energy summary from Health.")
                    Bullet("Ask questions that your Mac answers with its own brain.")
                    Text("Everything is sealed with a key made on your Mac and shown only in its pairing code. No server, no account; they talk directly on your network.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Ink.tertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Ink.paper(scheme).ignoresSafeArea())
        .sheet(isPresented: $scanningCode) {
            CodeScanner { text in
                scanningCode = false
                if model.pair(with: text) { model.notice = "Paired. Looking for your Mac…" }
            }
            .ignoresSafeArea()
        }
    }

    private var statusText: String {
        switch model.link {
        case .unpaired: return "Not paired"
        case .searching: return "Looking for it on this network…"
        case .connected: return "Connected"
        case .unreachable(let reason): return reason
        }
    }

    private var statusColour: Color {
        switch model.link {
        case .connected: return .green
        case .searching: return .orange
        default: return Ink.tertiary(scheme)
        }
    }
}

private struct Bullet: View {
    @Environment(\.colorScheme) private var scheme
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Ink.tertiary(scheme)).frame(width: 4, height: 4).offset(y: -3)
            Text(text)
                .font(.system(size: 14.5))
                .foregroundStyle(Ink.secondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
