import Foundation

struct Entitlement: Codable, Equatable {
    static let trialDuration: TimeInterval = 30 * 86_400
    var firstOpen: Date
    var proStartedAt: Date?
    var purchasedPro = false
    var lastSeen: Date?

    var trialStart: Date { proStartedAt ?? firstOpen }
    var trialEnd: Date { trialStart.addingTimeInterval(Self.trialDuration) }

    func effective(_ now: Date) -> Date { max(now, lastSeen ?? now) }

    mutating func observe(_ now: Date) {
        lastSeen = effective(now)
    }

    func hasPro(at now: Date, free: Bool = Launch.freePeriod) -> Bool {
        let current = effective(now)
        return free || purchasedPro || (current >= trialStart && current < trialEnd)
    }

    func remainingDays(at now: Date) -> Int {
        let interval = trialEnd.timeIntervalSince(max(effective(now), trialStart))
        return max(0, Int(ceil(interval / 86_400)))
    }
}

