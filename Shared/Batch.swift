import Foundation

struct PhotoItem: Codable, Identifiable, Sendable {
    var id = UUID()
    var file: String?
    var issue: ToneError?
    var makesSDR = false
    var identity: String?
}

enum SaveStage: String, Codable, Sendable {
    case queued, rendering, writing, saved, failed, unknown
}

struct SaveItem: Codable, Identifiable, Sendable {
    let id: UUID
    var stage: SaveStage = .queued
    var issue: ToneError?
}

struct SaveJob: Codable, Identifiable, Sendable {
    var id = UUID()
    var items: [SaveItem]
    let recipe: Recipe
    let access: Access
    var cancelled = false
    var hadIssue = false

    init(photos: [PhotoItem], recipe: Recipe, access: Access) {
        items = photos.map { SaveItem(id: $0.id) }
        self.recipe = recipe
        self.access = access
    }

    var saved: Int { items.filter { $0.stage == .saved }.count }
    var failed: [SaveItem] { items.filter { $0.stage == .failed } }
    var unknown: [SaveItem] { items.filter { $0.stage == .unknown } }
    var pending: Int { items.filter { [.queued, .rendering, .writing].contains($0.stage) }.count }

    mutating func recoverInterrupted() {
        for index in items.indices {
            switch items[index].stage {
            case .writing: items[index].stage = .unknown
            case .rendering: items[index].stage = .queued
            default: continue
            }
            hadIssue = true
        }
    }

    mutating func prepareRetry() {
        for index in items.indices where items[index].stage == .failed {
            items[index].stage = .queued
            items[index].issue = nil
        }
    }
}

enum BatchRunner {
    @MainActor
    static func run(
        ids: [UUID],
        shouldStop: () -> Bool,
        journal: (UUID, SaveStage, ToneError?) throws -> Void,
        render: (UUID) async throws -> URL,
        write: (URL) async throws -> Void
    ) async throws {
        for id in ids {
            if shouldStop() { return }
            try journal(id, .rendering, nil)
            let output: URL
            do {
                output = try await render(id)
            } catch {
                try journal(id, .failed, ToneError.map(error))
                continue
            }
            defer { try? FileManager.default.removeItem(at: output) }
            if shouldStop() {
                try journal(id, .queued, nil)
                return
            }
            try journal(id, .writing, nil)
            do {
                try await write(output)
            } catch {
                try journal(id, .failed, ToneError.map(error, fallback: .write))
                continue
            }
            try journal(id, .saved, nil)
        }
    }
}

struct ActivityRecord: Codable {
    var totalSaved = 0
    var successfulDays: Set<DateComponents> = []
    var ratedVersions: Set<String> = []
    var milestoneOffered = false
    var reviewPending = false

    mutating func recordSave(on date: Date, calendar: Calendar = .autoupdatingCurrent) {
        totalSaved += 1
        var day = calendar.dateComponents([.era, .year, .month, .day], from: date)
        day.calendar = nil
        day.timeZone = nil
        successfulDays.insert(day)
    }

    func canRequestReview(version: String) -> Bool {
        reviewPending && successfulDays.count >= 3 && !ratedVersions.contains(version)
    }
}

