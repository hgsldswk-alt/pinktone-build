import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

struct PhotoInfo {
    let width: Int
    let height: Int
    let orientation: Int32
    let retainsAlpha: Bool
    let makesSDR: Bool
    let fileExtension: String

    var pixels: Int64 { Int64(width) * Int64(height) }

    func checkDeviceBudget() throws {
        let memory = ProcessInfo.processInfo.physicalMemory
        let pixelBudget: Int64 = memory >= 3_500_000_000 ? 54_000_000 : 26_000_000
        guard pixels <= pixelBudget else { throw ToneError.tooLarge }
    }

    init(source: CGImageSource) throws {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let w = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let h = properties[kCGImagePropertyPixelHeight as String] as? Int,
              w > 0, h > 0, w <= 24_000, h <= 24_000 else { throw ToneError.unreadable }
        let rawOrientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        orientation = Int32((1...8).contains(rawOrientation) ? rawOrientation : 1)
        width = orientation >= 5 ? h : w
        height = orientation >= 5 ? w : h
        let type = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) }
        fileExtension = type?.preferredFilenameExtension ?? "image"
        retainsAlpha = properties[kCGImagePropertyHasAlpha as String] as? Bool
            ?? (type != .jpeg && type != .heic)
        let depth = properties[kCGImagePropertyDepth as String] as? Int ?? 8
        makesSDR = depth > 8 || type?.conforms(to: .rawImage) == true
            || type?.conforms(to: .heic) == true
    }
}

struct TonePreview: @unchecked Sendable {
    let original: CGImage
    let edited: CGImage
}

final class ToneEngine {
    private struct Grade {
        let warmth: Float
        let pink: Float
        let saturation: Float
        let lift: Float
        let contrast: Float
    }

    private let outputSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let workSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
    private lazy var context = CIContext(options: [
        .workingColorSpace: workSpace,
        .outputColorSpace: outputSpace,
        .cacheIntermediates: false
    ])
    private let cubeSize = 33
    private var cubes: [Preset: Data] = [:]

    private func grade(for preset: Preset) -> Grade {
        switch preset {
        case .softpink:  return Grade(warmth: -0.045, pink: 0.165, saturation: 0.9, lift: 0.06, contrast: 0.96)
        case .white:     return Grade(warmth: -0.066, pink: -0.013, saturation: 0.69, lift: 0.115, contrast: 0.93)
        case .milktea:   return Grade(warmth: 0.085, pink: -0.035, saturation: 0.65, lift: 0.045, contrast: 0.89)
        case .rosebeige: return Grade(warmth: 0.035, pink: 0.098, saturation: 0.77, lift: 0.018, contrast: 1.02)
        case .mistpink:  return Grade(warmth: -0.035, pink: 0.16, saturation: 0.63, lift: 0.12, contrast: 0.86)
        case .cream:     return Grade(warmth: 0.065, pink: -0.009, saturation: 0.79, lift: 0.17, contrast: 0.95)
        }
    }

    private func lookup(_ preset: Preset) -> Data {
        if let data = cubes[preset] { return data }
        let grade = grade(for: preset)
        let top = Float(cubeSize - 1)
        var values = [Float]()
        values.reserveCapacity(cubeSize * cubeSize * cubeSize * 4)
        for blue in 0..<cubeSize {
            for green in 0..<cubeSize {
                for red in 0..<cubeSize {
                    let r = Float(red) / top
                    let g = Float(green) / top
                    let b = Float(blue) / top
                    let luma = 0.22897 * r + 0.69174 * g + 0.07929 * b
                    let chroma = max(r, max(g, b)) - min(r, min(g, b))
                    let hue = (g - b) / max(0.001, chroma)
                    let warmth = min(1, max(0, (r - g) * 7))
                    let skin = warmth * max(0, 1 - abs(hue - 0.48) * 1.8)
                        * min(1, chroma * 6) * max(0, 1 - chroma * 0.65)
                    let mask = min(1, luma * 7) * (1 - luma * 0.32)
                    let tint = grade.pink * mask * (1 - 0.62 * skin)
                    let whiteBalance = grade.warmth * mask * (1 - 0.55 * skin)
                    let saturation = grade.saturation + (1 - grade.saturation) * skin * 0.55
                    let lift = grade.lift * sqrt(luma) * (1 - luma)
                    let curve = (grade.contrast - 1) * (luma - 0.43) * mask
                    func channel(_ x: Float, shift: Float) -> Float {
                        let mix = luma + (x - luma) * saturation + lift + curve
                        return mix + shift * (shift >= 0 ? max(0, 1 - mix) : min(1, max(0, mix * 3)))
                    }
                    values.append(channel(r, shift: whiteBalance + tint))
                    values.append(channel(g, shift: -tint * 0.30))
                    values.append(channel(b, shift: -whiteBalance + tint * 0.53))
                    values.append(1)
                }
            }
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        cubes[preset] = data
        return data
    }

    static func source(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { throw ToneError.unreadable }
        return source
    }

    static func inspect(_ url: URL) throws -> PhotoInfo {
        try PhotoInfo(source: source(url))
    }

    static func validateInput(_ url: URL) throws -> PhotoInfo {
        let source = try Self.source(url)
        let info = try PhotoInfo(source: source)
        try info.checkDeviceBudget()
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64
        ] as CFDictionary) != nil else { throw ToneError.unreadable }
        return info
    }

    func demo(image: CGImage, recipe: Recipe, maxSide: Int) throws -> TonePreview {
        if max(image.width, image.height) <= maxSide { return try preview(image: image, recipe: recipe) }
        let ratio = CGFloat(maxSide) / CGFloat(max(image.width, image.height))
        let scaled = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: ratio, y: ratio))
        guard let thumb = context.createCGImage(scaled, from: scaled.extent.integral, format: .RGBA8,
                                                colorSpace: outputSpace) else { throw ToneError.unreadable }
        return try preview(image: thumb, recipe: recipe)
    }

    private func thumbnail(_ source: CGImageSource, maxSide: Int) throws -> CGImage {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw ToneError.unreadable }
        return image
    }

    private func average(_ image: CIImage) -> Float {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let result = filter.outputImage else { return 0.5 }
        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            if let base = bytes.baseAddress {
                context.render(result, toBitmap: base, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                               format: .RGBAf, colorSpace: workSpace)
            }
        }
        let alpha = pixel[3]
        guard alpha > 0.05 else { return 0.5 }
        return (0.229 * pixel[0] + 0.692 * pixel[1] + 0.079 * pixel[2]) / alpha
    }

    private func filtered(_ image: CIImage, recipe: Recipe, average: Float) throws -> CIImage {
        guard recipe.version == 1, (0...100).contains(recipe.strength) else { throw ToneError.unreadable }
        guard recipe.strength > 0 else { return image }
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = image
        exposure.ev = min(0.15, max(-0.12, (0.35 - average) * 0.52))
        let cube = CIFilter.colorCube()
        cube.inputImage = exposure.outputImage ?? image
        cube.cubeDimension = Float(cubeSize)
        cube.cubeData = lookup(recipe.preset)
        guard let adjusted = cube.outputImage else { throw ToneError.unreadable }
        if recipe.strength == 100 { return adjusted }
        let blend = CIFilter.dissolveTransition()
        blend.inputImage = image
        blend.targetImage = adjusted
        blend.time = Float(recipe.strength) / 100
        guard let result = blend.outputImage else { throw ToneError.unreadable }
        return result.cropped(to: image.extent)
    }

    func preview(url: URL, recipe: Recipe, maxSide: Int, watermark: Bool) throws -> TonePreview {
        let source = try Self.source(url)
        try PhotoInfo(source: source).checkDeviceBudget()
        let image = try thumbnail(source, maxSide: maxSide)
        let meter = try thumbnail(source, maxSide: 96)
        return try preview(image: image, meter: meter, recipe: recipe, watermark: watermark)
    }

    func preview(image: CGImage, recipe: Recipe) throws -> TonePreview {
        let scaled = CIImage(cgImage: image)
        let ratio = min(1, 96 / max(scaled.extent.width, scaled.extent.height))
        let small = scaled.transformed(by: CGAffineTransform(scaleX: ratio, y: ratio))
        return try makePreview(image, average: average(small), recipe: recipe, watermark: false)
    }

    private func preview(image: CGImage, meter: CGImage, recipe: Recipe, watermark: Bool) throws -> TonePreview {
        try makePreview(image, average: average(CIImage(cgImage: meter)), recipe: recipe, watermark: watermark)
    }

    private func makePreview(_ original: CGImage, average: Float, recipe: Recipe, watermark: Bool) throws -> TonePreview {
        if recipe.strength == 0 && !watermark { return TonePreview(original: original, edited: original) }
        let input = CIImage(cgImage: original)
        var result = try filtered(input, recipe: recipe, average: average)
        if watermark { result = marked(result) }
        guard let output = context.createCGImage(result, from: input.extent, format: .RGBA8, colorSpace: outputSpace) else {
            throw ToneError.unreadable
        }
        return TonePreview(original: original, edited: output)
    }

    private func marked(_ image: CIImage) -> CIImage {
        let shortSide = min(image.extent.width, image.extent.height)
        let scale = max(0.05, shortSide / 950)
        let size = CGSize(width: (114 * scale).rounded(.up), height: (34 * scale).rounded(.up))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let badge = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(white: 0.12, alpha: 0.74).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10 * scale).fill()
            ("PinkTone" as NSString).draw(at: CGPoint(x: 12 * scale, y: 5 * scale), withAttributes: [
                .font: UIFont.systemFont(ofSize: 19 * scale, weight: .semibold),
                .foregroundColor: UIColor.white
            ])
        }
        guard let cg = badge.cgImage else { return image }
        let inset = 14 * scale
        let positioned = CIImage(cgImage: cg).transformed(by: CGAffineTransform(
            translationX: image.extent.maxX - size.width - inset,
            y: image.extent.minY + inset
        ))
        return positioned.composited(over: image).cropped(to: image.extent)
    }

    func export(url: URL, to directory: URL, recipe: Recipe, watermark: Bool) throws -> URL {
        let info = try Self.inspect(url)
        try info.checkDeviceBudget()

        let capacity = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
        if let capacity, Int64(capacity) < info.pixels * 9 + 16_000_000 { throw ToneError.noSpace }

        let id = UUID().uuidString
        let backing = directory.appendingPathComponent(id + ".pixels")
        let final = directory.appendingPathComponent(id + (info.retainsAlpha ? ".png" : ".jpg"))
        defer { try? FileManager.default.removeItem(at: backing) }
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: final) } }
        try autoreleasepool {
            defer { context.clearCaches() }
            try renderStrips(url: url, info: info, recipe: recipe, watermark: watermark, to: backing)
        }
        try autoreleasepool { try encode(backing: backing, info: info, to: final) }
        let output = try Self.validateInput(final)
        guard output.width == info.width, output.height == info.height, output.orientation == 1 else {
            throw ToneError.write
        }
        completed = true
        return final
    }

    private func renderStrips(url: URL, info: PhotoInfo, recipe: Recipe, watermark: Bool, to backing: URL) throws {
        let meter = try thumbnail(Self.source(url), maxSide: 96)
        guard let raw = CIImage(contentsOf: url, options: [.applyOrientationProperty: false]) else {
            throw ToneError.unreadable
        }
        let oriented = raw.oriented(forExifOrientation: info.orientation)
        let bounds = oriented.extent
        guard bounds.width == CGFloat(info.width), bounds.height == CGFloat(info.height) else { throw ToneError.unreadable }
        let input = oriented.transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        let graded = try filtered(input, recipe: recipe, average: average(CIImage(cgImage: meter)))
        try writeStrips(watermark ? marked(graded) : graded, info: info, to: backing)
    }

    private func writeStrips(_ image: CIImage, info: PhotoInfo, to backing: URL) throws {
        try Data().write(to: backing)
        let stream = try FileHandle(forWritingTo: backing)
        defer { try? stream.close() }
        let strideBytes = info.width * 4
        let rowsPerStrip = max(1, min(256, 8_388_608 / strideBytes))
        for top in stride(from: 0, to: info.height, by: rowsPerStrip) {
            try autoreleasepool {
                let height = min(rowsPerStrip, info.height - top)
                let bottom = info.height - top - height
                let low = max(0, bottom - 2)
                let high = min(info.height, bottom + height + 2)
                let sample = CGRect(x: 0, y: low, width: info.width, height: high - low)
                guard let tile = context.createCGImage(image, from: sample, format: .RGBA8, colorSpace: outputSpace),
                      let center = tile.cropping(to: CGRect(x: 0, y: high - bottom - height, width: info.width, height: height)),
                      let bitmap = CGContext(data: nil, width: info.width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: strideBytes, space: outputSpace, bitmapInfo: bitmapInfo(info)),
                      let data = bitmap.data else { throw ToneError.write }
                bitmap.setBlendMode(.copy)
                bitmap.draw(center, in: CGRect(x: 0, y: 0, width: info.width, height: height))
                try stream.write(contentsOf: Data(bytes: data, count: strideBytes * height))
            }
        }
        try stream.close()
    }

    private func bitmapInfo(_ info: PhotoInfo) -> UInt32 {
        let alpha = info.retainsAlpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
        return CGBitmapInfo.byteOrder32Big.rawValue | alpha.rawValue
    }

    private func encode(backing: URL, info: PhotoInfo, to output: URL) throws {
        guard let provider = CGDataProvider(url: backing as CFURL),
              let image = CGImage(width: info.width, height: info.height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: info.width * 4, space: outputSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo(info)), provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(output as CFURL,
                  (info.retainsAlpha ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil) else {
            throw ToneError.write
        }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if !info.retainsAlpha { properties[kCGImageDestinationLossyCompressionQuality] = 0.95 }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            let capacity = try? output.deletingLastPathComponent()
                .resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
            if let capacity, capacity < 16_000_000 { throw ToneError.noSpace }
            throw ToneError.write
        }
    }
}

actor PreviewWorker {
    private let engine = ToneEngine()

    func render(_ url: URL, recipe: Recipe, maxSide: Int, watermark: Bool = false) throws -> TonePreview {
        try Task.checkCancellation()
        return try autoreleasepool { try engine.preview(url: url, recipe: recipe, maxSide: maxSide, watermark: watermark) }
    }

    func demo(_ image: CGImage, recipe: Recipe, maxSide: Int) throws -> TonePreview {
        try Task.checkCancellation()
        return try autoreleasepool { try engine.demo(image: image, recipe: recipe, maxSide: maxSide) }
    }
}

actor ExportWorker {
    private let engine = ToneEngine()

    func render(_ url: URL, directory: URL, recipe: Recipe, watermark: Bool) throws -> URL {
        try autoreleasepool { try engine.export(url: url, to: directory, recipe: recipe, watermark: watermark) }
    }
}

