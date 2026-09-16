import Foundation

public protocol CommandRepository: Sendable {
    var rootURL: URL { get }
    func loadCommands() throws -> [SavedCommand]
    func saveCommands(_ commands: [SavedCommand]) throws
    func loadSettings() throws -> AppSettings
    func saveSettings(_ settings: AppSettings) throws
    func loadRunHistory() throws -> [CommandRunRecord]
    func saveRunHistory(_ records: [CommandRunRecord]) throws
}

public final class JSONCommandRepository: CommandRepository, @unchecked Sendable {
    public let rootURL: URL

    private var commandsURL: URL {
        rootURL.appendingPathComponent("commands.json")
    }

    private var runHistoryURL: URL {
        rootURL.appendingPathComponent("runs.json")
    }

    private var settingsURL: URL {
        rootURL.appendingPathComponent("settings.json")
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let legacyRootURL: URL?

    public init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        if let rootURL {
            self.rootURL = rootURL
            self.legacyRootURL = nil
        } else {
            self.rootURL = Self.defaultRootURL(fileManager: fileManager)
            self.legacyRootURL = Self.legacyRootURL(fileManager: fileManager)
        }
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        applicationSupportURL(fileManager: fileManager)
            .appendingPathComponent("Maclet", isDirectory: true)
    }

    static func legacyRootURL(fileManager: FileManager = .default) -> URL {
        applicationSupportURL(fileManager: fileManager)
            .appendingPathComponent("MacGyver", isDirectory: true)
    }

    private static func applicationSupportURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return baseURL
    }

    static func migrateLegacyDataIfNeeded(
        from legacyRootURL: URL,
        to rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard legacyRootURL.standardizedFileURL != rootURL.standardizedFileURL,
              !fileManager.fileExists(atPath: rootURL.path),
              fileManager.fileExists(atPath: legacyRootURL.path) else {
            return
        }

        try fileManager.createDirectory(
            at: rootURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: legacyRootURL, to: rootURL)
    }

    public func loadCommands() throws -> [SavedCommand] {
        try ensureDirectory()
        guard fileManager.fileExists(atPath: commandsURL.path) else {
            try saveCommands(CommandPresets.defaults)
            return CommandPresets.defaults
        }

        let data = try Data(contentsOf: commandsURL)
        return try decoder.decode([SavedCommand].self, from: data)
    }

    public func saveCommands(_ commands: [SavedCommand]) throws {
        try ensureDirectory()
        let data = try encoder.encode(commands)
        try data.write(to: commandsURL, options: [.atomic])
    }

    public func loadSettings() throws -> AppSettings {
        try ensureDirectory()
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            try saveSettings(.defaults)
            return .defaults
        }

        let data = try Data(contentsOf: settingsURL)
        return try decoder.decode(AppSettings.self, from: data)
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try ensureDirectory()
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: [.atomic])
    }

    public func loadRunHistory() throws -> [CommandRunRecord] {
        try ensureDirectory()
        guard fileManager.fileExists(atPath: runHistoryURL.path) else {
            try saveRunHistory([])
            return []
        }

        let data = try Data(contentsOf: runHistoryURL)
        return try decoder.decode([CommandRunRecord].self, from: data)
    }

    public func saveRunHistory(_ records: [CommandRunRecord]) throws {
        try ensureDirectory()
        let data = try encoder.encode(records)
        try data.write(to: runHistoryURL, options: [.atomic])
    }

    private func ensureDirectory() throws {
        if let legacyRootURL {
            try Self.migrateLegacyDataIfNeeded(
                from: legacyRootURL,
                to: rootURL,
                fileManager: fileManager
            )
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }
}
