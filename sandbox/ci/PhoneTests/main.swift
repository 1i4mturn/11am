import CryptoKit
import Foundation

// Checks what the iPhone and the Mac share: Energy (days, your usual, what last night means) and the link
// (pairing codes, sealed messages, framing, and a real connection on this machine, by address and by Bonjour).

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}

func waitFor(_ seconds: Double = 10, until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    return condition()
}

var sydney = Calendar(identifier: .gregorian)
sydney.timeZone = TimeZone(identifier: "Australia/Sydney")!
func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    sydney.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

// MARK: Energy

check(EnergyDay.key(at(5, 7), calendar: sydney) == "2026-11-05" && EnergyDay.date("2026-11-05", calendar: sydney) == at(5, 0), "Days by date")
check(EnergyDay.minutesAfterNoon(at(4, 23, 30), calendar: sydney) == 690 && EnergyDay.minutesAfterNoon(at(5, 0, 30), calendar: sydney) == 750
      && EnergyDay.minutesAfterNoon(at(5, 13), calendar: sydney) == 60, "Bedtimes either side of midnight line up")
check(EnergyFormat.duration(340) == "5 h 40 m" && EnergyFormat.duration(420) == "7 h" && EnergyFormat.duration(25) == "25 m", "Durations")
check(EnergyFormat.gap(65) == "about an hour" && EnergyFormat.gap(40) == "40 minutes" && EnergyFormat.gap(150) == "about 2.5 hours", "Gaps in words")
check(EnergyFormat.clock(minutesAfterNoon: 690) == "11:30 pm" && EnergyFormat.clock(minutesAfterNoon: 750) == "12:30 am", "Times of day")

let sample = EnergySample.days(28, ending: at(5, 7), calendar: sydney)
check(sample.count == 28 && sample.last?.day == "2026-11-05" && sample.first?.day == "2026-10-09", "Sample days end today, oldest first")
let latest = EnergyInsight.latest(sample, today: at(5, 7), calendar: sydney)
check(latest.today?.sleepMinutes == 340 && latest.yesterday?.steps == 3_150 && latest.baseline.nights == 27, "Today, yesterday and four weeks of usual")
let usualSleep = latest.baseline.sleepMinutes ?? 0
check(usualSleep > 400 && usualSleep < 470 && (latest.baseline.restingHeartRate ?? 0) > 53 && (latest.baseline.restingHeartRate ?? 0) < 59,
      "Your usual from the sample (\(EnergyFormat.duration(usualSleep)), resting \(Int(latest.baseline.restingHeartRate ?? 0)))")
if let reading = EnergyInsight.reading(today: latest.today, yesterday: latest.yesterday, baseline: latest.baseline, calendar: sydney) {
    check(reading.tone == .easy && reading.headline == "Short night" && reading.detail.contains("less than your usual"),
          "A short night reads as one (\(reading.detail))")
    check(reading.detail.contains("working harder than usual") && reading.detail.contains("Later to bed"), "…with the body's signs and a late bedtime")
    check(reading.suggestions.contains { $0.contains("after 10") } && reading.suggestions.contains { $0.contains("quiet on your feet") },
          "…and what to do about it")
} else {
    check(false, "A short night reads as one")
}
var rested = latest.today!
rested.sleepMinutes = usualSleep + 60
rested.restingHeartRate = latest.baseline.restingHeartRate
rested.heartRateVariability = latest.baseline.heartRateVariability
rested.bedtime = nil
var active = latest.yesterday!
active.steps = latest.baseline.steps
let good = EnergyInsight.reading(today: rested, yesterday: active, baseline: latest.baseline)
check(good?.tone == .good && good?.headline == "Good night's sleep", "A long night reads as good")
rested.sleepMinutes = usualSleep + 5
let usual = EnergyInsight.reading(today: rested, yesterday: active, baseline: latest.baseline)
check(usual?.tone == .usual && usual?.headline == "Usual night" && usual?.suggestions.isEmpty == true, "An ordinary night says so, without fuss")
check(EnergyInsight.reading(today: nil, yesterday: nil, baseline: latest.baseline) == nil, "No data, nothing to say")
let firstNight = EnergyInsight.reading(today: DayEnergy(day: "2026-11-05", sleepMinutes: 450), yesterday: nil, baseline: EnergyBaseline([]))
check(firstNight?.detail == "7 h 30 m asleep.", "With no history it just reports")
let facts = EnergyInsight.briefFacts(today: latest.today, yesterday: latest.yesterday, baseline: latest.baseline, calendar: sydney) ?? ""
check(facts.hasPrefix("Slept 5 h 40 m (usual ") && facts.contains("3,150 steps yesterday") && facts.contains("Short night."), "Facts for Leo's brief (\(facts.prefix(70))…)")
let merged = EnergyDay.merge([DayEnergy(day: "2026-11-01", steps: 100), DayEnergy(day: "2026-11-02", steps: 200)],
                             [DayEnergy(day: "2026-11-02", steps: 250), DayEnergy(day: "2026-11-03", steps: 300)])
check(merged.map(\.day) == ["2026-11-01", "2026-11-02", "2026-11-03"] && merged[1].steps == 250, "Newer days replace older ones")
check((try? JSONDecoder().decode([DayEnergy].self, from: JSONEncoder().encode(sample))) == sample, "Days travel as JSON unchanged")

// MARK: Pairing and the wire

let pairing = LinkPairing.make(macName: "Liam's MacBook Air")
check(pairing.key.count == 32 && pairing.service == "11am on Liam's MacBook Air", "A pairing has a fresh 256-bit key")
if let url = pairing.url {
    check(url.absoluteString.hasPrefix("elevenam://pair?d=") && LinkPairing(url: url) == pairing && LinkPairing(text: " \(url.absoluteString)\n") == pairing,
          "The QR link carries the pairing")
} else {
    check(false, "The QR link carries the pairing")
}
check(LinkPairing(text: "https://example.com/pair?d=abc") == nil && LinkPairing(text: "elevenam://pair?d=bm9wZQ") == nil, "Anything else isn't a pairing")
check(LinkPairing.make(macName: "x").key != LinkPairing.make(macName: "x").key, "Each pairing gets its own key")

let key = pairing.symmetricKey
let capture = LinkCapture(kind: .scan, destination: .receipt, title: "Receipt", text: "Cafe Lune $14.50",
                          attachments: [LinkAttachment(name: "Receipt.pdf", kind: "pdf", data: Data((0..<5_000).map { UInt8($0 % 251) }))])
let messages: [LinkMessage] = [
    .hello(device: "iPhone", pairing: pairing.id), .welcome(macName: "Mac"), .energy(Array(sample.suffix(3))), .capture(capture),
    .received(capture.id, where: "Notes"), .brief(LinkBrief(macName: "Mac", written: at(5, 6), text: "Light day.",
    events: [LinkEvent(title: "Kickoff", start: at(5, 10), end: at(5, 11), location: "Zoom")])),
    .ask(id: UUID(), question: "What's next?"), .answer(id: UUID(), text: "Kickoff at 10.", done: true), .ping, .pong,
]
var allRoundTrip = true
for message in messages {
    guard let frame = try? LinkWire.seal(message, key: key) else { allRoundTrip = false; continue }
    var reader = LinkWire.Reader()
    reader.append(frame)
    guard let body = try? reader.next(), let opened = try? LinkWire.open(body, key: key), opened == message else { allRoundTrip = false; continue }
}
check(allRoundTrip, "Every kind of message seals and opens")
let sealed = try! LinkWire.seal(.ping, key: key)
check((try? LinkWire.open(sealed.dropFirst(4), key: SymmetricKey(size: .bits256))) == nil, "The wrong key can't open a message")
var tampered = sealed
tampered[tampered.count - 3] ^= 0xFF
check((try? LinkWire.open(tampered.dropFirst(4), key: key)) == nil, "A changed message is refused")
let first = try! LinkWire.seal(.ping, key: key), second = try! LinkWire.seal(.pong, key: key)
var trickle = LinkWire.Reader()
var opened: [LinkMessage] = []
for byte in first + second {
    trickle.append(Data([byte]))
    while let body = try? trickle.next() { opened.append(try! LinkWire.open(body, key: key)) }
}
check(opened == [.ping, .pong], "Frames come back whole from a trickle of bytes")
var huge = LinkWire.Reader()
huge.append(Data([0x7F, 0xFF, 0xFF, 0xFF]))
check((try? huge.next()) == nil, "A frame claiming to be enormous is refused")
check(first != (try! LinkWire.seal(.ping, key: key)), "The same message seals differently each time")

// MARK: A real connection on this Mac

final class Box<T> { var value: T? }

func loopback(serverKey: SymmetricKey, clientKey: SymmetricKey, send: [LinkMessage]) -> (serverGot: [LinkMessage], clientGot: [LinkMessage], serverClosed: Bool)? {
    let server = LinkServer(key: serverKey)
    let port = Box<UInt16>()
    let serverChannel = Box<LinkChannel>()
    var serverGot: [LinkMessage] = []
    var clientGot: [LinkMessage] = []
    var serverClosed = false
    server.onReady = { port.value = $0 }
    server.onChannel = { channel in
        serverChannel.value = channel
        channel.onMessage = { message in
            serverGot.append(message)
            if case .hello = message { channel.send(.welcome(macName: "Test Mac")) }
        }
        channel.onState = { state in if case .closed = state { serverClosed = true } }
    }
    try? server.start(name: nil)
    guard waitFor(5, until: { port.value != nil }), let listening = port.value else { return nil }
    let client = LinkClient(pairing: LinkPairing(id: pairing.id, macName: "Test Mac", service: "", key: clientKey.withUnsafeBytes { Data($0) }))
    let clientChannel = Box<LinkChannel>()
    client.onChannel = { channel in
        clientChannel.value = channel
        channel.onMessage = { clientGot.append($0) }
        channel.onState = { state in
            if state == .ready { send.forEach { channel.send($0) } }
        }
    }
    client.connect(host: "127.0.0.1", port: listening)
    _ = waitFor(8) { serverGot.count >= send.count || serverClosed }
    _ = waitFor(2) { !clientGot.isEmpty || serverClosed }
    clientChannel.value?.close()
    server.stop()
    return (serverGot, clientGot, serverClosed)
}

let bigCapture = LinkCapture(kind: .photo, title: "Whiteboard", text: "",
                             attachments: [LinkAttachment(name: "Whiteboard.jpeg", kind: "jpeg", data: Data((0..<3_000_000).map { UInt8(($0 * 7) % 256) }))])
if let result = loopback(serverKey: key, clientKey: key, send: [.hello(device: "Test iPhone", pairing: pairing.id), .capture(bigCapture), .energy(sample)]) {
    check(result.serverGot.count == 3 && result.serverGot[1] == .capture(bigCapture) && result.serverGot[2] == .energy(sample),
          "An iPhone and a Mac talk over the network, a 3 MB photo included")
    check(result.clientGot.first == .welcome(macName: "Test Mac"), "…and the Mac answers")
} else {
    check(false, "The Mac listens on the network")
}
if let stranger = loopback(serverKey: key, clientKey: SymmetricKey(size: .bits256), send: [.hello(device: "Stranger", pairing: pairing.id)]) {
    check(stranger.serverGot.isEmpty && stranger.clientGot.isEmpty && stranger.serverClosed, "A device without the key gets nothing and is cut off")
} else {
    check(false, "A device without the key is refused")
}

// Bonjour: the phone finds the Mac by name. CI machines don't always run multicast DNS, so this one reports what happened
// in detail, and counts as a failure only when discovery worked but the connection didn't.
let named = LinkPairing.make(macName: "CI Mac \(Int.random(in: 1_000...9_999))")
let bonjourServer = LinkServer(key: named.symmetricKey)
var bonjourHello: LinkMessage?
var steps: [String] = []
bonjourServer.onReady = { steps.append("advertising on port \($0)") }
bonjourServer.onFailure = { steps.append("listener failed: \($0)") }
bonjourServer.onChannel = { channel in
    steps.append("Mac accepted a connection")
    channel.onMessage = { bonjourHello = $0 }
}
do {
    try bonjourServer.start(name: named.service)
    _ = waitFor(3) { !steps.isEmpty }
    let finder = LinkClient(pairing: named)
    var failure: String?
    finder.onFailure = { failure = $0 }
    finder.onChannel = { channel in
        steps.append("found \(channel.endpointDescription)")
        channel.onState = { state in
            steps.append("connection \(state)")
            if state == .ready { channel.send(.hello(device: "Bonjour iPhone", pairing: named.id)) }
        }
    }
    finder.connect(timeout: 8)
    _ = waitFor(14) { bonjourHello != nil || failure != nil }
    let found = steps.contains { $0.hasPrefix("found") }
    if bonjourHello == .hello(device: "Bonjour iPhone", pairing: named.id) {
        check(true, "The iPhone finds the Mac on the network by name")
    } else if found {
        check(false, "Found the Mac by name but couldn't talk: \(steps.joined(separator: "; "))")
    } else {
        print("NOTE Bonjour discovery isn't available on this machine: \((steps + [failure ?? "no answer"]).joined(separator: "; "))")
    }
    bonjourServer.stop()
} catch {
    print("NOTE Bonjour listener couldn't start here: \(error.localizedDescription)")
}

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
