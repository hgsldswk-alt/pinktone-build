import Combine
import Foundation
import PhotosUI
import StoreKit
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var draft = Draft()
    @Published private(set) var entitlement = Entitlement(firstOpen: .distantPast)
    @Published private(set) var now: Date = .distantPast
    @Published private(set) var importing = false
    @Published private(set) var running = false
    @Published private(set) var stopping = false
    @Published private(set) var problem: ToneError?
    @Published private(set) var milestoneJustReached = false

    let purchases = Purchases()
    let previews = PreviewWorker()
    private let exporter = ExportWorker()
    private let clock: () -> Date
    private let disk = PurchaseDisk()
    private let workspace: Workspace?
    private var draftReadable = true
    private var entitlementReadable = true
    private var originals: [UUID: ImportSource] = [:]
    private var seedFailureTriggered = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var cachedJournal: SaveJob?

    init(workspace injected: Workspace? = nil, clock: @escaping () -> Date = Date.init,
         loadEntitlement: (() throws -> Entitlement)? = nil) {
        self.clock = clock
        workspace = injected ?? (try? Workspace.open(testing: Launch.isTesting || Launch.hostedTests))
        do {
            guard let workspace else { throw ToneError.storage }
            draft = try workspace.load()
            if var job = draft.job {
                job.recoverInterrupted()
                draft.job = job
                try workspace.commit(draft)
            }
            workspace.cleanOrphans(keeping: draft.photos)
        } catch {
            draftReadable = false
            problem = .storage
        }
        do {
            if let loadEntitlement {
                entitlement = try loadEntitlement()
            } else if Launch.isTesting || Launch.hostedTests {
                let start = clock().addingTimeInterval(Launch.arguments.contains("-expired") ? -31 * 86_400 : 0)
                entitlement = Entitlement(firstOpen: start)
                #if DEBUG
                if Launch.arguments.contains("-milestone") && draftReadable {
                    draft.activity.totalSaved = 100
                }
                #endif
            } else {
                entitlement = try disk.load(clock: clock)
            }
        } catch {
            entitlementReadable = false
            problem = .storage
        }
        now = clock()
    }

    var access: Access { Access(pro: entitlement.hasPro(at: clock(), free: Launch.isFreePeriod)) }
    var job: SaveJob? { cachedJournal ?? draft.job }
    var canOpenPhotos: Bool { draftReadable && !importing && !running }
    var hasUnfinishedJob: Bool {
        guard let job else { return false }
        return job.pending > 0 || !job.failed.isEmpty || !job.unknown.isEmpty
    }

    func refreshClock() {
        let current = clock()
        var next = entitlement
        next.observe(current)
        now = current
        if next != entitlement && entitlementReadable {
            entitlement = next
            if !Launch.isTesting && !Launch.hostedTests {
                do { try disk.save(next) } catch { problem = .storage }
            }
        }
    }

    func accept(_ transaction: StoreKit.Transaction) throws {
        guard transaction.productID == Launch.proID else { return }
        var next = entitlement
        next.purchasedPro = transaction.revocationDate == nil
        if transaction.originalPurchaseDate < next.trialStart {
            next.proStartedAt = transaction.originalPurchaseDate
        }
        next.observe(clock())
        try disk.save(next)
        entitlementReadable = true
        entitlement = next
        now = clock()
    }

    private func commit(_ next: Draft) throws {
        guard draftReadable, let workspace else { throw ToneError.storage }
        try workspace.commit(next)
        draft = next
    }

    func source(for item: PhotoItem) -> URL? { workspace?.url(for: item) }
    func canReload(_ item: PhotoItem) -> Bool { originals[item.id] != nil }

    func updateRecipe(_ recipe: Recipe) -> Bool {
        guard !running, access.allows(recipe.preset) else { return false }
        draft.recipe = recipe
        return true
    }

    func persistEditor() {
        guard !running, !importing else { return }
        do { try commit(draft) } catch { problem = ToneError.map(error) }
    }

    func select(_ picked: [PhotosPickerItem], appending: Bool) async -> Bool {
        let sources = picked.map { ($0.itemIdentifier, ImportSource.photo($0)) }
        return await importPhotos(sources, appending: appending)
    }

    #if DEBUG
    func seed(appending: Bool = false, count: Int = 6) async -> Bool {
        let sources = (0..<count).map { (Optional("seed-\($0)"), ImportSource.seed($0)) }
        return await importPhotos(sources, appending: appending)
    }
    #endif

    private func importPhotos(_ inputs: [(String?, ImportSource)], appending: Bool) async -> Bool {
        guard canOpenPhotos, !inputs.isEmpty, let workspace else { return false }
        var next = draft
        if !appending { next.photos = [] }
        let currentAccess = access
        var identifiers = Set(next.photos.compactMap(\.identity))
        var work: [(PhotoItem, ImportSource)] = []
        for (id, source) in inputs {
            if !currentAccess.pro, next.photos.count >= currentAccess.pickerLimit { break }
            if let id, !identifiers.insert(id).inserted { continue }
            let slot = PhotoItem(issue: .unavailable, identity: id)
            next.photos.append(slot)
            work.append((slot, source))
        }
        guard !work.isEmpty else { return false }
        next.job = nil
        next.activity.reviewPending = false
        if !currentAccess.allows(next.recipe.preset) { next.recipe = Recipe() }
        do { try commit(next) } catch {
            problem = ToneError.map(error)
            return false
        }
        cachedJournal = nil
        if !appending { originals.removeAll() }
        importing = true
        problem = nil
        defer {
            importing = false
            workspace.cleanOrphans(keeping: draft.photos)
        }
        for (slot, source) in work {
            originals[slot.id] = source
            let loaded = await source.load(slot, in: workspace)
            do { try replace(loaded) } catch {
                problem = ToneError.map(error)
                break
            }
        }
        return true
    }

    private func replace(_ item: PhotoItem) throws {
        guard let index = draft.photos.firstIndex(where: { $0.id == item.id }) else { throw ToneError.storage }
        var next = draft
        next.photos[index] = item
        try commit(next)
    }

    func reload(_ item: PhotoItem) async {
        guard let source = originals[item.id], let workspace, canOpenPhotos else { return }
        importing = true
        defer { importing = false }
        do { try replace(await source.load(item, in: workspace)) }
        catch { problem = ToneError.map(error) }
    }

    func replace(_ item: PhotoItem, with pickerItem: PhotosPickerItem) async {
        guard let workspace, canOpenPhotos else { return }
        importing = true
        defer {
            importing = false
            workspace.cleanOrphans(keeping: draft.photos)
        }
        let source = ImportSource.photo(pickerItem)
        originals[item.id] = source
        var slot = item
        slot.identity = pickerItem.itemIdentifier
        do { try replace(await source.load(slot, in: workspace)) }
        catch { problem = ToneError.map(error) }
    }

    func startSave() async {
        guard canOpenPhotos, access.allows(count: draft.photos.count), access.allows(draft.recipe.preset),
              !hasUnfinishedJob else { return }
        var next = draft
        next.activity.reviewPending = false
        next.job = SaveJob(photos: draft.photos, recipe: draft.recipe, access: access)
        do {
            try commit(next)
            await run(ids: next.photos.map(\.id))
        } catch { problem = ToneError.map(error) }
    }

    func continueSave() async {
        guard !running, !importing, let job else { return }
        await run(ids: job.items.filter { $0.stage == .queued }.map(\.id))
    }

    func retryFailed() async {
        guard !running, !importing, cachedJournal == nil, var job,
              !job.failed.isEmpty else { return }
        let ids = job.failed.map(\.id)
        job.prepareRetry()
        var next = draft
        next.job = job
        do {
            try commit(next)
            await run(ids: ids)
        } catch { problem = ToneError.map(error) }
    }

    func retryUnknown(_ id: UUID) async {
        guard !running, !importing, var job, let index = job.items.firstIndex(where: {
            $0.id == id && $0.stage == .unknown
        }) else { return }
        job.items[index].stage = .queued
        var next = draft
        next.job = job
        do {
            try commit(next)
            cachedJournal = nil
            await run(ids: [id])
        } catch { problem = ToneError.map(error) }
    }

    func closeCompletedSession() {
        guard !running, !importing, job != nil, !hasUnfinishedJob else { return }
        var next = draft
        next.job = nil
        next.photos = []
        do {
            try commit(next)
            originals.removeAll()
            workspace?.cleanOrphans(keeping: next.photos)
        } catch { problem = ToneError.map(error) }
    }

    func stop() { if running { stopping = true } }

    private func run(ids: [UUID]) async {
        guard !running, draftReadable, cachedJournal == nil,
              !ids.isEmpty, let job, let workspace else { return }
        running = true
        stopping = false
        problem = nil
        milestoneJustReached = false
        let oldTotal = draft.activity.totalSaved
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PinkTone save") { [weak self] in
            Task { @MainActor in
                self?.stop()
                self?.endBackgroundTask()
            }
        }
        defer {
            endBackgroundTask()
            running = false
            stopping = false
        }
        do {
            if !Launch.isTesting { try await PhotoAlbum.authorize() }
            try await BatchRunner.run(ids: ids, shouldStop: { self.stopping },
                                      journal: { try self.transition(jobID: job.id, itemID: $0, stage: $1, issue: $2) },
                                      render: { id in
                if Launch.arguments.contains("-fail-once"), !self.seedFailureTriggered, id == ids.dropFirst().first {
                    self.seedFailureTriggered = true
                    throw ToneError.noSpace
                }
                guard let item = self.draft.photos.first(where: { $0.id == id }),
                      let url = self.source(for: item) else {
                    throw self.draft.photos.first(where: { $0.id == id })?.issue ?? ToneError.unavailable
                }
                return try await self.exporter.render(url, directory: workspace.output,
                                                      recipe: job.recipe, watermark: job.access.watermark)
            }, write: { url in
                if Launch.isTesting {
                    _ = try ToneEngine.inspect(url)
                } else {
                    try await PhotoAlbum.save(url)
                }
            })
            var next = draft
            if stopping {
                next.job?.cancelled = true
                next.job?.hadIssue = true
            }
            if let current = next.job, current.saved > job.saved, current.pending == 0,
               !current.hadIssue, current.failed.isEmpty, current.unknown.isEmpty {
                next.activity.reviewPending = true
            }
            if oldTotal < 100, next.activity.totalSaved >= 100, !next.activity.milestoneOffered {
                next.activity.milestoneOffered = true
                milestoneJustReached = true
            }
            try commit(next)
        } catch {
            let issue = ToneError.map(error)
            problem = issue
            var next = draft
            if issue == .permission {
                for id in ids { try? transition(jobID: job.id, itemID: id, stage: .failed, issue: issue) }
            } else if var current = next.job {
                current.recoverInterrupted()
                next.job = current
                do { try commit(next) } catch { cachedJournal = current }
            }
        }
    }

    private func transition(jobID: UUID, itemID: UUID, stage: SaveStage, issue: ToneError?) throws {
        var next = draft
        guard var job = next.job, job.id == jobID,
              let index = job.items.firstIndex(where: { $0.id == itemID }) else { throw ToneError.storage }
        let previous = job.items[index].stage
        job.items[index].stage = stage
        job.items[index].issue = issue
        if stage == .failed || stage == .unknown { job.hadIssue = true }
        if stage == .saved, previous == .writing { next.activity.recordSave(on: clock()) }
        next.job = job
        try commit(next)
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    func savePreset(name: String, overwrite: Bool) -> Bool {
        guard access.canSavePreset, !running, !importing else { return false }
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        guard !name.isEmpty else { return false }
        var next = draft
        if let existing = next.savedPresets.firstIndex(where: { $0.name == name }) {
            guard overwrite else { return false }
            next.savedPresets[existing].recipe = next.recipe
        } else {
            next.savedPresets.append(SavedPreset(name: name, recipe: next.recipe))
        }
        do { try commit(next); return true } catch {
            problem = ToneError.map(error)
            return false
        }
    }

    func askForReviewIfReady(version: String, request: () -> Void) {
        guard !Launch.isTesting, !Launch.hostedTests, !running, !importing, problem == nil,
              !hasUnfinishedJob, draft.activity.canRequestReview(version: version) else { return }
        var next = draft
        next.activity.ratedVersions.insert(version)
        next.activity.reviewPending = false
        do { try commit(next); request() } catch { problem = ToneError.map(error) }
    }
}

