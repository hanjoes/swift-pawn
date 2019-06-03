@testable import SwiftPawn
import XCTest

final class SwiftPawnTests: XCTestCase {
    func testExecute() {
        do {
            try SwiftPawn.execute(command: "git", arguments: ["git", "status"])
        } catch {
            print(error)
        }
    }

    func testNonBlockExecute() {
        do {
            try SwiftPawn.nonBlockedExecute(command: "git", arguments: ["git", "status"])
        } catch {
            print(error)
        }
    }

    static var allTests = [
        ("testExecute", testExecute),
        ("testNonBlockExecute", testNonBlockExecute),
    ]
}
