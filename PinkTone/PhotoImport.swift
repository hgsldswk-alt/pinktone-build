import CoreTransferable
import Foundation
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PickedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 300_000_000 else { throw ToneError.tooLarge }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("PinkImport-\(UUID())")
            do {
                try FileManager.default.copyItem(at: received.file, to: copy)
                return Self(url: copy)
            } catch {
                throw ToneError.map(error)
            }
        }
    }
}

enum ImportSource: Sendable {
    case photo(PhotosPickerItem)
    #if DEBUG
    case seed(Int)
    #endif

    func load(_ slot: PhotoItem, in workspace: Workspace) async -> PhotoItem {
        var item = slot
        item.file = nil
        item.issue = nil
        do {
            let file: URL
            var usesLiveStill = false
            switch self {
            case .photo(let pickerItem):
                guard let result = try await pickerItem.loadTransferable(type: PickedFile.self) else {
                    throw ToneError.unavailable
                }
                file = result.url
                usesLiveStill = pickerItem.supportedContentTypes.contains { $0.identifier == "com.apple.live-photo" }
            #if DEBUG
            case .seed(let index):
                file = try await SeedPhotos.make(index)
            #endif
            }
            defer { try? FileManager.default.removeItem(at: file) }
            try Task.checkCancellation()
            let info = try await Task.detached(priority: .userInitiated) {
                try autoreleasepool { try ToneEngine.validateInput(file) }
            }.value
            try Task.checkCancellation()
            let name = "\(item.id)-\(UUID()).\(info.fileExtension)"
            try FileManager.default.moveItem(at: file, to: workspace.source.appendingPathComponent(name))
            item.file = name
            item.makesSDR = info.makesSDR || usesLiveStill
        } catch {
            item.issue = ToneError.map(error, fallback: .unavailable)
        }
        return item
    }
}

enum PhotoAlbum {
    static func authorize() async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { throw ToneError.permission }
    }

    static func save(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
            } completionHandler: { success, error in
                if success { continuation.resume() }
                else if [.denied, .restricted].contains(PHPhotoLibrary.authorizationStatus(for: .addOnly)) {
                    continuation.resume(throwing: ToneError.permission)
                }
                else { continuation.resume(throwing: error ?? ToneError.write) }
            }
        }
    }
}

