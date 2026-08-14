import XCTest
@testable import DutchCommute

final class APIKeyTests: XCTestCase {
    func testParsesQuotedValue() {
        XCTAssertEqual(APIKey.parse("NS_API_KEY=\"abc123\"\n"), "abc123")
    }

    func testParsesUnquotedValue() {
        XCTAssertEqual(APIKey.parse("NS_API_KEY=abc123\n"), "abc123")
    }

    func testIgnoresCommentsAndOtherKeys() {
        let content = """
        # comment
        FOO=bar
        NS_API_KEY=xyz
        """
        XCTAssertEqual(APIKey.parse(content), "xyz")
    }

    func testReturnsEmptyWhenMissing() {
        XCTAssertEqual(APIKey.parse("FOO=bar\n"), "")
    }
}
