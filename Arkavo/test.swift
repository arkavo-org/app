import XCTest
  class Test: XCTestCase {
    func test() {
      XCUIApplication().launch()
      XCUIApplication().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      sleep(30)
    }
  }
