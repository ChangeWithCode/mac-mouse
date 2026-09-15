import Foundation

/// Persists profiles and macros as JSON.
///
/// Plain JSON in Application Support rather than `UserDefaults`, so a
/// configuration can be read, diffed, checked into a dotfiles repo and copied
/// between machines. Writes are atomic: a crash mid-save leaves the previous
/// file intact rather than a truncated one.
public final class ProfileStore {

    /// The document as written to disk.
    public struct Document: Codable, Sendable {
        /// Schema version, so a future format change can migrate rather than
        /// discard someone's carefully built set-up.
        public var version: Int
        public var profiles: [Profile]
        public var macros: [Macro]
        /// User-authored presets, alongside the built-in ones.
        public var customPresets: [ScrollPreset]
        /// Whether `shellCommand` actions are permitted to run.
        public var allowsShellCommands: Bool

        public static let currentVersion = 1

        public init(
            version: Int = Document.currentVersion,
            profiles: [Profile] = [Profile.makeDefault()],
            macros: [Macro] = [],
            customPresets: [ScrollPreset] = [],
            allowsShellCommands: Bool = false
        ) {
            self.version = version
            self.profiles = profiles
            self.macros = macros
            self.customPresets = customPresets
            self.allowsShellCommands = allowsShellCommands
        }
    }

    public enum StoreError: Error, LocalizedError {
        case unsupportedVersion(found: Int, supported: Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let found, let supported):
                return "This configuration was written by a newer version of Glide "
                     + "(format \(found), this build understands \(supported))."
            }
        }
    }

    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL) {
        self.url = url
        self.encoder = JSONEncoder()
        // Readable and diffable — the whole reason for choosing JSON on disk.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.decoder = JSONDecoder()
    }

    /// Default location: `~/Library/Application Support/Glide/profiles.json`.
    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("Glide", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("profiles.json")
    }

    /// Loads the document, returning defaults when nothing has been saved yet.
    ///
    /// A document from a *newer* Glide throws rather than being silently
    /// rewritten — overwriting settings this build cannot represent would
    /// quietly destroy them.
    public func load() throws -> Document {
        guard FileManager.default.fileExists(atPath: url.path) else { return Document() }
        let data = try Data(contentsOf: url)
        let document = try decoder.decode(Document.self, from: data)
        guard document.version <= Document.currentVersion else {
            throw StoreError.unsupportedVersion(found: document.version, supported: Document.currentVersion)
        }
        return document
    }

    /// Writes atomically, so an interrupted save cannot corrupt the file.
    public func save(_ document: Document) throws {
        var copy = document
        copy.version = Document.currentVersion
        let data = try encoder.encode(copy)
        try data.write(to: url, options: .atomic)
    }

    /// Exports to an arbitrary location, for sharing a set-up.
    public func export(_ document: Document, to destination: URL) throws {
        try encoder.encode(document).write(to: destination, options: .atomic)
    }

    public func `import`(from source: URL) throws -> Document {
        try decoder.decode(Document.self, from: Data(contentsOf: source))
    }
}
