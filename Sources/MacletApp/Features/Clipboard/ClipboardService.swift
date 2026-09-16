import AppKit

enum ClipboardPayload {
    case empty
    case text(String)
    case image(NSImage)
    case unsupported

    var isCopyable: Bool {
        switch self {
        case .text(let value):
            return !value.isEmpty
        case .image:
            return true
        case .empty, .unsupported:
            return false
        }
    }
}

struct ClipboardSnapshot {
    let payload: ClipboardPayload
    let changeCount: Int
}

struct ClipboardHistoryItem: Identifiable {
    let id: String
    let payload: ClipboardPayload
    let capturedAt: Date
    let changeCount: Int
}

enum ClipboardError: LocalizedError {
    case notCopyable
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .notCopyable:
            return "The current clipboard item cannot be copied."
        case .writeFailed:
            return "The clipboard could not be updated."
        }
    }
}

protocol ClipboardManaging {
    func readSnapshot() -> ClipboardSnapshot
    func write(_ payload: ClipboardPayload) throws
}

struct PasteboardClipboardManager: ClipboardManaging {
    func readSnapshot() -> ClipboardSnapshot {
        let pasteboard = NSPasteboard.general
        let payload: ClipboardPayload

        if let image = NSImage(pasteboard: pasteboard) {
            payload = .image(image)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            payload = .text(text)
        } else if pasteboard.types?.isEmpty ?? true {
            payload = .empty
        } else {
            payload = .unsupported
        }

        return ClipboardSnapshot(payload: payload, changeCount: pasteboard.changeCount)
    }

    func write(_ payload: ClipboardPayload) throws {
        let pasteboard = NSPasteboard.general

        switch payload {
        case .text(let value) where !value.isEmpty:
            pasteboard.clearContents()
            guard pasteboard.setString(value, forType: .string) else {
                throw ClipboardError.writeFailed
            }
        case .image(let image):
            pasteboard.clearContents()
            guard pasteboard.writeObjects([image]) else {
                throw ClipboardError.writeFailed
            }
        case .text, .empty, .unsupported:
            throw ClipboardError.notCopyable
        }
    }
}

extension ClipboardPayload {
    var historyIdentifier: String? {
        switch self {
        case .empty, .unsupported:
            return nil
        case .text(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            return "text:\(Data(trimmed.utf8).stableFingerprint)"
        case .image(let image):
            if let data = image.tiffRepresentation {
                return "image:\(data.stableFingerprint)"
            }
            return "image:\(Int(image.size.width))x\(Int(image.size.height))"
        }
    }
}

private extension Data {
    var stableFingerprint: String {
        let hash = reduce(UInt64(14_695_981_039_346_656_037)) { result, byte in
            (result ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
