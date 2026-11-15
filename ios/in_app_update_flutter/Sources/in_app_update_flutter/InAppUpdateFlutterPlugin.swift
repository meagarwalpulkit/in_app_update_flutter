import UIKit
import Flutter
import StoreKit

public class InAppUpdateFlutterPlugin: NSObject, FlutterPlugin, SKStoreProductViewControllerDelegate {
  /// Loads a product into a store view controller. Calls back on the main
  /// thread, as `loadProduct(withParameters:completionBlock:)` documents.
  typealias ProductLoader = (
    SKStoreProductViewController,
    [String: Any],
    @escaping (Bool, Error?) -> Void
  ) -> Void

  private let loadProduct: ProductLoader

  public override convenience init() {
    self.init(loadProduct: { viewController, parameters, completion in
      viewController.loadProduct(withParameters: parameters, completionBlock: completion)
    })
  }

  /// Lets tests replace the StoreKit load, which can't run in unit tests.
  init(loadProduct: @escaping ProductLoader) {
    self.loadProduct = loadProduct
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "in_app_update_flutter", binaryMessenger: registrar.messenger())
    let instance = InAppUpdateFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  /// Resolves the view controller to present from at call time. Capturing the
  /// root view controller at registration is unreliable: on app launch the
  /// window/rootViewController may not be set yet (especially with scene-based
  /// lifecycles), leaving it nil for the lifetime of the plugin.
  private func topViewController() -> UIViewController? {
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }

    var top = keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  /// True if an App Store sheet is anywhere in the key window's presentation
  /// chain, including one still animating in: UIKit sets
  /// `presentedViewController` as soon as it accepts a presentation.
  ///
  /// This is the only "busy" state, and it's read from the view hierarchy
  /// rather than kept in a flag. A flag would have to be cleared by a StoreKit
  /// or UIKit callback, and one lost callback would leave every later call
  /// failing with ALREADY_RUNNING until the app restarts.
  private func isStoreSheetPresented() -> Bool {
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }

    var current = keyWindow?.rootViewController?.presentedViewController
    while let presented = current {
      if presented is SKStoreProductViewController { return true }
      current = presented.presentedViewController
    }
    return false
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "showStoreUpdateIos",
       let args = call.arguments as? [String: Any],
       let appStoreId = args["appStoreId"] as? String {
      showStoreProductView(appStoreId: appStoreId, result: result)
    } else if call.method == "checkForUpdateIos" {
      checkForUpdateIos(result: result)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  private func showStoreProductView(appStoreId: String, result: @escaping FlutterResult) {
    // StoreKit requires the iTunes item identifier as an NSNumber. Passing a
    // String causes loadProduct(withParameters:) to silently fail (loaded == false,
    // error == nil), which surfaces as STORE_NOT_LOADED.
    guard let appStoreIdNumber = Int(appStoreId) else {
      result(FlutterError(code: "INVALID_APP_STORE_ID", message: "appStoreId must be a numeric value", details: appStoreId))
      return
    }

    // One sheet at a time, matching Android's ALREADY_RUNNING. Checked here to
    // fail fast, and again before presenting, because concurrent calls each
    // load their own product and only the first to finish may present.
    let alreadyRunning = FlutterError(code: "ALREADY_RUNNING", message: "An App Store sheet is already being shown", details: nil)
    guard !isStoreSheetPresented() else {
      result(alreadyRunning)
      return
    }

    // Each call keeps its own result and replies exactly once. A shared result
    // used to be overwritten by a second call, so the first Future never
    // completed.
    var replied = false
    let finish: (Any?) -> Void = { value in
      guard !replied else { return }
      replied = true
      result(value)
    }

    let productViewController = SKStoreProductViewController()
    productViewController.delegate = self

    let parameters = [SKStoreProductParameterITunesItemIdentifier : NSNumber(value: appStoreIdNumber)]

    loadProduct(productViewController, parameters) { [weak self] loaded, error in
      guard let self = self else {
        finish(FlutterError(code: "NO_VIEW_CONTROLLER", message: "The plugin was released before the App Store sheet could be shown", details: nil))
        return
      }

      if let error = error {
        finish(FlutterError(code: "STORE_ERROR", message: "Failed to load product", details: error.localizedDescription))
        return
      }

      guard loaded else {
        finish(FlutterError(code: "STORE_NOT_LOADED", message: "Could not load product", details: nil))
        return
      }

      // Another call's sheet may have been presented while this one loaded.
      guard !self.isStoreSheetPresented() else {
        finish(alreadyRunning)
        return
      }

      guard let vc = self.topViewController() else {
        finish(FlutterError(code: "NO_VIEW_CONTROLLER", message: "No view controller available to present the App Store overlay", details: nil))
        return
      }

      // UIKit doesn't document calling the completion when it refuses a
      // presentation, so don't present onto a view controller mid-transition.
      guard !vc.isBeingPresented, !vc.isBeingDismissed else {
        finish(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Another view controller is being presented or dismissed", details: nil))
        return
      }

      vc.present(productViewController, animated: true) {
        finish(nil)
      }

      // An accepted presentation sets presentingViewController right away.
      // If it's still nil, UIKit refused and the completion won't run.
      if productViewController.presentingViewController == nil {
        finish(FlutterError(code: "NO_VIEW_CONTROLLER", message: "The App Store sheet could not be presented", details: nil))
      }
    }
  }

  public func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
    viewController.dismiss(animated: true, completion: nil)
  }

  // MARK: - checkForUpdateIos

  private func checkForUpdateIos(result: @escaping FlutterResult) {
    // Always deliver the Flutter result on the main thread.
    let reply: (Any?) -> Void = { value in
      DispatchQueue.main.async { result(value) }
    }

    guard let bundleId = Bundle.main.bundleIdentifier else {
      reply(FlutterError(code: "MISSING_BUNDLE_ID", message: "Bundle.main.bundleIdentifier is nil", details: nil))
      return
    }

    fetchStorefrontCountryCode { alpha3 in
      guard let alpha3 = alpha3, !alpha3.isEmpty,
            let alpha2 = CountryCodes.alpha3ToAlpha2[alpha3.uppercased()] else {
        reply(FlutterError(code: "STOREFRONT_UNAVAILABLE", message: "Could not determine the App Store storefront country", details: alpha3))
        return
      }
      let country = alpha2.lowercased()

      var components = URLComponents(string: "https://itunes.apple.com/lookup")!
      components.queryItems = [
        URLQueryItem(name: "bundleId", value: bundleId),
        URLQueryItem(name: "country", value: country),
      ]
      var request = URLRequest(url: components.url!)
      request.cachePolicy = .reloadIgnoringLocalCacheData

      URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
          reply(FlutterError(code: "NETWORK_ERROR", message: "The App Store lookup request failed", details: error.localizedDescription))
          return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
          reply(FlutterError(code: "INVALID_RESPONSE", message: "The App Store lookup returned no HTTP response", details: nil))
          return
        }

        guard httpResponse.statusCode == 200 else {
          reply(FlutterError(code: "HTTP_ERROR", message: "The App Store lookup returned HTTP \(httpResponse.statusCode)", details: httpResponse.statusCode))
          return
        }

        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
          reply(FlutterError(code: "INVALID_RESPONSE", message: "The App Store lookup response is not valid lookup JSON", details: nil))
          return
        }

        // UIDevice is read on the main thread, so interpret the response there.
        DispatchQueue.main.async {
          result(self.interpretLookup(results: results, bundleId: bundleId, country: country))
        }
      }.resume()
    }
  }

  /// Reads the storefront's alpha-3 country code. Uses `Storefront.current` on
  /// iOS 15+ and `SKPaymentQueue.default().storefront` on iOS 13–14, which is
  /// synchronous and slow, so it is called off the main thread.
  private func fetchStorefrontCountryCode(completion: @escaping (String?) -> Void) {
    if #available(iOS 15.0, *) {
      Task {
        let countryCode = await Storefront.current?.countryCode
        completion(countryCode)
      }
    } else {
      DispatchQueue.global(qos: .userInitiated).async {
        completion(SKPaymentQueue.default().storefront?.countryCode)
      }
    }
  }

  /// Turns the lookup `results` into the channel map, or a `FlutterError`.
  private func interpretLookup(results: [[String: Any]], bundleId: String, country: String) -> Any {
    guard let item = results.first(where: { ($0["bundleId"] as? String) == bundleId }) else {
      return FlutterError(code: "APP_NOT_FOUND", message: "No App Store app matches this bundle ID in this storefront", details: ["bundleId": bundleId, "country": country])
    }

    let installedRaw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let storeRaw = item["version"] as? String

    guard let installedRaw = installedRaw, let installed = parseVersion(installedRaw),
          let storeRaw = storeRaw, let store = parseVersion(storeRaw) else {
      return FlutterError(code: "INVALID_VERSION", message: "The installed or store version is not a numeric version", details: ["installedVersion": installedRaw, "storeVersion": storeRaw])
    }

    guard let trackId = item["trackId"] as? NSNumber,
          let trackViewUrl = item["trackViewUrl"] as? String else {
      return FlutterError(code: "INVALID_RESPONSE", message: "The App Store lookup result is missing trackId or trackViewUrl", details: nil)
    }

    let minimumOsRaw = item["minimumOsVersion"] as? String
    let minimumOs = minimumOsRaw.flatMap(parseVersion)

    let updateAvailability: String
    let minimumOsVersion: String?

    switch compareVersions(store, installed) {
    case .orderedDescending:
      let systemVersionRaw = UIDevice.current.systemVersion
      guard let minimumOs = minimumOs, let systemVersion = parseVersion(systemVersionRaw) else {
        return FlutterError(code: "INVALID_VERSION", message: "minimumOsVersion is missing or not a numeric version", details: ["minimumOsVersion": minimumOsRaw, "systemVersion": systemVersionRaw])
      }
      updateAvailability = compareVersions(systemVersion, minimumOs) == .orderedAscending
        ? "updateIncompatible"
        : "updateAvailable"
      minimumOsVersion = minimumOsRaw
    case .orderedSame:
      updateAvailability = "updateNotAvailable"
      minimumOsVersion = minimumOs == nil ? nil : minimumOsRaw
    case .orderedAscending:
      updateAvailability = "installedNewer"
      minimumOsVersion = minimumOs == nil ? nil : minimumOsRaw
    }

    return [
      "updateAvailability": updateAvailability,
      "installedVersion": installedRaw,
      "storeVersion": storeRaw,
      "appStoreId": trackId.stringValue,
      "storeUrl": trackViewUrl,
      "country": country,
      "minimumOsVersion": minimumOsVersion as Any,
    ] as [String: Any]
  }

  /// Splits a version on "." into integers. Returns nil if any component is
  /// empty or not made of ASCII digits.
  private func parseVersion(_ version: String) -> [Int]? {
    let parts = version.split(separator: ".", omittingEmptySubsequences: false)
    var numbers: [Int] = []
    for part in parts {
      guard !part.isEmpty,
            part.allSatisfy({ $0.isASCII && $0.isNumber }),
            let number = Int(part) else {
        return nil
      }
      numbers.append(number)
    }
    return numbers
  }

  /// Compares versions left to right, padding missing components with 0,
  /// so 2.1 == 2.1.0.
  private func compareVersions(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
    for index in 0..<max(lhs.count, rhs.count) {
      let left = index < lhs.count ? lhs[index] : 0
      let right = index < rhs.count ? rhs[index] : 0
      if left < right { return .orderedAscending }
      if left > right { return .orderedDescending }
    }
    return .orderedSame
  }
}
