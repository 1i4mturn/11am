import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// One colour wheel (shadows, midtones or highlights): a hue to push towards, how far, and a brightness offset.
struct ColorWheel: Codable, Equatable {
    var hue: Double = 0
    var amount: Double = 0
    var luma: Double = 0

    init(hue: Double = 0, amount: Double = 0, luma: Double = 0) {
        self.hue = hue
        self.amount = amount
        self.luma = luma
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hue = (try? c.decodeIfPresent(Double.self, forKey: .hue)) ?? 0
        amount = (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0
        luma = (try? c.decodeIfPresent(Double.self, forKey: .luma)) ?? 0
    }

    var isNeutral: Bool { amount < 0.001 && abs(luma) < 0.001 }

    /// The wheel as an RGB push centred on zero, so colour shifts without changing brightness (luma does that).
    var offset: SIMD3<Double> {
        let rgb = GradeMath.hueToRGB(hue)
        let mean = (rgb.x + rgb.y + rgb.z) / 3
        return (rgb - SIMD3(repeating: mean)) * amount + SIMD3(repeating: luma)
    }
}

/// Hue, saturation and lightness changes for one band of colour.
struct HSLBand: Codable, Equatable {
    var hue: Double = 0
    var saturation: Double = 0
    var luminance: Double = 0

    init(hue: Double = 0, saturation: Double = 0, luminance: Double = 0) {
        self.hue = hue
        self.saturation = saturation
        self.luminance = luminance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hue = (try? c.decodeIfPresent(Double.self, forKey: .hue)) ?? 0
        saturation = (try? c.decodeIfPresent(Double.self, forKey: .saturation)) ?? 0
        luminance = (try? c.decodeIfPresent(Double.self, forKey: .luminance)) ?? 0
    }

    var isNeutral: Bool { abs(hue) < 0.001 && abs(saturation) < 0.001 && abs(luminance) < 0.001 }
}

struct CurvePoint: Codable, Equatable {
    var x: Double
    var y: Double
}

/// Every adjustment in a grade. Shared by Photo and Video, saved as a look, and written by Johnny from plain English.
struct GradeSettings: Codable, Equatable {
    static let bandNames = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]
    static let bandHues: [Double] = [0, 30, 60, 120, 180, 225, 275, 320]
    static let identityCurve = [
        CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.25), CurvePoint(x: 0.5, y: 0.5),
        CurvePoint(x: 0.75, y: 0.75), CurvePoint(x: 1, y: 1),
    ]

    // Light
    var exposure: Double = 0      // stops, −3…3
    var contrast: Double = 0      // −1…1
    var highlights: Double = 0    // −1…1
    var shadows: Double = 0       // −1…1
    // Colour
    var temperature: Double = 0   // −1 cool … 1 warm
    var tint: Double = 0          // −1 green … 1 magenta
    var vibrance: Double = 0      // −1…1
    var saturation: Double = 0    // −1…1
    // Wheels
    var lift = ColorWheel()
    var gamma = ColorWheel()
    var gain = ColorWheel()
    // Colour by colour
    var hsl: [HSLBand] = Array(repeating: HSLBand(), count: 8)
    // Tone curve
    var curve: [CurvePoint] = GradeSettings.identityCurve
    // Detail
    var sharpen: Double = 0       // 0…1
    var noiseReduction: Double = 0
    // Effects
    var fade: Double = 0          // 0…1
    var vignette: Double = 0      // 0…1
    var grain: Double = 0         // 0…1
    // Imported film look
    var lutName: String?
    var lutAmount: Double = 1

    init() {}

    /// Missing keys fall back to defaults, so a look Johnny writes with only a few values still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d(_ key: CodingKeys) -> Double? { (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil }
        exposure = d(.exposure) ?? 0
        contrast = d(.contrast) ?? 0
        highlights = d(.highlights) ?? 0
        shadows = d(.shadows) ?? 0
        temperature = d(.temperature) ?? 0
        tint = d(.tint) ?? 0
        vibrance = d(.vibrance) ?? 0
        saturation = d(.saturation) ?? 0
        lift = (try? c.decodeIfPresent(ColorWheel.self, forKey: .lift)) ?? ColorWheel()
        gamma = (try? c.decodeIfPresent(ColorWheel.self, forKey: .gamma)) ?? ColorWheel()
        gain = (try? c.decodeIfPresent(ColorWheel.self, forKey: .gain)) ?? ColorWheel()
        var bands = (try? c.decodeIfPresent([HSLBand].self, forKey: .hsl)) ?? []
        while bands.count < 8 { bands.append(HSLBand()) }
        hsl = Array(bands.prefix(8))
        let points = (try? c.decodeIfPresent([CurvePoint].self, forKey: .curve)) ?? []
        curve = points.count >= 2 ? points : GradeSettings.identityCurve
        sharpen = d(.sharpen) ?? 0
        noiseReduction = d(.noiseReduction) ?? 0
        fade = d(.fade) ?? 0
        vignette = d(.vignette) ?? 0
        grain = d(.grain) ?? 0
        lutName = (try? c.decodeIfPresent(String.self, forKey: .lutName)) ?? nil
        lutAmount = d(.lutAmount) ?? 1
        clamp()
    }

    /// Keeps every value in its range, whatever wrote it.
    mutating func clamp() {
        func c(_ v: inout Double, _ lo: Double, _ hi: Double) { v = min(max(v, lo), hi) }
        c(&exposure, -3, 3)
        let signed: [WritableKeyPath<GradeSettings, Double>] = [\.contrast, \.highlights, \.shadows, \.temperature, \.tint, \.vibrance, \.saturation]
        for key in signed { c(&self[keyPath: key], -1, 1) }
        let positive: [WritableKeyPath<GradeSettings, Double>] = [\.sharpen, \.noiseReduction, \.fade, \.vignette, \.grain, \.lutAmount]
        for key in positive { c(&self[keyPath: key], 0, 1) }
        let wheels: [WritableKeyPath<GradeSettings, ColorWheel>] = [\.lift, \.gamma, \.gain]
        for key in wheels {
            c(&self[keyPath: key].amount, 0, 1)
            c(&self[keyPath: key].luma, -1, 1)
        }
        for index in hsl.indices {
            c(&hsl[index].hue, -1, 1)
            c(&hsl[index].saturation, -1, 1)
            c(&hsl[index].luminance, -1, 1)
        }
        curve = curve.map { CurvePoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }.sorted { $0.x < $1.x }
    }

    var curveIsIdentity: Bool { curve.allSatisfy { abs($0.x - $0.y) < 0.002 } }

    /// True when the colour lookup (tone, wheels, saturation, colour by colour) has anything to do.
    var needsCube: Bool {
        abs(contrast) > 0.001 || highlights > 0.001 || !curveIsIdentity || fade > 0.001
            || !lift.isNeutral || !gamma.isNeutral || !gain.isNeutral
            || abs(saturation) > 0.001 || hsl.contains { !$0.isNeutral }
    }
}

/// A 3D colour lookup table, from a .cube file or baked from a grade.
struct CubeLUT: @unchecked Sendable {
    let size: Int
    let data: Data

    /// Reads Resolve/Adobe .cube files (3D tables, with optional DOMAIN_MIN/MAX).
    static func parse(_ text: String) -> CubeLUT? {
        var size = 0
        var low = SIMD3<Float>(0, 0, 0)
        var high = SIMD3<Float>(1, 1, 1)
        var values: [Float] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("TITLE") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if line.hasPrefix("LUT_1D_SIZE") { return nil }
            if line.hasPrefix("LUT_3D_SIZE"), let last = parts.last, let n = Int(last) {
                size = n
                values.reserveCapacity(n * n * n * 4)
                continue
            }
            if line.hasPrefix("DOMAIN_MIN"), parts.count >= 4 {
                low = SIMD3(Float(parts[1]) ?? 0, Float(parts[2]) ?? 0, Float(parts[3]) ?? 0)
                continue
            }
            if line.hasPrefix("DOMAIN_MAX"), parts.count >= 4 {
                high = SIMD3(Float(parts[1]) ?? 1, Float(parts[2]) ?? 1, Float(parts[3]) ?? 1)
                continue
            }
            guard parts.count >= 3, let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) else { continue }
            let span = high - low
            values.append((r - low.x) / max(span.x, 0.0001))
            values.append((g - low.y) / max(span.y, 0.0001))
            values.append((b - low.z) / max(span.z, 0.0001))
            values.append(1)
        }
        guard size > 1, values.count == size * size * size * 4 else { return nil }
        let lut = CubeLUT(size: size, data: values.withUnsafeBufferPointer { Data(buffer: $0) })
        return size > 64 ? lut.resampled(to: 33) : lut
    }

    /// Big tables (65³ from Resolve) are resampled so Core Image accepts them everywhere.
    func resampled(to target: Int) -> CubeLUT {
        let source: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        func sample(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> {
            let i = ((b * size + g) * size + r) * 4
            return SIMD3(source[i], source[i + 1], source[i + 2])
        }
        var out = [Float](repeating: 1, count: target * target * target * 4)
        let scale = Float(size - 1) / Float(target - 1)
        var o = 0
        for b in 0..<target {
            for g in 0..<target {
                for r in 0..<target {
                    let p = SIMD3<Float>(Float(r), Float(g), Float(b)) * scale
                    let i0 = SIMD3<Int>(Int(p.x), Int(p.y), Int(p.z))
                    let i1 = SIMD3<Int>(min(i0.x + 1, size - 1), min(i0.y + 1, size - 1), min(i0.z + 1, size - 1))
                    let f = p - SIMD3<Float>(Float(i0.x), Float(i0.y), Float(i0.z))
                    func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }
                    let c00 = lerp(sample(i0.x, i0.y, i0.z), sample(i1.x, i0.y, i0.z), f.x)
                    let c10 = lerp(sample(i0.x, i1.y, i0.z), sample(i1.x, i1.y, i0.z), f.x)
                    let c01 = lerp(sample(i0.x, i0.y, i1.z), sample(i1.x, i0.y, i1.z), f.x)
                    let c11 = lerp(sample(i0.x, i1.y, i1.z), sample(i1.x, i1.y, i1.z), f.x)
                    let c = lerp(lerp(c00, c10, f.y), lerp(c01, c11, f.y), f.z)
                    out[o] = c.x
                    out[o + 1] = c.y
                    out[o + 2] = c.z
                    o += 4
                }
            }
        }
        return CubeLUT(size: target, data: out.withUnsafeBufferPointer { Data(buffer: $0) })
    }
}

/// Smooth curve through the user's points that never overshoots (monotone cubic, Fritsch–Carlson).
struct ToneCurve {
    private let xs: [Double]
    private let ys: [Double]
    private let ms: [Double]

    init(points: [CurvePoint]) {
        var sorted = points.sorted { $0.x < $1.x }
        if sorted.count < 2 { sorted = GradeSettings.identityCurve }
        var px: [Double] = []
        var py: [Double] = []
        for point in sorted where px.last.map({ point.x - $0 > 0.0001 }) ?? true {
            px.append(point.x)
            py.append(point.y)
        }
        let n = px.count
        var secants = [Double](repeating: 0, count: max(n - 1, 0))
        for i in 0..<(n - 1) { secants[i] = (py[i + 1] - py[i]) / (px[i + 1] - px[i]) }
        var tangents = [Double](repeating: 0, count: n)
        if n >= 2 {
            tangents[0] = secants[0]
            tangents[n - 1] = secants[n - 2]
            for i in 1..<(n - 1) { tangents[i] = secants[i - 1] * secants[i] <= 0 ? 0 : (secants[i - 1] + secants[i]) / 2 }
            for i in 0..<(n - 1) where secants[i] == 0 {
                tangents[i] = 0
                tangents[i + 1] = 0
            }
            for i in 0..<(n - 1) where secants[i] != 0 {
                let a = tangents[i] / secants[i]
                let b = tangents[i + 1] / secants[i]
                let h = a * a + b * b
                if h > 9 {
                    let t = 3 / h.squareRoot()
                    tangents[i] = t * a * secants[i]
                    tangents[i + 1] = t * b * secants[i]
                }
            }
        }
        xs = px
        ys = py
        ms = tangents
    }

    func value(_ x: Double) -> Double {
        guard let first = xs.first, let last = xs.last else { return x }
        if x <= first { return ys[0] }
        if x >= last { return ys[ys.count - 1] }
        var i = 0
        while i < xs.count - 2 && x > xs[i + 1] { i += 1 }
        let h = xs[i + 1] - xs[i]
        let t = (x - xs[i]) / h
        let t2 = t * t
        let t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * ms[i]
            + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * ms[i + 1]
    }
}

enum GradeMath {
    static func hueToRGB(_ degrees: Double) -> SIMD3<Double> {
        let h = ((degrees.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        switch Int(h) {
        case 0: return SIMD3(1, x, 0)
        case 1: return SIMD3(x, 1, 0)
        case 2: return SIMD3(0, 1, x)
        case 3: return SIMD3(0, x, 1)
        case 4: return SIMD3(x, 0, 1)
        default: return SIMD3(1, 0, x)
        }
    }

    static func luma(_ c: SIMD3<Double>) -> Double { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func rgbToHSL(_ c: SIMD3<Double>) -> SIMD3<Double> {
        let maxV = max(c.x, c.y, c.z)
        let minV = min(c.x, c.y, c.z)
        let l = (maxV + minV) / 2
        guard maxV - minV > 0.00001 else { return SIMD3(0, 0, l) }
        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        if maxV == c.x { h = (c.y - c.z) / d + (c.y < c.z ? 6 : 0) }
        else if maxV == c.y { h = (c.z - c.x) / d + 2 }
        else { h = (c.x - c.y) / d + 4 }
        h *= 60
        return SIMD3(h, s, l)
    }

    static func hslToRGB(_ hsl: SIMD3<Double>) -> SIMD3<Double> {
        let (h, s, l) = (hsl.x, hsl.y, hsl.z)
        guard s > 0.00001 else { return SIMD3(repeating: l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let hn = h / 360
        return SIMD3(channel(hn + 1.0 / 3), channel(hn), channel(hn - 1.0 / 3))
    }

    /// Bakes tone, wheels, saturation and colour-by-colour into one 33³ lookup, applied in a single GPU pass.
    static func makeCube(_ s: GradeSettings, size n: Int = 33) -> Data {
        let curve = ToneCurve(points: s.curve)
        let useCurve = !s.curveIsIdentity
        let lift = s.lift.offset * 0.15
        let gammaShift = s.gamma.offset * 0.35
        let gain = s.gain.offset * 0.35
        let wheels = !(s.lift.isNeutral && s.gamma.isNeutral && s.gain.isNeutral)
        let bands = s.hsl
        let useHSL = bands.contains { !$0.isNeutral }
        var values = [Float](repeating: 1, count: n * n * n * 4)
        var i = 0
        let step = 1 / Double(n - 1)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    var c = SIMD3<Double>(Double(r), Double(g), Double(b)) * step

                    // Tone
                    if abs(s.contrast) > 0.001 {
                        if s.contrast > 0 {
                            let curved = SIMD3(smoothstep(0, 1, c.x), smoothstep(0, 1, c.y), smoothstep(0, 1, c.z))
                            c += (curved - c) * s.contrast
                        } else {
                            c = SIMD3(repeating: 0.5) + (c - SIMD3(repeating: 0.5)) * (1 + s.contrast * 0.5)
                        }
                    }
                    if s.highlights > 0.001 {
                        c += SIMD3(repeating: s.highlights * 0.18 * smoothstep(0.45, 1, luma(c)))
                    }
                    if useCurve {
                        c = SIMD3(curve.value(c.x), curve.value(c.y), curve.value(c.z))
                    }
                    if s.fade > 0.001 {
                        let lift = s.fade * 0.12
                        c = SIMD3(repeating: lift) + c * (1 - lift)
                    }

                    // Wheels: slope (gain), offset (lift, mostly in the shadows), power (gamma)
                    if wheels {
                        var out = SIMD3<Double>(0, 0, 0)
                        for ch in 0..<3 {
                            var v = c[ch] * (1 + gain[ch]) + lift[ch] * (1 - c[ch])
                            v = max(0, v)
                            v = pow(v, 1 / max(0.2, 1 + gammaShift[ch]))
                            out[ch] = v
                        }
                        c = out
                    }

                    // Saturation
                    if abs(s.saturation) > 0.001 {
                        let l = luma(c)
                        c = SIMD3(repeating: l) + (c - SIMD3(repeating: l)) * (1 + s.saturation)
                    }

                    // Colour by colour
                    if useHSL {
                        var hsl = rgbToHSL(SIMD3(min(max(c.x, 0), 1), min(max(c.y, 0), 1), min(max(c.z, 0), 1)))
                        var dh = 0.0
                        var ds = 0.0
                        var dl = 0.0
                        for (k, band) in bands.enumerated() where !band.isNeutral {
                            var distance = abs(hsl.x - GradeSettings.bandHues[k]).truncatingRemainder(dividingBy: 360)
                            if distance > 180 { distance = 360 - distance }
                            let w = max(0, 1 - distance / 40)
                            dh += w * band.hue * 30
                            ds += w * band.saturation
                            dl += w * band.luminance
                        }
                        hsl.x += dh
                        hsl.y = min(max(hsl.y * (1 + ds), 0), 1)
                        hsl.z = min(max(hsl.z + dl * 0.25 * hsl.y, 0), 1)
                        c = hslToRGB(hsl)
                    }

                    values[i] = Float(min(max(c.x, 0), 1))
                    values[i + 1] = Float(min(max(c.y, 0), 1))
                    values[i + 2] = Float(min(max(c.z, 0), 1))
                    i += 4
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

/// Applies a grade to an image or a video frame. Immutable once made, so it's safe on any thread.
final class GradeRenderer: @unchecked Sendable {
    let settings: GradeSettings
    private let cube: Data?
    private let lut: CubeLUT?
    private static let cubeSize = 33
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)

    init(settings: GradeSettings, lut: CubeLUT?) {
        self.settings = settings
        self.lut = settings.lutName == nil ? nil : lut
        cube = settings.needsCube ? GradeMath.makeCube(settings, size: GradeRenderer.cubeSize) : nil
    }

    /// `frame` is the picture's real extent (video frames arrive clamped to infinity); `seed` moves the grain each frame.
    func apply(to input: CIImage, frame: CGRect? = nil, seed: Double = 0) -> CIImage {
        let s = settings
        let rect = frame ?? input.extent
        var image = input

        if abs(s.exposure) > 0.001 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = image
            f.ev = Float(s.exposure)
            image = f.outputImage ?? image
        }
        if abs(s.temperature) > 0.001 || abs(s.tint) > 0.001 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            f.neutral = CIVector(x: 6500 + CGFloat(s.temperature) * 3500, y: CGFloat(s.tint) * 80)
            f.targetNeutral = CIVector(x: 6500, y: 0)
            image = f.outputImage ?? image
        }
        if abs(s.shadows) > 0.001 || s.highlights < -0.001 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = image
            f.shadowAmount = Float(s.shadows)
            f.highlightAmount = Float(1 + min(0, s.highlights) * 0.9)
            f.radius = Float(max(rect.width, rect.height) / 400)
            image = f.outputImage ?? image
        }
        if abs(s.vibrance) > 0.001 {
            let f = CIFilter.vibrance()
            f.inputImage = image
            f.amount = Float(s.vibrance)
            image = f.outputImage ?? image
        }
        if let cube {
            image = GradeRenderer.applyCube(cube, size: GradeRenderer.cubeSize, to: image)
        }
        if let lut, s.lutAmount > 0.001 {
            let looked = GradeRenderer.applyCube(lut.data, size: lut.size, to: image)
            if s.lutAmount >= 0.999 {
                image = looked
            } else {
                let mix = CIFilter.dissolveTransition()
                mix.inputImage = image
                mix.targetImage = looked
                mix.time = Float(s.lutAmount)
                image = mix.outputImage ?? looked
            }
        }
        if s.noiseReduction > 0.001 {
            let f = CIFilter.noiseReduction()
            f.inputImage = image
            f.noiseLevel = Float(0.005 + 0.045 * s.noiseReduction)
            f.sharpness = 0.4
            image = f.outputImage ?? image
        }
        if s.sharpen > 0.001 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = image
            f.sharpness = Float(s.sharpen * 1.2)
            f.radius = Float(max(1.2, max(rect.width, rect.height) / 1600))
            image = f.outputImage ?? image
        }
        if s.vignette > 0.001 {
            let f = CIFilter.vignetteEffect()
            f.inputImage = image
            f.center = CGPoint(x: rect.midX, y: rect.midY)
            f.radius = Float(hypot(rect.width, rect.height) * 0.42)
            f.intensity = Float(s.vignette * 0.9)
            f.falloff = 0.55
            image = f.outputImage ?? image
        }
        if s.grain > 0.001, let noise = CIFilter.randomGenerator().outputImage {
            let size = max(1, max(rect.width, rect.height) / 1800)
            let shift = (seed * 977).truncatingRemainder(dividingBy: 2048)
            let mono = noise
                .transformed(by: CGAffineTransform(translationX: shift, y: shift * 0.618).scaledBy(x: size, y: size))
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                ])
                .cropped(to: rect)
            let blend = CIFilter.softLightBlendMode()
            blend.inputImage = mono
            blend.backgroundImage = image
            if let grained = blend.outputImage {
                let mix = CIFilter.dissolveTransition()
                mix.inputImage = image
                mix.targetImage = grained
                mix.time = Float(s.grain * 0.7)
                image = mix.outputImage ?? image
            }
        }
        return image
    }

    private static func applyCube(_ data: Data, size: Int, to image: CIImage) -> CIImage {
        let f = CIFilter.colorCubeWithColorSpace()
        f.inputImage = image
        f.cubeDimension = Float(size)
        f.cubeData = data
        f.colorSpace = sRGB
        return f.outputImage ?? image
    }
}

/// Auto-enhance: Core Image's own analysis, turned into editable settings rather than a black box.
enum GradeAuto {
    static func settings(for image: CIImage, keeping base: GradeSettings = GradeSettings()) -> GradeSettings {
        var s = base
        for filter in image.autoAdjustmentFilters(options: [.redEye: false]) {
            switch filter.name {
            case "CIVibrance":
                s.vibrance = (filter.value(forKey: "inputAmount") as? NSNumber)?.doubleValue ?? s.vibrance
            case "CIHighlightShadowAdjust":
                s.shadows = (filter.value(forKey: "inputShadowAmount") as? NSNumber)?.doubleValue ?? s.shadows
                if let h = (filter.value(forKey: "inputHighlightAmount") as? NSNumber)?.doubleValue { s.highlights = (h - 1) / 0.9 }
            case "CIToneCurve":
                var points: [CurvePoint] = []
                for i in 0..<5 {
                    if let v = filter.value(forKey: "inputPoint\(i)") as? CIVector {
                        points.append(CurvePoint(x: Double(v.x), y: Double(v.y)))
                    }
                }
                if points.count == 5 { s.curve = points }
            case "CITemperatureAndTint":
                if let neutral = filter.value(forKey: "inputNeutral") as? CIVector {
                    s.temperature = Double((neutral.x - 6500) / 3500)
                }
            default:
                break
            }
        }
        s.clamp()
        return s
    }
}

/// Brightness distribution, for the histogram.
enum Histogram {
    static func luminance(of image: CIImage, context: CIContext, bins: Int = 64) -> [Float] {
        guard !image.extent.isInfinite, image.extent.width > 0 else { return [] }
        let grey = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        let f = CIFilter.areaHistogram()
        f.inputImage = grey
        f.extent = image.extent
        f.count = bins
        f.scale = 1
        guard let output = f.outputImage else { return [] }
        var buffer = [Float](repeating: 0, count: bins * 4)
        context.render(output, toBitmap: &buffer, rowBytes: bins * 16, bounds: CGRect(x: 0, y: 0, width: bins, height: 1), format: .RGBAf, colorSpace: nil)
        var values = stride(from: 0, to: buffer.count, by: 4).map { buffer[$0] }
        let peak = values.max() ?? 1
        if peak > 0 { values = values.map { $0 / peak } }
        return values
    }
}
