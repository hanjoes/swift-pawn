@testable import SwiftPawn
import XCTest

final class SwiftPawnTests: XCTestCase {
    func testExecute() {
        do {
            let (status, out, err) = try SwiftPawn.execute(command: "git", arguments: ["git", "status"])
            print("------ status ------")
            print(status)
            print("------ stdout ------")
            print(out)
            print("------ stderr ------")
            print(err)
            print("--------------------")
        } catch {
            print(error)
        }
    }

    static var allTests = [
        ("testExecute", testExecute)
    ]
}
