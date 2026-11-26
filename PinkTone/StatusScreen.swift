import SwiftUI
import UIKit

struct StatusScreen: View {
    @ObservedObject var model: AppModel
    let starting: Bool
    let preferredPhoto: UUID?
    let edit: () -> Void
    let home: () -> Void
    let open: (Screen) -> Void
    let share: (PhotoItem, Recipe, Bool) -> Void
    let replace: (PhotoItem) -> Void

    @State private var confirming: UUID?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L.t("save.title")) {
                if !busy { HeaderButton(icon: "xmark", title: L.t("nav.home"), id: "resultHome", action: home) }
            }
            PageScroll {
                if let job = model.job {
                    if busy || job.pending > 0 { progress(job) }
                    if job.saved > 0 { success(job) }
                    if !job.failed.isEmpty { failures(job) }
                    if !job.unknown.isEmpty { unknown(job) }
                    if model.milestoneJustReached {
                        ToneButton(title: L.t("milestone.title"), icon: "rosette", id: "milestoneUnlocked", kind: .soft) {
                            open(.milestone)
                        }
                    }
                } else if busy {
                    ProgressView(L.t("save.running"))
                }
                if let issue = model.problem { ErrorNote(text: issue.localizedDescription) }
            }
            if !busy {
                BottomActions {
                    ToneButton(title: L.t("save.edit"), icon: "checkmark", id: "backToEdit", action: edit)
                }
            }
        }
    }

    private var busy: Bool { model.running || starting }

    private func progress(_ job: SaveJob) -> some View {
        let processed = job.items.count - job.pending
        return VStack(alignment: .leading, spacing: 9) {
            Text(L.t(busy ? "save.running" : "save.paused")).font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text(String(processed)).font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(L.f("save.total", job.items.count)).font(.headline)
                Spacer()
                if let index = job.items.firstIndex(where: { $0.stage == .rendering || $0.stage == .writing }) {
                    StatusPill(title: L.f("save.current", index + 1), color: Theme.apricot)
                }
            }
            .accessibilityElement(children: .combine).accessibilityIdentifier("saveProgress")
            ProgressView(value: Double(processed), total: Double(max(1, job.items.count))).tint(Theme.sage)
                .accessibilityIdentifier("saveProgressBar")
            Text(L.t("save.progressNote")).toneNote()
            if busy {
                ToneButton(title: L.t(model.stopping ? "save.stopping" : "save.stop"), icon: "stop.circle",
                           id: "cancelSave", kind: .outline, action: model.stop)
                    .disabled(model.stopping || !model.running)
            } else {
                ToneButton(title: L.t("save.resume"), icon: "play", id: "continueSave", kind: .soft) {
                    Task { await model.continueSave() }
                }
                .disabled(model.importing)
            }
        }.padding(14).toneCard()
    }

    private func success(_ job: SaveJob) -> some View {
        let succeeded = Set(job.items.filter { $0.stage == .saved }.map(\.id))
        let photos = model.draft.photos.lazy.filter { succeeded.contains($0.id) }
        let thumbnails = Array(photos.prefix(3))
        let featured = photos.first { $0.id == preferredPhoto } ?? thumbnails.first
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                SmallIcon(name: "checkmark.circle", color: Theme.sage)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.saved == 1 ? L.t("save.completedOne") : L.f("save.completed", job.saved)).font(.headline)
                        .accessibilityIdentifier("savedCount")
                    Text(L.t("save.album")).toneNote()
                }
            }
            if let featured {
                HStack(spacing: 6) {
                    ForEach(thumbnails) { item in
                        PhotoThumbnail(model: model, item: item, recipe: job.recipe, watermark: job.access.watermark)
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                }
                ToneButton(title: L.t("share.title"), icon: "rectangle.split.2x1", id: "shareCard", kind: .soft) {
                    share(featured, job.recipe, job.access.watermark)
                }.disabled(busy)
            }
        }.padding(14).toneCard()
    }

    private func failures(_ job: SaveJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(job.failed.count == 1 ? L.t("save.failedOne") : L.f("save.failed", job.failed.count))
                .font(.headline).accessibilityIdentifier("failedCount")
            ForEach(job.failed) { outcome in
                if let index = job.items.firstIndex(where: { $0.id == outcome.id }) {
                    Label(L.f("save.issueItem", index + 1, (outcome.issue ?? .write).localizedDescription),
                          systemImage: "exclamationmark.circle")
                        .toneNote().accessibilityIdentifier("failed.\(index)")
                }
                if let item = model.draft.photos.first(where: { $0.id == outcome.id }),
                   item.file == nil || [.tooLarge, .unreadable, .unavailable].contains(outcome.issue) {
                    HStack(spacing: 8) {
                        if model.canReload(item) {
                            ToneButton(title: L.t("photo.reload"), icon: "arrow.clockwise",
                                       id: "reload.\(item.id)", kind: .outline) {
                                Task { await model.reload(item) }
                            }
                        }
                        ToneButton(title: L.t("photo.replace"), icon: "photo",
                                   id: "replace.\(item.id)", kind: .outline) { replace(item) }
                    }.disabled(busy || model.importing)
                }
            }
            if job.failed.contains(where: { $0.issue == .permission }) {
                ToneButton(title: L.t("save.systemSettings"), icon: "gearshape", id: "systemSettings", kind: .outline) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            ToneButton(title: job.failed.count == 1 ? L.t("save.retryOne") : L.f("save.retry", job.failed.count),
                       icon: "arrow.clockwise",
                       id: "retryFailed", kind: .outline) {
                Task { await model.retryFailed() }
            }.disabled(busy || model.importing)
        }.padding(14).toneCard(fill: Theme.apricot.opacity(0.22))
    }

    private func unknown(_ job: SaveJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("save.unknown")).font(.headline)
            Text(L.t("save.checkAlbum")).toneNote()
            ForEach(job.unknown) { outcome in
                if let index = job.items.firstIndex(where: { $0.id == outcome.id }) {
                    if confirming != outcome.id {
                        ToneButton(title: L.f("photo.index", index + 1), icon: "questionmark.circle",
                                   id: "unknown.\(index)", kind: .outline) { confirming = outcome.id }
                    } else {
                        ToneButton(title: L.t("save.confirmMissing"), icon: "arrow.clockwise",
                                   id: "confirmUnknown.\(index)", kind: .outline) {
                            confirming = nil
                            Task { await model.retryUnknown(outcome.id) }
                        }
                        ToneButton(title: L.t("nav.cancel"), icon: "xmark", id: "cancelUnknown.\(index)", kind: .soft) {
                            confirming = nil
                        }
                    }
                }
            }
        }.padding(14).toneCard(fill: Theme.apricot.opacity(0.22))
        .disabled(busy || model.importing)
    }
}

