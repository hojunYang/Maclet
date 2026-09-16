import XCTest
@testable import MacletCore

final class JSONCommandRepositoryTests: XCTestCase {
    func testRepositorySeedsDefaultsWhenCommandsFileDoesNotExist() throws {
        let repository = JSONCommandRepository(rootURL: makeTemporaryDirectory())

        let commands = try repository.loadCommands()

        XCTAssertFalse(commands.isEmpty)
        XCTAssertTrue(commands.contains { $0.title == "Keep Display On 1h" })
    }

    func testRepositorySavesAndLoadsCommands() throws {
        let repository = JSONCommandRepository(rootURL: makeTemporaryDirectory())
        let command = SavedCommand(title: "Echo", command: "echo persisted")

        try repository.saveCommands([command])
        let loaded = try repository.loadCommands()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, command.id)
        XCTAssertEqual(loaded.first?.title, "Echo")
        XCTAssertEqual(loaded.first?.command, "echo persisted")
    }

    func testRepositorySeedsDefaultSettingsWhenSettingsFileDoesNotExist() throws {
        let repository = JSONCommandRepository(rootURL: makeTemporaryDirectory())

        let settings = try repository.loadSettings()

        XCTAssertEqual(settings, .defaults)
        XCTAssertTrue(settings.isEnabled(.timer))
        XCTAssertTrue(settings.isEnabled(.keepDisplayOn))
        XCTAssertTrue(settings.isEnabled(.keepAwake))
        XCTAssertTrue(settings.isEnabled(.cleanKeyboard))
        XCTAssertTrue(settings.isEnabled(.clipboardHistory))
        XCTAssertTrue(settings.isEnabled(.quickCommands))
        XCTAssertEqual(settings.featureOrder, AppFeature.allCases)
        XCTAssertEqual(settings.clipboardHistoryLimit, 5)
        XCTAssertEqual(settings.commandCenterShortcut, .defaultCommandCenter)
        XCTAssertEqual(settings.timerPresetSeconds, [])
    }

    func testRepositorySavesAndLoadsSettings() throws {
        let repository = JSONCommandRepository(rootURL: makeTemporaryDirectory())
        let settings = AppSettings(
            enabledFeatures: [.keepDisplayOn, .quickCommands],
            featureOrder: [.quickCommands, .clipboardHistory, .timer, .cleanKeyboard, .keepAwake, .keepDisplayOn],
            clipboardHistoryLimit: 10,
            commandCenterShortcut: GlobalShortcut(
                keyCode: 40,
                modifiers: [.command, .shift]
            ),
            timerPresetSeconds: [300, 1_500, 3_600]
        )

        try repository.saveSettings(settings)
        let loaded = try repository.loadSettings()

        XCTAssertEqual(loaded, settings)
        XCTAssertFalse(loaded.isEnabled(.timer))
        XCTAssertTrue(loaded.isEnabled(.keepDisplayOn))
        XCTAssertFalse(loaded.isEnabled(.keepAwake))
        XCTAssertFalse(loaded.isEnabled(.clipboardHistory))
        XCTAssertTrue(loaded.isEnabled(.quickCommands))
        XCTAssertEqual(
            loaded.featureOrder,
            [.quickCommands, .clipboardHistory, .timer, .cleanKeyboard, .keepAwake, .keepDisplayOn]
        )
        XCTAssertEqual(loaded.clipboardHistoryLimit, 10)
        XCTAssertEqual(
            loaded.commandCenterShortcut,
            GlobalShortcut(keyCode: 40, modifiers: [.command, .shift])
        )
        XCTAssertEqual(loaded.timerPresetSeconds, [300, 1_500, 3_600])
    }

    func testRepositoryLoadsLegacySettingsWithoutClipboardHistoryLimit() throws {
        let rootURL = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        {
          "enabledFeatures" : [
            "clipboardHistory",
            "preventSleep"
          ]
        }
        """.write(to: rootURL.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        let repository = JSONCommandRepository(rootURL: rootURL)
        let loaded = try repository.loadSettings()

        XCTAssertTrue(loaded.isEnabled(.clipboardHistory))
        XCTAssertTrue(loaded.isEnabled(.keepDisplayOn))
        XCTAssertTrue(loaded.isEnabled(.timer))
        XCTAssertTrue(loaded.isEnabled(.cleanKeyboard))
        XCTAssertEqual(loaded.featureOrder, AppFeature.allCases)
        XCTAssertEqual(loaded.clipboardHistoryLimit, 5)
        XCTAssertEqual(loaded.commandCenterShortcut, .defaultCommandCenter)
        XCTAssertEqual(loaded.timerPresetSeconds, [])
    }

    func testTimerPresetsAreValidatedDeduplicatedAndLimited() {
        let values = [0, 300, 300, -1, 600, 900, 1_200, 1_500, 1_800, 2_100, 360_000]

        XCTAssertEqual(
            AppSettings.normalizedTimerPresets(values),
            [300, 600, 900, 1_200, 1_500, 1_800]
        )
    }

    func testFeatureOrderRemovesDuplicatesAndAppendsMissingFeatures() {
        XCTAssertEqual(
            AppSettings.normalizedFeatureOrder([.clipboardHistory, .timer, .clipboardHistory]),
            [.clipboardHistory, .timer, .keepDisplayOn, .keepAwake, .cleanKeyboard, .quickCommands]
        )
    }

    func testVersionOneSettingsMigrateCleanKeyboardAsIndependentFeature() throws {
        let data = """
        {
          "featureSchemaVersion" : 1,
          "enabledFeatures" : ["timer", "disableSleep"],
          "featureOrder" : ["timer", "disableSleep", "clipboardHistory"]
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(settings.isEnabled(.cleanKeyboard))
        XCTAssertEqual(
            settings.featureOrder,
            [.timer, .keepAwake, .cleanKeyboard, .clipboardHistory, .keepDisplayOn, .quickCommands]
        )
    }

    func testFeatureNamesEncodeUsingCurrentTitles() throws {
        let data = try JSONEncoder().encode([AppFeature.keepDisplayOn, .keepAwake])
        let names = try JSONDecoder().decode([String].self, from: data)

        XCTAssertEqual(names, ["keepDisplayOn", "keepAwake"])
    }

    func testRepositoryPersistsDisabledGlobalShortcut() throws {
        let repository = JSONCommandRepository(rootURL: makeTemporaryDirectory())
        let settings = AppSettings(commandCenterShortcut: nil)

        try repository.saveSettings(settings)
        let loaded = try repository.loadSettings()

        XCTAssertNil(loaded.commandCenterShortcut)
    }

    func testRepositorySavesAndLoadsRunHistory() throws {
        let repository = JSONCommandRepository(rootURL: makeTemporaryDirectory())
        let command = SavedCommand(title: "Echo", command: "echo persisted")
        let record = CommandRunRecord.makeImmediateFailure(command: command, stderr: "boom")

        try repository.saveRunHistory([record])
        let loaded = try repository.loadRunHistory()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, record.id)
        XCTAssertEqual(loaded.first?.commandID, command.id)
        XCTAssertEqual(loaded.first?.status, .failed)
        XCTAssertEqual(loaded.first?.stderr, "boom")
    }

    func testLegacyApplicationSupportDirectoryMigratesToMaclet() throws {
        let containerURL = makeTemporaryDirectory()
        let legacyURL = containerURL.appendingPathComponent("MacGyver", isDirectory: true)
        let macletURL = containerURL.appendingPathComponent("Maclet", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyURL, withIntermediateDirectories: true)
        try "legacy".write(
            to: legacyURL.appendingPathComponent("commands.json"),
            atomically: true,
            encoding: .utf8
        )

        try JSONCommandRepository.migrateLegacyDataIfNeeded(
            from: legacyURL,
            to: macletURL
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: macletURL.path))
        XCTAssertEqual(
            try String(contentsOf: macletURL.appendingPathComponent("commands.json")),
            "legacy"
        )
    }

    func testLegacyMigrationDoesNotOverwriteExistingMacletDirectory() throws {
        let containerURL = makeTemporaryDirectory()
        let legacyURL = containerURL.appendingPathComponent("MacGyver", isDirectory: true)
        let macletURL = containerURL.appendingPathComponent("Maclet", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: macletURL, withIntermediateDirectories: true)
        try "current".write(
            to: macletURL.appendingPathComponent("settings.json"),
            atomically: true,
            encoding: .utf8
        )

        try JSONCommandRepository.migrateLegacyDataIfNeeded(
            from: legacyURL,
            to: macletURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(
            try String(contentsOf: macletURL.appendingPathComponent("settings.json")),
            "current"
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacletTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
