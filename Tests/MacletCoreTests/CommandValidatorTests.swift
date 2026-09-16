import XCTest
@testable import MacletCore

final class CommandValidatorTests: XCTestCase {
    func testValidCommandPasses() throws {
        let command = SavedCommand(title: "Echo", command: "echo hello", timeoutSeconds: 5)
        XCTAssertNoThrow(try CommandValidator.validate(command))
    }

    func testEmptyTitleFails() {
        let command = SavedCommand(title: " ", command: "echo hello")
        XCTAssertThrowsError(try CommandValidator.validate(command)) { error in
            XCTAssertEqual(error as? CommandValidationError, .emptyTitle)
        }
    }

    func testEmptyCommandFails() {
        let command = SavedCommand(title: "Echo", command: " ")
        XCTAssertThrowsError(try CommandValidator.validate(command)) { error in
            XCTAssertEqual(error as? CommandValidationError, .emptyCommand)
        }
    }

    func testInvalidWorkingDirectoryFails() {
        let path = "/tmp/maclet-missing-\(UUID().uuidString)"
        let command = SavedCommand(title: "Echo", command: "echo hello", workingDirectory: path)

        XCTAssertThrowsError(try CommandValidator.validate(command)) { error in
            XCTAssertEqual(error as? CommandValidationError, .invalidWorkingDirectory(path))
        }
    }
}
