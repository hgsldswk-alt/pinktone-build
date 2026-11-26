#if DEBUG
import UIKit

enum SeedPhotos {
    static let names = ["portrait", "cafe", "floral", "portrait", "floral", "cafe"]

    static func make(_ index: Int) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                guard names.indices.contains(index), let source = UIImage(named: names[index]) else {
                    throw ToneError.unreadable
                }
                let size: CGSize
                if index == 5 { size = CGSize(width: 4000, height: 3000) }
                else if index >= 3 { size = CGSize(width: 960, height: 640) }
                else { size = source.size }
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let raster = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    let scale = max(size.width / source.size.width, size.height / source.size.height)
                    let width = source.size.width * scale
                    let height = source.size.height * scale
                    source.draw(in: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                                           width: width, height: height))
                }
                guard let data = raster.jpegData(compressionQuality: 0.93) else { throw ToneError.unreadable }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("PinkSeed-\(UUID()).jpg")
                try data.write(to: url, options: .atomic)
                return url
            }
        }.value
    }
}
#endif

