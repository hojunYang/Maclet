import Foundation
import ServiceManagement

enum LoginItemState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isEnabled: Bool {
        self == .enabled
    }
}

enum LoginItemError: LocalizedError {
    case requiresApproval
    case unavailable

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "Maclet needs approval in System Settings before it can start at login."
        case .unavailable:
            return "macOS did not make the login item service available for this build."
        }
    }
}

protocol LoginItemManaging {
    var state: LoginItemState { get }
    func setEnabled(_ enabled: Bool) throws
}

struct ServiceManagementLoginItemManager: LoginItemManaging {
    var state: LoginItemState {
        LoginItemState(status: SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp

        switch LoginItemState(status: service.status) {
        case .enabled where enabled:
            return
        case .disabled where !enabled:
            return
        case .requiresApproval where enabled:
            throw LoginItemError.requiresApproval
        case .unavailable:
            throw LoginItemError.unavailable
        case .enabled, .disabled, .requiresApproval:
            break
        }

        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}

private extension LoginItemState {
    init(status: SMAppService.Status) {
        switch status {
        case .notRegistered, .notFound:
            self = .disabled
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        @unknown default:
            self = .unavailable
        }
    }
}
