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

  func testConcurrentCallsEachGetTheirOwnReply() {
    // Hold both loads open, then finish them in reverse order.
    var pendingLoads: [(Bool, Error?) -> Void] = []
    let plugin = InAppUpdateFlutterPlugin(loadProduct: { _, _, completion in
      pendingLoads.append(completion)
    })

    var firstReplies: [Any?] = []
    var secondReplies: [Any?] = []
    plugin.handle(showCall()) { firstReplies.append($0) }
    plugin.handle(showCall("2222222222")) { secondReplies.append($0) }
    XCTAssertEqual(pendingLoads.count, 2)

    pendingLoads[1](false, NSError(domain: "test", code: 1))
    pendingLoads[0](false, nil)

    // Before the fix, the second call overwrote a shared result: the first
    // Future never completed and the second got both replies.
    XCTAssertEqual(firstReplies.count, 1)
    XCTAssertEqual((firstReplies.first as? FlutterError)?.code, "STORE_NOT_LOADED")
    XCTAssertEqual(secondReplies.count, 1)
    XCTAssertEqual((secondReplies.first as? FlutterError)?.code, "STORE_ERROR")
  }

  func testLostLoadCallbackDoesNotBlockLaterCalls() {
    // The first load never calls back, as if StoreKit's service died.
    var loads = 0
    let plugin = InAppUpdateFlutterPlugin(loadProduct: { _, _, completion in
      loads += 1
      if loads > 1 { completion(false, NSError(domain: "test", code: 1)) }
    })

    var firstReplies: [Any?] = []
    plugin.handle(showCall()) { firstReplies.append($0) }

    var codes: [String?] = []
    plugin.handle(showCall()) { codes.append(($0 as? FlutterError)?.code) }
    plugin.handle(showCall("2222222222")) { codes.append(($0 as? FlutterError)?.code) }

    // Later calls run normally instead of failing with ALREADY_RUNNING.
    XCTAssertTrue(firstReplies.isEmpty)
    XCTAssertEqual(codes, ["STORE_ERROR", "STORE_ERROR"])
  }

  func testConcurrentLoadsPresentOnlyOneSheet() {
    var pendingLoads: [(Bool, Error?) -> Void] = []
    let plugin = InAppUpdateFlutterPlugin(loadProduct: { _, _, completion in
      pendingLoads.append(completion)
    })

    var firstReplies: [Any?] = []
    var secondReplies: [Any?] = []
    let firstReply = expectation(description: "first call replies.")
    plugin.handle(showCall()) { result in
      firstReplies.append(result)
      firstReply.fulfill()
    }
    plugin.handle(showCall("2222222222")) { secondReplies.append($0) }

    // Both loads finish back to back, while the first sheet is still animating.
    pendingLoads[0](true, nil)
    pendingLoads[1](true, nil)
    waitForExpectations(timeout: 5)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))

    XCTAssertEqual(firstReplies.count, 1)
    XCTAssertEqual(secondReplies.count, 1)

    // A test host without a window can't present at all.
    if let error = firstReplies.first as? FlutterError {
      XCTAssertEqual(error.code, "NO_VIEW_CONTROLLER")
      return
    }

    XCTAssertNil(firstReplies.first ?? nil)
    XCTAssertEqual((secondReplies.first as? FlutterError)?.code, "ALREADY_RUNNING")
    dismissPresentedSheet()
  }

  private func dismissPresentedSheet() {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController
    let dismissed = expectation(description: "sheet dismissed.")
    root?.dismiss(animated: false) { dismissed.fulfill() }
    waitForExpectations(timeout: 5)
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

    dismissPresentedSheet()
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
