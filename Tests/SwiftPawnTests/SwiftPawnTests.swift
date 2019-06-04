@testable import SwiftPawn
import XCTest

final class SwiftPawnTests: XCTestCase {
    func testExecute() {
        do {
            let (s, o, e) = try SwiftPawn.execute(command: "git", arguments: ["git", "status"])
            print("------ status ------")
            print(s)
            print("------ stdout ------")
            print(o)
            print("------ stderr ------")
            print(e)
            print("--------------------")
        } catch {
            print(error)
        }
    }

    static var allTests = [
        ("testExecute", testExecute)
    ]
}
