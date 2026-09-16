import Foundation

public enum AppFeature: String, CaseIterable, Codable, Equatable, Hashable, Identifiable, Sendable {
    case timer
    case keepDisplayOn
    case keepAwake
    case cleanKeyboard
    case clipboardHistory
    case quickCommands

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "preventSleep":
            self = .keepDisplayOn
        case "disableSleep":
            self = .keepAwake
        default:
            guard let feature = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown feature: \(value)"
                )
            }
            self = feature
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ShortcutModifier: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case function
    case control
    case option
    case shift
    case command
}

public struct GlobalShortcut: Codable, Equatable, Sendable {
    public static let defaultCommandCenter = GlobalShortcut(
        keyCode: 9,
        modifiers: [.function]
    )

    public var keyCode: UInt16
    public var modifiers: Set<ShortcutModifier>

    public init(keyCode: UInt16, modifiers: Set<ShortcutModifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    private static let currentFeatureSchemaVersion = 2
    public static let clipboardHistoryLimitOptions = [5, 10, 20, 30]
    public static let defaultClipboardHistoryLimit = 5
    public static let maximumTimerPresets = 6
    public static let maximumTimerDurationSeconds = 99 * 60 * 60 + 59 * 60 + 59

    public var enabledFeatures: Set<AppFeature>
    public var featureOrder: [AppFeature]
    public var clipboardHistoryLimit: Int
    public var commandCenterShortcut: GlobalShortcut?
    public var timerPresetSeconds: [Int]

    public init(
        enabledFeatures: Set<AppFeature> = Set(AppFeature.allCases),
        featureOrder: [AppFeature] = AppFeature.allCases,
        clipboardHistoryLimit: Int = AppSettings.defaultClipboardHistoryLimit,
        commandCenterShortcut: GlobalShortcut? = .defaultCommandCenter,
        timerPresetSeconds: [Int] = []
    ) {
        self.enabledFeatures = enabledFeatures
        self.featureOrder = AppSettings.normalizedFeatureOrder(featureOrder)
        self.clipboardHistoryLimit = AppSettings.normalizedClipboardHistoryLimit(clipboardHistoryLimit)
        self.commandCenterShortcut = commandCenterShortcut
        self.timerPresetSeconds = AppSettings.normalizedTimerPresets(timerPresetSeconds)
    }

    public static let defaults = AppSettings()

    public func isEnabled(_ feature: AppFeature) -> Bool {
        enabledFeatures.contains(feature)
    }

    public mutating func setFeature(_ feature: AppFeature, enabled: Bool) {
        if enabled {
            enabledFeatures.insert(feature)
        } else {
            enabledFeatures.remove(feature)
        }
    }

    public mutating func setFeatureOrder(_ features: [AppFeature]) {
        featureOrder = AppSettings.normalizedFeatureOrder(features)
    }

    public mutating func setClipboardHistoryLimit(_ limit: Int) {
        clipboardHistoryLimit = AppSettings.normalizedClipboardHistoryLimit(limit)
    }

    public mutating func setTimerPresets(_ values: [Int]) {
        timerPresetSeconds = AppSettings.normalizedTimerPresets(values)
    }

    public static func normalizedClipboardHistoryLimit(_ limit: Int) -> Int {
        clipboardHistoryLimitOptions.min(by: { abs($0 - limit) < abs($1 - limit) })
            ?? defaultClipboardHistoryLimit
    }

    public static func normalizedTimerPresets(_ values: [Int]) -> [Int] {
        var result: [Int] = []
        for value in values
            where value > 0
                && value <= maximumTimerDurationSeconds
                && !result.contains(value) {
            result.append(value)
            if result.count == maximumTimerPresets {
                break
            }
        }
        return result
    }

    public static func normalizedFeatureOrder(_ features: [AppFeature]) -> [AppFeature] {
        var result: [AppFeature] = []
        for feature in features + AppFeature.allCases where !result.contains(feature) {
            result.append(feature)
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case featureSchemaVersion
        case enabledFeatures
        case featureOrder
        case clipboardHistoryLimit
        case commandCenterShortcut
        case timerPresetSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let features = try container.decodeIfPresent([AppFeature].self, forKey: .enabledFeatures)
            ?? AppFeature.allCases
        var decodedFeatures = Set(features)
        let featureSchemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .featureSchemaVersion
        ) ?? 0
        if featureSchemaVersion < 1 {
            decodedFeatures.insert(.timer)
        }
        if featureSchemaVersion < 2 {
            decodedFeatures.insert(.cleanKeyboard)
        }
        enabledFeatures = decodedFeatures
        var decodedOrder = try container.decodeIfPresent([AppFeature].self, forKey: .featureOrder)
            ?? AppFeature.allCases
        if featureSchemaVersion < 2,
           !decodedOrder.contains(.cleanKeyboard),
           let keepAwakeIndex = decodedOrder.firstIndex(of: .keepAwake) {
            decodedOrder.insert(.cleanKeyboard, at: keepAwakeIndex + 1)
        }
        featureOrder = AppSettings.normalizedFeatureOrder(decodedOrder)
        clipboardHistoryLimit = AppSettings.normalizedClipboardHistoryLimit(
            try container.decodeIfPresent(Int.self, forKey: .clipboardHistoryLimit)
                ?? AppSettings.defaultClipboardHistoryLimit
        )
        if container.contains(.commandCenterShortcut) {
            commandCenterShortcut = try container.decodeIfPresent(
                GlobalShortcut.self,
                forKey: .commandCenterShortcut
            )
        } else {
            commandCenterShortcut = .defaultCommandCenter
        }
        timerPresetSeconds = AppSettings.normalizedTimerPresets(
            try container.decodeIfPresent([Int].self, forKey: .timerPresetSeconds) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            AppSettings.currentFeatureSchemaVersion,
            forKey: .featureSchemaVersion
        )
        try container.encode(
            enabledFeatures.sorted { $0.rawValue < $1.rawValue },
            forKey: .enabledFeatures
        )
        try container.encode(featureOrder, forKey: .featureOrder)
        try container.encode(clipboardHistoryLimit, forKey: .clipboardHistoryLimit)
        try container.encodeIfPresent(commandCenterShortcut, forKey: .commandCenterShortcut)
        if commandCenterShortcut == nil {
            try container.encodeNil(forKey: .commandCenterShortcut)
        }
        try container.encode(timerPresetSeconds, forKey: .timerPresetSeconds)
    }
}
