import AppKit
import CryptoKit
import Foundation
import SwiftUI

struct PaletteColor: Sendable, Hashable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }

    func vividColor(hueShift: Double = 0) -> Color {
        let source = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        source.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let shiftedHue = (Double(hue) + hueShift).truncatingRemainder(dividingBy: 1)
        return Color(
            hue: shiftedHue < 0 ? shiftedHue + 1 : shiftedHue,
            saturation: min(max(Double(saturation) * 1.55, 0.58), 1),
            brightness: min(max(Double(brightness) * 1.20, 0.48), 0.98)
        )
    }
}

actor DominantColorService {
    static let shared = DominantColorService()

    private var cache: [String: [PaletteColor]] = [:]

    func colors(for data: Data?) -> [PaletteColor] {
        guard let data else { return Self.fallback }
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let cached = cache[key] { return cached }

        let colors = extract(from: data)
        cache[key] = colors
        if cache.count > 80, let firstKey = cache.keys.first { cache.removeValue(forKey: firstKey) }
        return colors
    }

    private func extract(from data: Data) -> [PaletteColor] {
        guard let image = NSImage(data: data),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return Self.fallback
        }

        let size = 40
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Self.fallback }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))

        struct Bucket { var count = 0; var red = 0.0; var green = 0.0; var blue = 0.0; var score = 0.0 }
        var buckets: [Int: Bucket] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255
            let maxValue = max(r, g, b)
            let minValue = min(r, g, b)
            let saturation = maxValue == 0 ? 0 : (maxValue - minValue) / maxValue
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            guard luminance > 0.055, luminance < 0.94 else { continue }
            let qr = Int(r * 5), qg = Int(g * 5), qb = Int(b * 5)
            let key = (qr << 8) | (qg << 4) | qb
            var bucket = buckets[key, default: Bucket()]
            bucket.count += 1
            bucket.red += r
            bucket.green += g
            bucket.blue += b
            bucket.score += 0.55 + saturation * 0.9
            buckets[key] = bucket
        }

        let candidates = buckets.values.sorted { lhs, rhs in
            lhs.score * log(Double(lhs.count) + 1) > rhs.score * log(Double(rhs.count) + 1)
        }.compactMap { bucket -> PaletteColor? in
            guard bucket.count > 0 else { return nil }
            return PaletteColor(
                red: bucket.red / Double(bucket.count),
                green: bucket.green / Double(bucket.count),
                blue: bucket.blue / Double(bucket.count)
            )
        }

        var selected: [PaletteColor] = []
        for candidate in candidates {
            let sufficientlyDifferent = selected.allSatisfy {
                let distance = pow(candidate.red - $0.red, 2) + pow(candidate.green - $0.green, 2) + pow(candidate.blue - $0.blue, 2)
                return distance > 0.025
            }
            if sufficientlyDifferent { selected.append(candidate) }
            if selected.count == 5 { break }
        }
        return selected.count >= 3 ? selected : selected + Self.fallback.prefix(5 - selected.count)
    }

    static let fallback = [
        PaletteColor(red: 0.18, green: 0.25, blue: 0.42),
        PaletteColor(red: 0.35, green: 0.17, blue: 0.37),
        PaletteColor(red: 0.10, green: 0.33, blue: 0.35),
        PaletteColor(red: 0.34, green: 0.24, blue: 0.16),
        PaletteColor(red: 0.14, green: 0.16, blue: 0.24)
    ]
}
