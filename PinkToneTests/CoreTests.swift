import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import PinkTone

final class CoreTests: XCTestCase {
    func testAllPresetsPreserveZeroAndIncreaseColorDistanceWithStrength() throws {
        let engine = ToneEngine()
        let sample = try swatches()
        let original = try pixels(sample)
        for preset in Preset.allCases {
            var distances: [Double] = []
            for strength in [0, 25, 60, 100] {
                let result = try engine.preview(image: sample, recipe: Recipe(preset: preset, strength: strength))
                distances.append(distance(original, try pixels(result.edited)))
            }
            XCTAssertEqual(distances[0], 0, preset.rawValue)
            XCTAssertGreaterThan(distances[1], distances[0] + 0.5, preset.rawValue)
            XCTAssertGreaterThan(distances[2], distances[1] + 0.5, preset.rawValue)
            XCTAssertGreaterThan(distances[3], distances[2] + 0.5, preset.rawValue)
            XCTAssertGreaterThan(distances[3], 2, preset.rawValue)
        }
    }

    func testSoftPinkIsVisibleOnCoffeeSampleAtDefaultStrength() throws {
        let sample = try XCTUnwrap(UIImage(named: "cafe")?.cgImage)
        let result = try ToneEngine().demo(image: sample, recipe: Recipe(), maxSide: 240)
        let original = try pixels(result.original)
        let edited = try pixels(result.edited)
        XCTAssertGreaterThan(distance(original, edited), 3.5)
        let redRelativeToGreen = stride(from: 0, to: original.count, by: 4).map { index in
            Int(edited[index]) - Int(edited[index + 1]) - Int(original[index]) + Int(original[index + 1])
        }.reduce(0, +)
        XCTAssertGreaterThan(redRelativeToGreen, original.count / 4 * 2)
    }

    func testPresetThumbnailsHavePairwiseColorDistanceOnPortrait() throws {
        let sample = try XCTUnwrap(UIImage(named: "portrait")?.cgImage)
        let engine = ToneEngine()
        let previews = try Preset.allCases.map { preset in
            let recipe = Recipe(preset: preset, strength: 100)
            let preview = try engine.demo(image: sample, recipe: recipe, maxSide: 300)
            return (preset: preset, pixels: try pixels(preview.edited))
        }
        for (index, first) in previews.enumerated() {
            for second in previews.dropFirst(index + 1) {
                let pair = "\(first.preset.rawValue) / \(second.preset.rawValue)"
                XCTAssertEqual(first.pixels.count, second.pixels.count, pair)
                XCTAssertGreaterThanOrEqual(distance(first.pixels, second.pixels), 6, pair)
            }
        }
    }

    func testCodes() {
        for preset in Preset.allCases {
            for strength in [0, 60, 100] {
                let recipe = Recipe(preset: preset, strength: strength)
                XCTAssertEqual(Recipe.parse(recipe.code), recipe)
            }
        }
        XCTAssertEqual(Recipe.parse(" PT1:softpink:25\n")?.strength, 25)
    }

    func testCodesInForwardedText() {
        let recipe = Recipe(preset: .softpink, strength: 60)
        for text in ["このプリセットの口令：PT1:softpink:60 #ピンク加工",
                     "滤镜口令：PT1:softpink:60，试试看",
                     "💌PT1:softpink:60✨",
                     "友だちから転送\r\nPT1:softpink:60\n分享给你",
                     "PT1:softpink:60 PT1:white:25"] {
            XCTAssertEqual(Recipe.parse(text), recipe, text)
        }
    }

    func testCodesRejectInvalidMatches() {
        for code in ["", "PT0:softpink:60", "PT2:softpink:60", "pt1:softpink:60", "PT1:unknown:50",
                     "PT1:softpink:101", "PT1:softpink:-1", "PT1:softpink:+1", "PT1:white:٦٠",
                     "PT1:white: 60", "PT1:white:", "PT1::60", "xPT1:white:60", "9PT1:white:60",
                     "PT1:white:60x", "PT1:white:1000", "前PT1:white:60", "PT1:white:60٢",
                     "PT1:unknown:50 PT1:white:60"] {
            XCTAssertNil(Recipe.parse(code), code.debugDescription)
        }
    }

    func testCodesSearchOnlyFirstTwoThousandCharacters() {
        let recipe = Recipe(preset: .white, strength: 60)
        let prefix = String(repeating: "👩‍💻", count: 2_000 - recipe.code.count)
        let text = prefix + recipe.code + String(repeating: "。", count: 3_000)
        XCTAssertEqual(text.count, 5_000)
        XCTAssertEqual(Recipe.parse(text), recipe)
        XCTAssertNil(Recipe.parse(String(repeating: "。", count: 2_000) + recipe.code))
    }

    func testFreeAndPremiumLimits() {
        let free = Access(pro: false)
        XCTAssertEqual(free.pickerLimit, 3)
        XCTAssertTrue(free.allows(count: 3))
        XCTAssertFalse(free.allows(count: 4))
        XCTAssertFalse(free.allows(count: 0))
        XCTAssertEqual(free.availablePresets, [.softpink, .white])
        XCTAssertTrue(free.watermark)
        XCTAssertFalse(free.canSavePreset)
        let pro = Access(pro: true)
        XCTAssertEqual(pro.pickerLimit, 0)
        XCTAssertTrue(pro.allows(count: 100))
        XCTAssertEqual(pro.availablePresets, Preset.allCases)
        XCTAssertFalse(pro.watermark)
        XCTAssertTrue(pro.canSavePreset)
    }

    func testTrialBoundaryAndClockRollback() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var value = Entitlement(firstOpen: start)
        let expiration = start.addingTimeInterval(30 * 86_400)
        XCTAssertFalse(Launch.freePeriod)
        XCTAssertTrue(value.hasPro(at: start))
        XCTAssertTrue(value.hasPro(at: expiration.addingTimeInterval(-1)))
        XCTAssertFalse(value.hasPro(at: expiration))
        XCTAssertEqual(value.remainingDays(at: start), 30)
        value.observe(expiration)
        XCTAssertFalse(value.hasPro(at: start))
        XCTAssertEqual(value.remainingDays(at: expiration), 0)
        value.purchasedPro = true
        XCTAssertTrue(value.hasPro(at: expiration.addingTimeInterval(86_400)))
    }

    @MainActor
    func testModelReadsCurrentTimeAfterEntitlementLoad() throws {
        let workspace = try scratch()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let beforeLoad = Date(timeIntervalSince1970: 2_000_000)
        let firstOpen = beforeLoad.addingTimeInterval(5)
        var clock = beforeLoad
        let model = AppModel(workspace: workspace, clock: { clock }, loadEntitlement: {
            clock = firstOpen
            return Entitlement(firstOpen: firstOpen, proStartedAt: firstOpen)
        })
        XCTAssertEqual(model.now, firstOpen)
        XCTAssertTrue(model.entitlement.hasPro(at: model.now))
        XCTAssertTrue(model.access.pro)
        clock = firstOpen.addingTimeInterval(30 * 86_400)
        XCTAssertFalse(model.access.pro)
    }

    @MainActor
    func testBatchRecordsPartialFailureAndRetriesOnlyThatItem() async throws {
        let workspace = try scratch()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let photos = (0..<3).map { _ in PhotoItem() }
        let ids = photos.map(\.id)
        var job = SaveJob(photos: photos, recipe: Recipe(), access: Access(pro: true))
        var writes: [UUID] = []
        var shouldFail = true
        func journal(id: UUID, stage: SaveStage, issue: ToneError?) throws {
            let index = try XCTUnwrap(job.items.firstIndex { $0.id == id })
            job.items[index].stage = stage
            job.items[index].issue = issue
            var draft = Draft()
            draft.photos = photos
            draft.job = job
            try workspace.commit(draft)
        }
        func render(_ id: UUID) async throws -> URL {
            if id == ids[1] && shouldFail { throw ToneError.noSpace }
            return workspace.output.appendingPathComponent(id.uuidString)
        }
        func write(_ url: URL) async throws {
            let id = try XCTUnwrap(UUID(uuidString: url.lastPathComponent))
            let persisted = try workspace.load().job
            XCTAssertEqual(persisted?.items.first(where: { $0.id == id })?.stage, .writing)
            writes.append(id)
        }
        try await BatchRunner.run(ids: ids, shouldStop: { false }, journal: journal, render: render, write: write)
        XCTAssertEqual(job.saved, 2)
        XCTAssertEqual(job.failed.map(\.id), [ids[1]])
        XCTAssertEqual(job.failed.first?.issue, .noSpace)
        XCTAssertEqual(writes, [ids[0], ids[2]])
        let retryIDs = job.failed.map(\.id)
        job.prepareRetry()
        shouldFail = false
        try await BatchRunner.run(ids: retryIDs, shouldStop: { false }, journal: journal, render: render, write: write)
        XCTAssertEqual(job.saved, 3)
        XCTAssertTrue(job.failed.isEmpty)
        XCTAssertEqual(writes, [ids[0], ids[2], ids[1]])
    }

    func testRecoveryKeepsUnknownOutOfRetryAndRatingUsesThreeDistinctDays() {
        let photos = (0..<4).map { _ in PhotoItem() }
        var job = SaveJob(photos: photos, recipe: Recipe(), access: Access(pro: true))
        job.items[0].stage = .saved
        job.items[1].stage = .writing
        job.items[2].stage = .rendering
        job.items[3].stage = .failed
        job.recoverInterrupted()
        XCTAssertEqual(job.items.map(\.stage), [.saved, .unknown, .queued, .failed])
        job.prepareRetry()
        XCTAssertEqual(job.items.map(\.stage), [.saved, .unknown, .queued, .queued])
        var history = ActivityRecord()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        history.reviewPending = true
        history.recordSave(on: start)
        history.recordSave(on: start)
        history.recordSave(on: start.addingTimeInterval(86_400))
        XCTAssertEqual(history.totalSaved, 3)
        XCTAssertFalse(history.canRequestReview(version: "1.0"))
        history.recordSave(on: start.addingTimeInterval(172_800))
        XCTAssertTrue(history.canRequestReview(version: "1.0"))
        history.ratedVersions.insert("1.0")
        XCTAssertFalse(history.canRequestReview(version: "1.0"))
    }

    func testFullSizeOrientationAndStripOrder() throws {
        let workspace = try scratch()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let engine = ToneEngine()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 335, height: 719), format: format)
            .image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 335, height: 360))
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 0, y: 360, width: 335, height: 359))
            }.cgImage)
        for orientation in [1, 3, 5, 6, 8] {
            let src = try fixture(image, as: .jpeg, orientation: orientation, in: workspace)
            let original = try Data(contentsOf: src)
            let source = try ToneEngine.inspect(src)
            let file = try engine.export(url: src, to: workspace.output, recipe: Recipe(strength: 0), watermark: false)
            let output = try ToneEngine.inspect(file)
            XCTAssertEqual(output.width, source.width)
            XCTAssertEqual(output.height, source.height)
            XCTAssertEqual(output.orientation, 1)
            let before = try engine.preview(url: src, recipe: Recipe(strength: 0), maxSide: 400, watermark: false)
            let after = try engine.preview(url: file, recipe: Recipe(strength: 0), maxSide: 400, watermark: false)
            XCTAssertLessThan(distance(try pixels(before.original), try pixels(after.original)), 4, "EXIF \(orientation)")
            XCTAssertEqual(try Data(contentsOf: src), original)
        }
    }

    func testTransparentPNGKeepsAlphaAndSize() throws {
        let workspace = try scratch()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 85, height: 95), format: format)
            .image { context in
                UIColor.orange.withAlphaComponent(0.45).setFill()
                context.fill(CGRect(x: 12, y: 12, width: 65, height: 65))
            }.cgImage)
        let src = try fixture(image, as: .png, orientation: 1, in: workspace)
        let engine = ToneEngine()
        let file = try engine.export(url: src, to: workspace.output, recipe: Recipe(), watermark: false)
        XCTAssertEqual(file.pathExtension, "png")
        let pair = try engine.preview(url: file, recipe: Recipe(strength: 0), maxSide: 95, watermark: false)
        XCTAssertEqual(pair.original.width, 85)
        XCTAssertEqual(pair.original.height, 95)
        let bytes = try pixels(pair.original)
        XCTAssertEqual(bytes[3], 0)
        let middle = (47 * 85 + 42) * 4 + 3
        XCTAssertEqual(Double(bytes[middle]), 115, accuracy: 2)
    }

    @MainActor
    func testCardDimensionsAndQR() throws {
        let sample = try swatches()
        let preview = try ToneEngine().preview(image: sample, recipe: Recipe())
        let share = try XCTUnwrap(ShareCard.render(preview: preview, recipe: Recipe(), milestonePhoto: nil).cgImage)
        let milestone = try XCTUnwrap(ShareCard.render(preview: nil, recipe: nil, milestonePhoto: nil).cgImage)
        let url = try XCTUnwrap(ShareCard.target)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                              options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        for card in [share, milestone] {
            XCTAssertEqual(card.width, 1080)
            XCTAssertEqual(card.height, 1350)
            let codes = detector.features(in: CIImage(cgImage: card)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertTrue(codes.contains(url.absoluteString))
        }
    }

    private func scratch() throws -> Workspace {
        try Workspace(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func fixture(_ image: CGImage, as type: UTType, orientation: Int, in workspace: Workspace) throws -> URL {
        let url = workspace.source.appendingPathComponent("\(UUID()).\(type.preferredFilenameExtension ?? "image")")
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        return url
    }

    private func swatches() throws -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let colors: [UIColor] = [
            UIColor(red: 0.85, green: 0.68, blue: 0.55, alpha: 1), .lightGray, .white, .darkGray,
            UIColor(red: 0.68, green: 0.43, blue: 0.34, alpha: 1),
            UIColor(red: 0.40, green: 0.48, blue: 0.32, alpha: 1)
        ]
        return try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 120, height: 60), format: format)
            .image { context in
                for (index, color) in colors.enumerated() {
                    color.setFill()
                    context.fill(CGRect(x: index * 20, y: 0, width: 20, height: 60))
                }
            }.cgImage)
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try buffer.withUnsafeMutableBytes { bytes in
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                                 bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                                 bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                                                    | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return buffer
    }

    private func distance(_ first: [UInt8], _ second: [UInt8]) -> Double {
        guard first.count == second.count, !first.isEmpty else { return .infinity }
        var sum = 0
        for i in stride(from: 0, to: first.count, by: 4) {
            sum += abs(Int(first[i]) - Int(second[i]))
            sum += abs(Int(first[i + 1]) - Int(second[i + 1]))
            sum += abs(Int(first[i + 2]) - Int(second[i + 2]))
        }
        return Double(sum) / Double(first.count / 4 * 3)
    }
}

