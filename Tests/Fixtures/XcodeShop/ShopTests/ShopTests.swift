@testable import Shop
import XCTest

final class ShopTests: XCTestCase {
  func testTitle() {
    XCTAssertFalse(String(describing: ShopApp.self).isEmpty)
  }
}
