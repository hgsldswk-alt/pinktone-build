import Foundation
import Darwin

enum Preset: String, Codable, CaseIterable, Identifiable, Sendable {
    case softpink, white, milktea, rosebeige, mistpink, cream

    var id: String { rawValue }
    var name: String { L.t("preset.\(rawValue)") }
    var isFree: Bool { self == .softpink || self == .white }
}

struct Recipe: Codable, Equatable, Hashable, Sendable {
    var preset: Preset = .softpink
    var strength = 60
    var version = 1

    var code: String { "PT1:\(preset.rawValue):\(strength)" }

    private static let codePattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])PT1:([a-z]+):([0-9]{1,3})(?![\p{L}\p{N}])"#
    )

    static func parse(_ input: String) -> Recipe? {
        let text = String(input.prefix(2_000))
        let utf16Text = text as NSString
        let range = NSRange(location: 0, length: utf16Text.length)
        guard let match = codePattern.firstMatch(in: text, range: range),
              let preset = Preset(rawValue: utf16Text.substring(with: match.range(at: 1))),
              let strength = Int(utf16Text.substring(with: match.range(at: 2))),
              (0...100).contains(strength) else { return nil }
        return Recipe(preset: preset, strength: strength)
    }
}

struct Access: Codable, Equatable, Sendable {
    let pro: Bool
    var pickerLimit: Int { pro ? 0 : 3 }
    var watermark: Bool { !pro }
    var canSavePreset: Bool { pro }
    var availablePresets: [Preset] { Preset.allCases.filter { allows($0) } }

    func allows(_ preset: Preset) -> Bool { pro || preset.isFree }
    func allows(count: Int) -> Bool { count > 0 && (pro || count <= pickerLimit) }
}

struct SavedPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var recipe: Recipe
}

enum ToneError: String, Codable, LocalizedError, Sendable {
    case unavailable, unreadable, storage, noSpace, tooLarge, permission, write, store, noPurchase

    var errorDescription: String? { L.t("error.\(rawValue)") }

    static func map(_ error: Error, fallback: Self = .storage) -> Self {
        if let known = error as? Self { return known }
        let nsError = error as NSError
        if (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC)) { return .noSpace }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return map(underlying, fallback: fallback)
        }
        return fallback
    }
}

