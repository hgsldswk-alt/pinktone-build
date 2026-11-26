import Foundation

struct Draft: Codable {
    var photos: [PhotoItem] = []
    var recipe = Recipe()
    var savedPresets: [SavedPreset] = []
    var job: SaveJob?
    var activity = ActivityRecord()
}

struct Workspace: Sendable {
    let root: URL
    var source: URL { root.appendingPathComponent("Sources", isDirectory: true) }
    var output: URL { root.appendingPathComponent("Output", isDirectory: true) }
    private var manifest: URL { root.appendingPathComponent("draft.json") }

    static func open(testing: Bool) throws -> Self {
        let files = FileManager.default
        let folder = testing ? files.temporaryDirectory.appendingPathComponent("PinkToneUITest")
            : try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                            appropriateFor: nil, create: true).appendingPathComponent("PinkTone")
        if testing, files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
        return try Self(root: folder)
    }

    init(root: URL) throws {
        self.root = root
        let files = FileManager.default
        try files.createDirectory(at: source, withIntermediateDirectories: true)
        try files.createDirectory(at: output, withIntermediateDirectories: true)
        var folder = root
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try folder.setResourceValues(flags)
    }

    func load() throws -> Draft {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return Draft() }
        return try JSONDecoder().decode(Draft.self, from: Data(contentsOf: manifest))
    }

    func commit(_ draft: Draft) throws {
        do {
            try JSONEncoder().encode(draft).write(to: manifest, options: .atomic)
        } catch {
            throw ToneError.map(error)
        }
    }

    func url(for item: PhotoItem) -> URL? {
        guard let file = item.file, file == URL(fileURLWithPath: file).lastPathComponent else { return nil }
        return source.appendingPathComponent(file)
    }

    func cleanOrphans(keeping photos: [PhotoItem]) {
        let keep = Set(photos.compactMap(\.file))
        for directory in [source, output] {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                      includingPropertiesForKeys: nil)) ?? []
            for file in files where directory == output || !keep.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

