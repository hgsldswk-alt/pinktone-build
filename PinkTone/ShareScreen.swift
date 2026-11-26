import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import UIKit

struct CompareInput {
    let url: URL
    let recipe: Recipe
    let watermark: Bool
}

@MainActor
enum ShareCard {
    static let width = 1080
    static let height = 1350
    static let hashtags = "#ピンク加工 #写真加工"
    static var target: URL? { Launch.storeURL ?? URL(string: "https://apps.apple.com/jp/") }

    static func qr(_ url: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let quiet = code.extent.insetBy(dx: -4, dy: -4)
        let image = code.composited(over: CIImage(color: CIColor(red: 1, green: 1, blue: 1)))
            .cropped(to: quiet).transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        return CIContext().createCGImage(image, from: image.extent)
    }

    static func render(preview: TonePreview?, recipe: Recipe?, milestonePhoto: CGImage?) throws -> UIImage {
        guard let target, let qr = qr(target) else { throw ToneError.write }
        let size = CGSize(width: width / 3, height: height / 3)
        let artwork = CardArtwork(preview: preview, recipe: recipe, milestonePhoto: milestonePhoto, qr: qr)
            .frame(width: size.width, height: size.height)
            .environment(\.dynamicTypeSize, .medium)
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        guard let image = renderer.uiImage, image.cgImage?.width == width, image.cgImage?.height == height else {
            throw ToneError.write
        }
        return image
    }
}

private struct CardArtwork: View {
    let preview: TonePreview?
    let recipe: Recipe?
    let milestonePhoto: CGImage?
    let qr: CGImage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SmallIcon(name: preview == nil ? "rosette" : "photo.on.rectangle", color: Theme.apricot)
                Spacer()
                if let recipe { StatusPill(title: L.f("share.intensity", recipe.strength)) }
            }
            if let preview, let recipe {
                Text(L.f("share.finish", recipe.preset.name)).font(.title2.weight(.bold)).lineLimit(2)
                HStack(spacing: 8) {
                    photo(preview.original, label: L.t("edit.original"))
                    photo(preview.edited, label: L.t("edit.edited"))
                }
            } else {
                Text(L.t("milestone.title")).font(.title2.weight(.bold))
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Theme.gradient)
                    if let milestonePhoto {
                        Image(decorative: milestonePhoto, scale: 1).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(6)
                    } else {
                        VStack(spacing: 10) {
                            EmptyIllustration()
                            Text("100").font(.system(size: 68, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.roseText)
                            Text(L.t("milestone.reached")).font(.subheadline)
                        }
                    }
                }
                .frame(height: 242)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Spacer(minLength: 0)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ShareCard.hashtags).font(.caption.weight(.semibold)).foregroundStyle(Theme.roseText)
                    Text(L.t(Launch.storeURL == nil ? "share.qrExample" : "share.qr"))
                        .font(.caption2)
                }
                Spacer()
                Image(decorative: qr, scale: 1).resizable().interpolation(.none)
                    .frame(width: 59, height: 59)
                    .padding(3).background(.white, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(16)
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.cardBorder, lineWidth: 3) }
        .padding(3)
        .background(.white)
    }

    private func photo(_ image: CGImage, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                Image(decorative: image, scale: 1)
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .frame(height: 230)
            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line) }
    }
}

struct ShareScreen: View {
    @ObservedObject var model: AppModel
    let compare: CompareInput?
    let close: () -> Void
    @State private var preview: TonePreview?
    @State private var image: UIImage?
    @State private var file: URL?
    @State private var photo: CGImage?
    @State private var problem: ToneError?
    @State private var copied = false
    @State private var milestoneItem: PhotosPickerItem?
    @State private var loading = false

    private var locked: Bool { compare == nil && model.draft.activity.totalSaved < 100 }
    private var title: String { L.t(compare == nil ? "milestone.title" : "share.title") }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: title) {
                HeaderButton(icon: "xmark", title: L.t("nav.close"), id: "closeShare", action: close)
            }
            PageScroll {
                if locked {
                    VStack(spacing: 10) {
                        EmptyIllustration()
                        Text(L.f("milestone.progress", model.draft.activity.totalSaved)).font(.headline)
                        ProgressView(value: Double(model.draft.activity.totalSaved), total: 100).tint(Theme.sage)
                            .accessibilityIdentifier("milestoneProgress")
                        ToneButton(title: L.t("nav.back"), icon: "chevron.left", id: "lockedMilestoneBack",
                                   kind: .soft, action: close)
                    }.padding(18).toneCard()
                } else if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .accessibilityLabel(title).accessibilityIdentifier("sharePreview")
                    if compare != nil { Text(L.t("share.privateNote")).toneNote() }
                } else if problem == nil {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 140)
                }
                if let problem { ErrorNote(text: problem.localizedDescription) }
                if !locked && compare == nil {
                    PhotosPicker(selection: $milestoneItem, matching: .images, preferredItemEncoding: .current) {
                        Label(L.t("milestone.addPhoto"), systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(ToneButtonStyle(kind: .outline))
                    .disabled(loading)
                    .accessibilityIdentifier("addMilestonePhoto")
                }
            }
            if !locked {
                BottomActions {
                    if let file {
                        ShareLink(item: file, message: Text(compare == nil ? ShareCard.hashtags : L.t("share.caption")),
                                  preview: SharePreview(title, image: Image(uiImage: image ?? UIImage()))) {
                            Label(L.t("share.action"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(ToneButtonStyle(kind: .primary))
                        .accessibilityIdentifier("shareImage")
                        .disabled(loading)
                    }
                    if let compare {
                        ToneButton(title: L.t(copied ? "share.copied" : "share.copy"),
                                   icon: copied ? "checkmark" : "document.on.document", id: "copyCode", kind: .soft) {
                            UIPasteboard.general.string = compare.recipe.code
                            copied = true
                        }
                    }
                }
            }
        }
        .task {
            guard !locked else { return }
            do {
                if let compare {
                    preview = try await model.previews.render(compare.url, recipe: compare.recipe,
                                                              maxSide: 1100, watermark: compare.watermark)
                }
                guard !Task.isCancelled else { return }
                try installCard()
            } catch {
                if !Task.isCancelled { problem = ToneError.map(error, fallback: .unreadable) }
            }
        }
        .task(id: milestoneItem) {
            guard let milestoneItem else { return }
            await addMilestonePhoto(milestoneItem)
        }
        .onDisappear { removeCard() }
    }

    private func addMilestonePhoto(_ item: PhotosPickerItem) async {
        loading = true
        defer { loading = false }
        do {
            guard let imported = try await item.loadTransferable(type: PickedFile.self) else {
                throw ToneError.unavailable
            }
            defer { try? FileManager.default.removeItem(at: imported.url) }
            let result = try await model.previews.render(imported.url, recipe: Recipe(strength: 0), maxSide: 1024)
            guard !Task.isCancelled else { return }
            photo = result.original
            try installCard()
        } catch {
            if !Task.isCancelled { problem = ToneError.map(error, fallback: .unavailable) }
        }
    }

    private func installCard() throws {
        let artwork = try ShareCard.render(preview: preview, recipe: compare?.recipe, milestonePhoto: photo)
        guard let png = artwork.pngData() else { throw ToneError.write }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("PinkTone-\(UUID()).png")
        try png.write(to: destination, options: .atomic)
        removeCard()
        image = artwork
        file = destination
        problem = nil
    }

    private func removeCard() {
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
    }
}

