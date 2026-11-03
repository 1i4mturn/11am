import AVFoundation
import Foundation

// Checks Cole's sound engine with generated signals: levels and loudness (EBU R 128 reference tones), filters,
// dynamics, silence detection and removal, time and pitch, waveforms and spectra, files, and multitrack edits.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}
func near(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool { abs(a - b) <= tolerance }
func db(_ amplitude: Float) -> Double { SoundMeter.decibels(amplitude) }
func level(_ sound: SoundBuffer, from: Double = 0.5) -> Double {
    let tail = sound.slice(min(from, sound.duration / 2), sound.duration)
    return db(SoundMeter.rms(tail.channels[0][...]))
}
func f(_ value: Double) -> String { String(format: "%.2f", value) }

// MARK: Basics

let tone = SoundBuffer.tone(1_000, seconds: 2, amplitude: 0.5)
check(tone.frames == 96_000 && near(tone.duration, 2, 0.0001) && near(Double(SoundMeter.peak(tone)), 0.5, 0.001), "A tone has the length and level asked for")
check(near(SoundMeter.decibels(0.5), -6.02, 0.01) && near(Double(SoundMeter.amplitude(-6.0206)), 0.5, 0.001), "Decibels both ways")
check(tone.withChannels(2).channelCount == 2 && tone.withChannels(2).withChannels(1).channels[0] == tone.channels[0], "Mono to stereo and back")
let resampled = tone.resampled(to: 44_100)
check(near(resampled.duration, 2, 0.001) && resampled.sampleRate == 44_100, "Resampling keeps the length")

// MARK: Loudness (EBU Tech 3341 test signals)

let reference = SoundBuffer.tone(1_000, seconds: 20, amplitude: SoundMeter.amplitude(-23), sampleRate: 48_000, channels: 2)
let referenceLoudness = SoundMeter.loudness(reference)
check(near(referenceLoudness, -23, 0.1), "Stereo 1 kHz at −23 dBFS measures −23 LUFS (\(f(referenceLoudness)))")
let mono = SoundBuffer.tone(1_000, seconds: 20, amplitude: SoundMeter.amplitude(-23), sampleRate: 48_000, channels: 1)
check(near(SoundMeter.loudness(mono), -26.01, 0.1), "Mono reads 3 dB lower (\(f(SoundMeter.loudness(mono))))")
let at44 = SoundBuffer.tone(1_000, seconds: 20, amplitude: SoundMeter.amplitude(-23), sampleRate: 44_100, channels: 2)
check(near(SoundMeter.loudness(at44), -23, 0.1), "…and the same at 44.1 kHz (\(f(SoundMeter.loudness(at44))))")
var gated = SoundBuffer.tone(1_000, seconds: 10, amplitude: SoundMeter.amplitude(-23), channels: 2)
gated.append(.silence(seconds: 10))
check(near(SoundMeter.loudness(gated), -23, 0.15), "Silence is gated out of the measurement (\(f(SoundMeter.loudness(gated))))")
let high = SoundMeter.loudness(.tone(10_000, seconds: 5, amplitude: 0.1, channels: 2))
let middle = SoundMeter.loudness(.tone(1_000, seconds: 5, amplitude: 0.1, channels: 2))
let low = SoundMeter.loudness(.tone(30, seconds: 5, amplitude: 0.1, channels: 2))
check(high - middle > 2.5 && middle - low > 1, "K-weighting hears treble more and deep bass less (\(f(high)), \(f(middle)), \(f(low)))")

// MARK: Gain

let normalised = SoundDSP.normalise(tone, peak: -1)
check(near(db(SoundMeter.peak(normalised)), -1, 0.01), "Normalise to −1 dBFS")
let podcast = SoundDSP.loudness(reference, target: -16, ceiling: -1)
check(near(SoundMeter.loudness(podcast), -16, 0.2) && db(SoundMeter.peak(podcast)) <= -0.99, "Loudness to −16 LUFS with peaks under −1 dBFS (\(f(SoundMeter.loudness(podcast))))")
let streaming = SoundDSP.loudness(SoundBuffer.tone(220, seconds: 6, amplitude: 0.05, channels: 2), target: -14, ceiling: -1)
check(near(SoundMeter.loudness(streaming), -14, 0.6), "…and to −14 LUFS for streaming (\(f(SoundMeter.loudness(streaming))))")
let quieter = SoundDSP.gain(tone, decibels: -6)
check(near(db(SoundMeter.peak(quieter)), db(0.5) - 6, 0.01), "Amplify by a set amount")
let faded = SoundDSP.fade(tone, in: 0.5, out: 0.5)
check(abs(faded.channels[0][0]) < 0.0001 && abs(faded.channels[0][faded.frames - 1]) < 0.0001 && near(level(faded.slice(0.8, 1.2), from: 0), level(tone.slice(0.8, 1.2), from: 0), 0.01),
      "Fades start and end silent and leave the middle alone")
check(SoundDSP.reverse(SoundDSP.reverse(tone)) == tone, "Reverse twice is the original")

// MARK: Filters

let hum = SoundBuffer.tone(50, seconds: 2, amplitude: 0.5)
let filteredHum = SoundDSP.filter(hum, [Biquad(.highPass, frequency: 120, sampleRate: 48_000)])
let filteredVoice = SoundDSP.filter(tone, [Biquad(.highPass, frequency: 120, sampleRate: 48_000)])
check(level(hum) - level(filteredHum) > 12 && abs(level(tone) - level(filteredVoice)) < 0.3,
      "The rumble filter takes 50 Hz hum down and leaves 1 kHz alone (\(f(level(hum) - level(filteredHum))) dB)")
let boost = EQBand(kind: .peak, frequency: 1_000, gain: 6, q: 1)
let boosted = SoundDSP.eq(tone, [boost])
check(near(level(boosted) - level(tone), 6, 0.4) && near(Biquad(.peak, frequency: 1_000, gain: 6, q: 1, sampleRate: 48_000).response(at: 1_000, sampleRate: 48_000), 6, 0.05),
      "A 6 dB bell at 1 kHz adds 6 dB there (\(f(level(boosted) - level(tone))))")
let shelf = Biquad(.highShelf, frequency: 4_000, gain: -6, sampleRate: 48_000)
check(near(shelf.response(at: 15_000, sampleRate: 48_000), -6, 0.6) && near(shelf.response(at: 200, sampleRate: 48_000), 0, 0.2), "A high shelf cuts the top and leaves the bottom")
let lowPass = Biquad(.lowPass, frequency: 1_000, sampleRate: 48_000)
check(lowPass.response(at: 8_000, sampleRate: 48_000) < -30, "A low-pass falls 12 dB an octave")

// MARK: Dynamics

let loud = SoundBuffer.tone(500, seconds: 3, amplitude: SoundMeter.amplitude(-6))
let compressed = SoundDSP.compressor(loud, threshold: -20, ratio: 4, attack: 0.005, release: 0.1)
let expected = -20 + (-6 - -20) / 4 - 3.01
check(near(level(compressed, from: 1), expected, 1.2), "The compressor holds a −6 dB tone near −16.5 dB peak (\(f(level(compressed, from: 1))) RMS, wanted \(f(expected)))")
let limited = SoundDSP.limiter(SoundDSP.gain(loud, decibels: 9), ceiling: -1)
check(db(SoundMeter.peak(limited)) <= -0.99, "The limiter keeps peaks under the ceiling (\(f(db(SoundMeter.peak(limited)))))")
var gateTest = SoundBuffer.tone(300, seconds: 1, amplitude: 0.3)
var hiss = SoundBuffer(sampleRate: 48_000, channelCount: 1, frames: 48_000)
for index in 0..<hiss.frames { hiss.channels[0][index] = Float.random(in: -0.001...0.001) }
gateTest.append(hiss)
gateTest.append(.tone(300, seconds: 1, amplitude: 0.3))
let gatedSound = SoundDSP.gate(gateTest, threshold: -45, reduction: -30)
check(level(gatedSound.slice(1.4, 1.9), from: 0) < level(gateTest.slice(1.4, 1.9), from: 0) - 20
      && abs(level(gatedSound.slice(2.3, 2.9), from: 0) - level(gateTest.slice(2.3, 2.9), from: 0)) < 0.5, "The gate quietens hiss between phrases, not the phrases")

// MARK: Silence

var talk = SoundBuffer.tone(220, seconds: 1, amplitude: 0.3)
talk.append(.silence(seconds: 1.5, channels: 1))
talk.append(.tone(220, seconds: 1, amplitude: 0.3))
talk.append(.silence(seconds: 0.3, channels: 1))
talk.append(.tone(220, seconds: 1, amplitude: 0.3))
let gaps = SoundMeter.silences(talk, threshold: -40, minimum: 0.6)
check(gaps.count == 1 && near(gaps[0].lowerBound, 1, 0.03) && near(gaps[0].upperBound, 2.5, 0.03), "Finds the long silence and skips the short pause (\(gaps))")
let cuts = SoundDSP.silenceCuts(talk, threshold: -40, minimum: 0.6, keep: 0.25)
let tightened = SoundDSP.remove(talk, ranges: cuts)
check(near(tightened.duration, talk.duration - 1.25, 0.05), "Removing it keeps a quarter-second breath (\(f(tightened.duration)) s)")
let spans = SoundMeter.speech(talk, threshold: -40, minimumGap: 0.6)
check(spans.count == 2 && near(spans[0].upperBound, 1, 0.03), "Speech spans, for ducking music")

// MARK: Pictures of sound

let peaks = SoundMeter.peaks(tone, buckets: 200)
check(peaks.count == 200 && peaks.allSatisfy { near(Double($0.high), 0.5, 0.01) && near(Double($0.low), -0.5, 0.01) }, "Waveform peaks")
let spectrum = SoundMeter.spectrogram(tone, size: 1024, hop: 512)
let loudestBin = spectrum.first.flatMap { column in column.indices.max { column[$0] < column[$1] } }
check(!spectrum.isEmpty && loudestBin.map { abs($0 - 21) <= 1 } == true, "The spectrum peaks at 1 kHz (bin \(loudestBin ?? -1))")

// MARK: Time and pitch

do {
    let faster = try SoundDSP.timePitch(tone, rate: 2)
    check(near(faster.duration, 1, 0.08), "Tempo × 2 halves the length (\(f(faster.duration)) s)")
    let higher = try SoundDSP.timePitch(tone, cents: 1_200)
    let higherBin = SoundMeter.spectrogram(higher.slice(0.5, 1.5)).first.flatMap { column in column.indices.max { column[$0] < column[$1] } }
    check(near(higher.duration, 2, 0.1) && higherBin.map { $0 >= 40 && $0 <= 45 } == true, "An octave up keeps the length and doubles the pitch (bin \(higherBin ?? -1))")
} catch {
    check(false, "Time and pitch render offline (\(error))")
}
check(near(SoundDSP.varispeed(tone, rate: 2).duration, 1, 0.01), "Speed × 2 like a tape")

// MARK: Files

let folder = FileManager.default.temporaryDirectory.appendingPathComponent("audio-tests-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let stereo = SoundBuffer.tone(440, seconds: 1.5, amplitude: 0.4, channels: 2)
for format in SoundFormat.allCases {
    let url = folder.appendingPathComponent("test.\(format.fileExtension)")
    do {
        try SoundIO.write(stereo, to: url, format: format)
        let back = try SoundIO.read(url)
        let lossless = format != .m4a
        let same = lossless ? zip(back.channels[0], stereo.channels[0]).allSatisfy { abs($0 - $1) < 0.0002 } : near(level(back), level(stereo), 0.3)
        check(back.sampleRate == 48_000 && back.channelCount == 2 && near(back.duration, 1.5, lossless ? 0.001 : 0.1) && same, "\(format.title) writes and reads back")
    } catch {
        check(false, "\(format.title) writes and reads back (\(error))")
    }
}

// MARK: Projects

var project = SoundProject(name: "Episode")
project.tracks = [SoundTrack(name: "Voice"), SoundTrack(name: "Music")]
let voice = SoundClip(name: "Voice", asset: "voice", start: 1, outPoint: 4)
project.tracks[0].clips = [voice]
project.markers = [SoundMarker(time: 0, name: "Intro"), SoundMarker(time: 3, name: "The news")]
project.words = [SoundWord(text: "So", start: 1.1, end: 1.3), SoundWord(text: "um,", start: 1.4, end: 1.7), SoundWord(text: "welcome", start: 1.8, end: 2.2)]
let sources: [String: SoundBuffer] = ["voice": .tone(440, seconds: 5, amplitude: 0.4), "music": .tone(110, seconds: 10, amplitude: 0.2, channels: 2)]
check(near(project.duration, 5, 0.001), "A project runs to the end of its last clip")
let secondHalf = SoundEdit.split(&project, clip: voice.id, at: 2.5)
check(secondHalf != nil && project.tracks[0].clips.count == 2 && project.tracks[0].clips[0].outPoint == 1.5 && project.tracks[0].clips[1].inPoint == 1.5
      && project.tracks[0].clips[1].start == 2.5, "Split at the playhead")
SoundEdit.delete(&project, range: 2.5...3)
check(project.tracks[0].clips.count == 2 && near(project.tracks[0].clips[0].outPoint, 1.5, 0.001) && near(project.tracks[0].clips[1].start, 2.5, 0.001)
      && near(project.tracks[0].clips[1].inPoint, 2, 0.001) && near(project.duration, 4.5, 0.001) && near(project.markers[1].time, 2.5, 0.001),
      "Deleting a stretch closes the gap, markers too")
let fillers = SoundEdit.fillerRanges(project)
check(fillers.count == 1 && near(fillers[0].lowerBound, 1.37, 0.001), "Finds the um")
SoundEdit.delete(&project, ranges: fillers)
check(near(project.duration, 4.5 - 0.36, 0.001) && project.words.count == 2 && near(project.words[1].start, 1.8 - 0.36, 0.001), "Removing fillers cuts them out of the words too")
project.tracks[1].clips = [SoundClip(name: "Bed", asset: "music", start: 0, outPoint: 3)]
SoundEdit.move(&project, clip: project.tracks[1].clips[0].id, to: 0.5)
check(near(project.tracks[1].clips[0].start, 0.5, 0.001), "Move a clip")

var mixProject = SoundProject(name: "Mix")
mixProject.tracks = [SoundTrack(name: "Voice", clips: [SoundClip(name: "Voice", asset: "voice", start: 1, outPoint: 2)]),
                     SoundTrack(name: "Music", clips: [SoundClip(name: "Bed", asset: "music", start: 0, outPoint: 3)], volume: -6)]
let mix = SoundMixer.render(mixProject, sources: { sources[$0] })
check(near(mix.duration, 3, 0.001) && mix.channelCount == 2, "The mix is stereo and as long as the project")
var voiceOnly = mixProject
voiceOnly.tracks[0].solo = true
let solo = SoundMixer.render(voiceOnly, sources: { sources[$0] })
check(SoundMeter.peak(solo.slice(0, 0.9)) < 0.0001 && near(level(solo.slice(1.2, 1.8), from: 0), level(SoundBuffer.tone(440, seconds: 1, amplitude: 0.4)), 0.2),
      "Solo plays one track, starting where its clip starts")
var panned = voiceOnly
panned.tracks[0].pan = -1
let left = SoundMixer.render(panned, sources: { sources[$0] })
check(SoundMeter.peak(SoundBuffer(sampleRate: 48_000, channels: [left.channels[1]])) < 0.0001, "Pan hard left")
var muted = mixProject
muted.tracks[1].muted = true
muted.tracks[0].muted = true
check(SoundMeter.peak(SoundMixer.render(muted, sources: { sources[$0] })) == 0, "Muted tracks are silent")
check(SoundChapters.text(project) == "00:00 Intro\n00:02 The news" && SoundChapters.clock(3725) == "1:02:05", "Chapters for show notes")
let saved = try? JSONDecoder().decode(SoundProject.self, from: JSONEncoder().encode(project))
check(saved == project, "Projects save as JSON")

// Music ducking: speech spans close together merge; the bed eases down before speech and back up after.
check(MusicEnvelope.merge([5...6, 0.5...1, 1.6...2.5]) == [0.5...2.5, 5...6], "Speech close together counts as one span")
let bedFade = MusicEnvelope.points(speech: [], total: 10, volume: 0.5, duckLevel: 0.2, fades: true)
check(bedFade.map(\.time) == [0, 1.5, 8, 10] && near(bedFade[0].volume, 0, 1e-9) && near(bedFade[1].volume, 0.5, 1e-9)
      && near(bedFade[2].volume, 0.5, 1e-9) && near(bedFade[3].volume, 0, 1e-9), "Music fades in and out with the movie")
let ducking = MusicEnvelope.points(speech: [4...6], total: 10, volume: 1, duckLevel: 0.2, fades: false)
func volume(_ points: [MusicEnvelope.Point], at time: Double) -> Double? { points.first { abs($0.time - time) < 1e-6 }?.volume }
check(volume(ducking, at: 3.75) == 1 && near(volume(ducking, at: 4) ?? 0, 0.2, 1e-9) && near(volume(ducking, at: 6) ?? 0, 0.2, 1e-9)
      && volume(ducking, at: 6.4) == 1 && volume(ducking, at: 10) == 1, "Music ducks to its level under speech")
check(zip(ducking, ducking.dropFirst()).allSatisfy { $0.time < $1.time }, "Ducking points only go forward, so the ramps never overlap")
let edges = MusicEnvelope.points(speech: [0...2, 9.8...12], total: 10, volume: 1, duckLevel: 0.3, fades: false)
check(edges.first?.time == 0 && edges.last?.time == 10 && near(edges.first?.volume ?? 0, 0.3, 1e-9), "Speech at the very ends stays inside the movie")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
