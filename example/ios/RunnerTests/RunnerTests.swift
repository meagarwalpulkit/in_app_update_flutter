import Flutter
import UIKit
import XCTest

@testable import in_app_update_flutter

class RunnerTests: XCTestCase {

  func testShowStoreUpdateWithoutArgs() {
    let plugin = InAppUpdateFlutterPlugin()

    let call = FlutterMethodCall(methodName: "showStoreUpdate", arguments: nil)

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      // Without valid arguments, the plugin should return FlutterMethodNotImplemented
      XCTAssertEqual(result as? NSObject, FlutterMethodNotImplemented as NSObject)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testShowStoreUpdateIosWithNonNumericId() {
    let plugin = InAppUpdateFlutterPlugin()

    let call = FlutterMethodCall(methodName: "showStoreUpdateIos", arguments: ["appStoreId": "not-a-number"])

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      // A non-numeric appStoreId must be rejected before reaching StoreKit.
      let error = result as? FlutterError
      XCTAssertEqual(error?.code, "INVALID_APP_STORE_ID")
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testShowStoreUpdateIosWithoutAppStoreId() {
    let plugin = InAppUpdateFlutterPlugin()

    let call = FlutterMethodCall(methodName: "showStoreUpdateIos", arguments: nil)

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      // Missing appStoreId fails the argument binding and is not implemented.
      XCTAssertEqual(result as? NSObject, FlutterMethodNotImplemented as NSObject)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  private func showCall(_ appStoreId: String = "1111111111") -> FlutterMethodCall {
    FlutterMethodCall(methodName: "showStoreUpdateIos", arguments: ["appStoreId": appStoreId])
  }

  func testConcurrentShowStoreUpdateIosReturnsAlreadyRunning() {
    // Hold the first load open so the first call stays in flight.
    var pendingLoad: ((Bool, Error?) -> Void)?
    let plugin = InAppUpdateFlutterPlugin(loadProduct: { _, _, completion in
      pendingLoad = completion
    })

    var firstReplies: [Any?] = []
    plugin.handle(showCall()) { firstReplies.append($0) }

    let secondExpectation = expectation(description: "second call replies.")
    plugin.handle(showCall("2222222222")) { result in
      XCTAssertEqual((result as? FlutterError)?.code, "ALREADY_RUNNING")
      secondExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)

    // The first call must still get its own reply, exactly once.
    XCTAssertTrue(firstReplies.isEmpty)
    pendingLoad?(false, nil)
    XCTAssertEqual(firstReplies.count, 1)
    XCTAssertEqual((firstReplies.first as? FlutterError)?.code, "STORE_NOT_LOADED")
  }

  func testShowStoreUpdateIosAcceptsNewCallAfterReply() {
    let plugin = InAppUpdateFlutterPlugin(loadProduct: { _, _, completion in
      completion(false, NSError(domain: "test", code: 1))
    })

    var codes: [String?] = []
    plugin.handle(showCall()) { codes.append(($0 as? FlutterError)?.code) }
    plugin.handle(showCall()) { codes.append(($0 as? FlutterError)?.code) }

    // Neither call is rejected as ALREADY_RUNNING once the earlier one replied.
    XCTAssertEqual(codes, ["STORE_ERROR", "STORE_ERROR"])
  }

  func testInvalidAppStoreIdDoesNotBlockNextCall() {
    var loads = 0
    let plugin = InAppUpdateFlutterPlugin(loadProduct: { _, _, completion in
      loads += 1
      completion(false, nil)
    })

    var codes: [String?] = []
    plugin.handle(showCall("not-a-number")) { codes.append(($0 as? FlutterError)?.code) }
    plugin.handle(showCall()) { codes.append(($0 as? FlutterError)?.code) }

    XCTAssertEqual(codes, ["INVALID_APP_STORE_ID", "STORE_NOT_LOADED"])
    XCTAssertEqual(loads, 1)
  }

  func testPresentRepliesOnceAndBlocksCallsWhileSheetIsShown() {
    let plugin = InAppUpdateFlutterPlugin(loadProduct: { _, _, completion in
      completion(true, nil)
    })

    var replies: [Any?] = []
    let firstReply = expectation(description: "first call replies.")
    plugin.handle(showCall()) { result in
      replies.append(result)
      firstReply.fulfill()
    }
    waitForExpectations(timeout: 5)

    // Give a stray second reply time to arrive.
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    XCTAssertEqual(replies.count, 1)

    // A test host without a window can't present at all.
    if let error = replies.first as? FlutterError {
      XCTAssertEqual(error.code, "NO_VIEW_CONTROLLER")
      return
    }

    // The sheet is on screen, so another call is rejected rather than stacked.
    let secondReply = expectation(description: "second call replies.")
    plugin.handle(showCall("2222222222")) { result in
      XCTAssertEqual((result as? FlutterError)?.code, "ALREADY_RUNNING")
      secondReply.fulfill()
    }
    waitForExpectations(timeout: 1)

    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController
    let dismissed = expectation(description: "sheet dismissed.")
    root?.dismiss(animated: false) { dismissed.fulfill() }
    waitForExpectations(timeout: 5)
  }

  func testUnknownMethod() {
    let plugin = InAppUpdateFlutterPlugin()

    let call = FlutterMethodCall(methodName: "unknownMethod", arguments: nil)

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertEqual(result as? NSObject, FlutterMethodNotImplemented as NSObject)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

}
