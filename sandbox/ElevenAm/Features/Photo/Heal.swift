import CoreGraphics
import Foundation

/// A spot to clean up: centre from the top-left, as a fraction of the photo; radius as a fraction of its short side.
struct HealSpot: Codable, Equatable {
    var x: Double
    var y: Double
    var radius: Double
}

/// Content-aware spot healing, entirely on this Mac.
/// Each spot is filled from the nearby patch whose surroundings best match the spot's own surroundings,
/// shifted to the same colour and feathered in. Good for dust, blemishes, wires and small distractions.
enum PhotoHeal {
    static func apply(_ spots: [HealSpot], to image: CGImage) -> CGImage? {
        guard !spots.isEmpty else { return image }
        let w = image.width
        let h = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { return nil }
        // Bitmap memory runs top to bottom, which matches spots measured from the top-left.
        let pixels = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let short = Double(min(w, h))
        for spot in spots {
            heal(pixels, width: w, height: h, cx: spot.x * Double(w), cy: spot.y * Double(h), radius: max(2, spot.radius * short))
        }
        return ctx.makeImage()
    }

    private static func heal(_ px: UnsafeMutablePointer<UInt8>, width w: Int, height h: Int, cx: Double, cy: Double, radius r: Double) {
        let ring = r * 1.4
        let centerX = Int(cx.rounded())
        let centerY = Int(cy.rounded())
        func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h }
        func index(_ x: Int, _ y: Int) -> Int { (y * w + x) * 4 }

        // Pixels in the band around the spot describe its surroundings.
        let step = max(1, Int(r / 7))
        let reach = Int(ring.rounded(.up))
        var band: [(Int, Int)] = []
        for dy in stride(from: -reach, through: reach, by: step) {
            for dx in stride(from: -reach, through: reach, by: step) {
                let d = hypot(Double(dx), Double(dy))
                if d >= r && d <= ring && inside(centerX + dx, centerY + dy) { band.append((dx, dy)) }
            }
        }
        guard !band.isEmpty else { return }

        // Try patches in a circle of directions and distances; keep the one whose surroundings match best.
        var best: (dx: Int, dy: Int)?
        var bestScore = Double.infinity
        for k in 0..<28 {
            let angle = Double(k) / 28 * 2 * .pi
            for distance in [2.3, 3.0, 3.8, 4.8] {
                let ox = Int((cos(angle) * distance * r).rounded())
                let oy = Int((sin(angle) * distance * r).rounded())
                let sx = centerX + ox
                let sy = centerY + oy
                guard sx - reach >= 0, sy - reach >= 0, sx + reach < w, sy + reach < h else { continue }
                var score = 0.0
                for (dx, dy) in band {
                    let t = index(centerX + dx, centerY + dy)
                    let s = index(sx + dx, sy + dy)
                    for c in 0..<3 {
                        let diff = Double(px[t + c]) - Double(px[s + c])
                        score += diff * diff
                    }
                }
                score *= 1 + distance * 0.04 // nearer patches win ties: lighting changes less
                if score < bestScore {
                    bestScore = score
                    best = (ox, oy)
                }
            }
        }
        guard let offset = best else { return }

        // Match the patch's colour to the spot's surroundings.
        var targetMean = SIMD3<Double>(0, 0, 0)
        var sourceMean = SIMD3<Double>(0, 0, 0)
        for (dx, dy) in band {
            let t = index(centerX + dx, centerY + dy)
            let s = index(centerX + offset.dx + dx, centerY + offset.dy + dy)
            targetMean += SIMD3(Double(px[t]), Double(px[t + 1]), Double(px[t + 2]))
            sourceMean += SIMD3(Double(px[s]), Double(px[s + 1]), Double(px[s + 2]))
        }
        let shift = (targetMean - sourceMean) / Double(band.count)

        // Copy with a soft edge.
        let outer = r * 1.08
        let inner = r * 0.62
        let span = Int(outer.rounded(.up))
        for dy in -span...span {
            for dx in -span...span {
                let d = hypot(Double(dx), Double(dy))
                guard d <= outer else { continue }
                let tx = centerX + dx
                let ty = centerY + dy
                let sx = tx + offset.dx
                let sy = ty + offset.dy
                guard inside(tx, ty), inside(sx, sy) else { continue }
                let t = min(max((d - inner) / (outer - inner), 0), 1)
                let alpha = 1 - t * t * (3 - 2 * t)
                let ti = index(tx, ty)
                let si = index(sx, sy)
                for c in 0..<3 {
                    let source = Double(px[si + c]) + shift[c]
                    let blended = Double(px[ti + c]) * (1 - alpha) + source * alpha
                    px[ti + c] = UInt8(min(max(blended, 0), 255))
                }
            }
        }
    }
}
