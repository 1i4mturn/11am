import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

/// A generated landscape and two short clips, so Photo and Video open with something to grade before you load your own.
enum SampleMedia {
    /// A dusk landscape: sky gradient, low sun, two ranges of hills and a lake.
    static func scene(width: Int = 2400, height: Int = 1600) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let w = CGFloat(width)
        let h = CGFloat(height)
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(colorSpace: space, components: [r, g, b, a]) ?? CGColor(gray: 0, alpha: 1)
        }
        func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient? {
            CGGradient(colorsSpace: space, colors: stops.map { $0.0 } as CFArray, locations: stops.map { $0.1 })
        }

        // Sky
        if let sky = gradient([
            (color(0.16, 0.20, 0.38), 0), (color(0.45, 0.38, 0.55), 0.45),
            (color(0.93, 0.58, 0.42), 0.8), (color(0.99, 0.80, 0.55), 1),
        ]) {
            ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.38), options: [.drawsAfterEndLocation])
        }
        // Sun and glow
        let sun = CGPoint(x: w * 0.64, y: h * 0.47)
        if let glow = gradient([(color(1, 0.92, 0.7, 0.9), 0), (color(1, 0.75, 0.5, 0.35), 0.25), (color(1, 0.6, 0.4, 0), 1)]) {
            ctx.drawRadialGradient(glow, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: w * 0.35, options: [])
        }
        ctx.setFillColor(color(1, 0.96, 0.85))
        ctx.fillEllipse(in: CGRect(x: sun.x - h * 0.045, y: sun.y - h * 0.045, width: h * 0.09, height: h * 0.09))

        // Far hills
        func ridge(base: CGFloat, height amplitude: CGFloat, seed: Double, fill: CGColor) {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: base))
            var x: CGFloat = 0
            while x <= w {
                let t = Double(x / w)
                let y = base + amplitude * CGFloat(0.55 * sin(t * 7.3 + seed) + 0.3 * sin(t * 17.1 + seed * 2) + 0.15 * sin(t * 41 + seed * 3))
                path.addLine(to: CGPoint(x: x, y: y))
                x += 6
            }
            path.addLine(to: CGPoint(x: w, y: 0))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(fill)
            ctx.fillPath()
        }
        ridge(base: h * 0.42, height: h * 0.06, seed: 1.2, fill: color(0.42, 0.36, 0.52))
        ridge(base: h * 0.36, height: h * 0.07, seed: 3.7, fill: color(0.24, 0.22, 0.34))

        // Lake with the sky reflected
        let lake = CGRect(x: 0, y: 0, width: w, height: h * 0.3)
        ctx.saveGState()
        ctx.clip(to: lake)
        if let water = gradient([(color(0.85, 0.55, 0.45), 0), (color(0.35, 0.33, 0.5), 0.6), (color(0.12, 0.14, 0.26), 1)]) {
            ctx.drawLinearGradient(water, start: CGPoint(x: 0, y: h * 0.3), end: CGPoint(x: 0, y: 0), options: [])
        }
        ctx.setFillColor(color(1, 0.9, 0.75, 0.55))
        var y = h * 0.28
        while y > 0 {
            let span = w * 0.05 * (y / (h * 0.3)) + 6
            ctx.fill(CGRect(x: sun.x - span, y: y, width: span * 2, height: 3))
            y -= 14
        }
        ctx.restoreGState()

        // Near shore with trees
        ridge(base: h * 0.27, height: h * 0.025, seed: 5.1, fill: color(0.08, 0.08, 0.12))
        ctx.setFillColor(color(0.06, 0.06, 0.09))
        for i in 0..<14 {
            let x = w * (0.04 + 0.025 * CGFloat(i)) + CGFloat(i % 3) * 9
            let top = h * (0.33 + 0.03 * CGFloat((i * 7) % 5) / 4)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - 22, y: h * 0.27))
            path.addLine(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x + 22, y: h * 0.27))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
        }
        return ctx.makeImage()
    }

    /// Two five-second clips panning across the scene; the second is cooler and flatter, like a different camera.
    static func makeClips() async throws -> [URL] {
        guard let cg = scene() else { return [] }
        let base = CIImage(cgImage: cg)
        let first = try await writeClip(from: base, name: "Sample A · lake", pan: (0.0, 0.35), zoom: (1.25, 1.1), cool: false)
        let second = try await writeClip(from: base, name: "Sample B · ridge", pan: (0.4, 0.15), zoom: (1.6, 1.35), cool: true)
        return [first, second]
    }

    private static func writeClip(from base: CIImage, name: String, pan: (Double, Double), zoom: (Double, Double), cool: Bool) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("11am-samples", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(name).mov")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let width = 1280
        let height = 720
        let fps: Int32 = 30
        let frames = 150
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        let context = CIContext(options: [.cacheIntermediates: false])
        var source = base
        if cool {
            source = source
                .applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 5200, y: 0), "inputTargetNeutral": CIVector(x: 6500, y: 0)])
                .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.75, "inputContrast": 0.85])
        }
        let extent = base.extent
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            let t = Double(frame) / Double(frames - 1)
            let scale = zoom.0 + (zoom.1 - zoom.0) * t
            let viewWidth = extent.width / scale
            let viewHeight = viewWidth * Double(height) / Double(width)
            let x = (extent.width - viewWidth) * (pan.0 + (pan.1 - pan.0) * t)
            let yOrigin = (extent.height - viewHeight) * 0.45
            let fit = Double(width) / viewWidth
            let image = source
                .transformed(by: CGAffineTransform(translationX: -x, y: -yOrigin))
                .transformed(by: CGAffineTransform(scaleX: fit, y: fit))
                .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }
            context.render(image, to: buffer)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }
}
