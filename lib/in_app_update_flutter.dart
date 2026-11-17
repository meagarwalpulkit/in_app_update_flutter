import 'package:flutter/foundation.dart';
import 'package:in_app_update_flutter/src/models/models.dart';
import 'package:in_app_update_flutter/src/platform_interface/in_app_update_flutter_platform_interface.dart';

export 'package:in_app_update_flutter/src/models/models.dart';

/// A Flutter plugin for in-app updates.
///
/// On iOS, use [checkUpdateIos] to compare the installed version with the
/// App Store version, then [showUpdateForIos] to present the App Store
/// product page using StoreKit.
///
/// On Android, use [checkUpdateAndroid] to check for updates via Google Play's
/// In-App Updates API, then [startImmediateUpdateAndroid] or
/// [startFlexibleUpdateAndroid] to start the update flow.
class InAppUpdateFlutter {
  /// iOS: Shows the App Store product page overlay via StoreKit.
  ///
  /// [appStoreId] is the numeric App Store ID of your app
  /// (found in your App Store Connect URL).
  ///
  /// Throws an [UnsupportedError] when not running on iOS.
  Future<void> showUpdateForIos({required String appStoreId}) {
    _requireIos('showUpdateForIos()');
    return InAppUpdateFlutterPlatform.instance.showUpdateForIos(
      appStoreId: appStoreId,
    );
  }

  /// iOS: Checks whether a newer version of this app is on the App Store.
  ///
  /// Looks up this app's bundle ID in the device's App Store storefront via
  /// Apple's iTunes Lookup endpoint and compares the store version with the
  /// installed one. Returns an [AppUpdateInfoIos]; pass its
  /// [AppUpdateInfoIos.appStoreId] to [showUpdateForIos].
  ///
  /// Throws an [UnsupportedError] when not running on iOS.
  Future<AppUpdateInfoIos> checkUpdateIos() {
    _requireIos('checkUpdateIos()');
    return InAppUpdateFlutterPlatform.instance.checkUpdateIos();
  }

  /// Android: Checks whether an in-app update is available via Play Core.
  ///
  /// Returns an [AppUpdateInfoAndroid] containing update metadata such as
  /// availability, version code, priority, staleness, and allowed update types.
  ///
  /// Throws an [UnsupportedError] when not running on Android.
  Future<AppUpdateInfoAndroid> checkUpdateAndroid() {
    _requireAndroid('checkUpdateAndroid()');
    return InAppUpdateFlutterPlatform.instance.checkUpdateAndroid();
  }

  /// Android: Starts the immediate (full-screen, blocking) update flow.
  ///
  /// The user must accept the update to continue using the app. If the user
  /// closes the update screen, [UpdateResultAndroid.userCanceled] is returned.
  ///
  /// If [allowAssetPackDeletion] is `true`, the system may delete asset packs
  /// to free up storage for the update.
  ///
  /// Throws an [UnsupportedError] when not running on Android.
  Future<UpdateResultAndroid> startImmediateUpdateAndroid({
    bool allowAssetPackDeletion = false,
  }) {
    _requireAndroid('startImmediateUpdateAndroid()');
    return InAppUpdateFlutterPlatform.instance.startImmediateUpdateAndroid(
      allowAssetPackDeletion: allowAssetPackDeletion,
    );
  }

  /// Android: Starts the flexible (background download) update flow.
  ///
  /// The update downloads in the background while the user continues
  /// using the app. Listen to [installStateStreamAndroid] for download
  /// progress, and call [completeUpdateAndroid] when the download is complete.
  ///
  /// If [allowAssetPackDeletion] is `true`, the system may delete asset packs
  /// to free up storage for the update.
  ///
  /// Throws an [UnsupportedError] when not running on Android.
  Future<UpdateResultAndroid> startFlexibleUpdateAndroid({
    bool allowAssetPackDeletion = false,
  }) {
    _requireAndroid('startFlexibleUpdateAndroid()');
    return InAppUpdateFlutterPlatform.instance.startFlexibleUpdateAndroid(
      allowAssetPackDeletion: allowAssetPackDeletion,
    );
  }

  /// Android: Completes a flexible update by triggering an app restart.
  ///
  /// Call this after [installStateStreamAndroid] reports
  /// [InstallStatusAndroid.downloaded].
  ///
  /// Throws an [UnsupportedError] when not running on Android.
  Future<void> completeUpdateAndroid() {
    _requireAndroid('completeUpdateAndroid()');
    return InAppUpdateFlutterPlatform.instance.completeUpdateAndroid();
  }

  /// Android: A stream of install state changes during a flexible update.
  ///
  /// Emits [InstallStateAndroid] events with download progress and status.
  ///
  /// Throws an [UnsupportedError] when read while not running on Android.
  Stream<InstallStateAndroid> get installStateStreamAndroid {
    _requireAndroid('installStateStreamAndroid');
    return InAppUpdateFlutterPlatform.instance.installStateStreamAndroid;
  }
}

/// Throws an [UnsupportedError] naming [member] unless running on iOS.
void _requireIos(String member) {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    throw UnsupportedError('$member is only supported on iOS.');
  }
}

/// Throws an [UnsupportedError] naming [member] unless running on Android.
void _requireAndroid(String member) {
  if (defaultTargetPlatform != TargetPlatform.android) {
    throw UnsupportedError('$member is only supported on Android.');
  }
}
