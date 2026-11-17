import 'package:flutter/foundation.dart';
import 'package:in_app_update_flutter/in_app_update_flutter.dart';
import 'package:in_app_update_flutter/src/method_channel/in_app_update_flutter_method_channel.dart';
import 'package:in_app_update_flutter/src/platform_interface/in_app_update_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// A valid mock that extends [InAppUpdateFlutterPlatform], giving it
/// the correct token so it can be set as the platform instance.
class _MockPlatform extends InAppUpdateFlutterPlatform {
  String? lastAppStoreId;

  /// Names of the members called on this platform, in order.
  final List<String> calls = [];

  @override
  Future<void> showUpdateForIos({required String appStoreId}) async {
    calls.add('showUpdateForIos');
    lastAppStoreId = appStoreId;
  }

  @override
  Future<AppUpdateInfoIos> checkUpdateIos() async {
    calls.add('checkUpdateIos');
    return const AppUpdateInfoIos(
      updateAvailability: UpdateAvailabilityIos.updateAvailable,
      installedVersion: '2.1.0',
      storeVersion: '2.2.0',
      appStoreId: '544007664',
      storeUrl: 'https://apps.apple.com/in/app/id544007664',
      country: 'in',
      minimumOsVersion: '15.0',
    );
  }

  @override
  Future<AppUpdateInfoAndroid> checkUpdateAndroid() async {
    calls.add('checkUpdateAndroid');
    return const AppUpdateInfoAndroid(
      updateAvailability: UpdateAvailabilityAndroid.updateAvailable,
      availableVersionCode: 42,
      updatePriority: 3,
      clientVersionStalenessDays: 7,
      isImmediateUpdateAllowed: true,
      isFlexibleUpdateAllowed: true,
      installStatus: InstallStatusAndroid.unknown,
    );
  }

  @override
  Future<UpdateResultAndroid> startImmediateUpdateAndroid({
    bool allowAssetPackDeletion = false,
  }) async {
    calls.add('startImmediateUpdateAndroid');
    return UpdateResultAndroid.success;
  }

  @override
  Future<UpdateResultAndroid> startFlexibleUpdateAndroid({
    bool allowAssetPackDeletion = false,
  }) async {
    calls.add('startFlexibleUpdateAndroid');
    return UpdateResultAndroid.success;
  }

  @override
  Future<void> completeUpdateAndroid() async {
    calls.add('completeUpdateAndroid');
  }

  @override
  Stream<InstallStateAndroid> get installStateStreamAndroid {
    calls.add('installStateStreamAndroid');
    return const Stream.empty();
  }
}

/// Minimal subclass that does NOT override the abstract methods,
/// so calls fall through to the base-class throw.
class _UnimplementedPlatform extends InAppUpdateFlutterPlatform {}

void main() {
  group('InAppUpdateFlutterPlatform', () {
    tearDown(() {
      // Restore default instance after each test.
      InAppUpdateFlutterPlatform.instance = MethodChannelInAppUpdateFlutter();
    });

    test('default instance is MethodChannelInAppUpdateFlutter', () {
      expect(
        InAppUpdateFlutterPlatform.instance,
        isA<MethodChannelInAppUpdateFlutter>(),
      );
    });

    test('instance can be replaced with a valid mock', () {
      final mock = _MockPlatform();
      InAppUpdateFlutterPlatform.instance = mock;
      expect(InAppUpdateFlutterPlatform.instance, same(mock));
    });

    test('setting instance back to MethodChannel works', () {
      InAppUpdateFlutterPlatform.instance = _MockPlatform();
      InAppUpdateFlutterPlatform.instance = MethodChannelInAppUpdateFlutter();
      expect(
        InAppUpdateFlutterPlatform.instance,
        isA<MethodChannelInAppUpdateFlutter>(),
      );
    });

    group('base class throws UnimplementedError', () {
      late _UnimplementedPlatform platform;

      setUp(() {
        platform = _UnimplementedPlatform();
      });

      test('showUpdateForIos throws UnimplementedError', () {
        expect(
          () => platform.showUpdateForIos(appStoreId: '123'),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('checkUpdateIos throws UnimplementedError', () {
        expect(
          () => platform.checkUpdateIos(),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('checkUpdateAndroid throws UnimplementedError', () {
        expect(
          () => platform.checkUpdateAndroid(),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('startImmediateUpdateAndroid throws UnimplementedError', () {
        expect(
          () => platform.startImmediateUpdateAndroid(),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('startFlexibleUpdateAndroid throws UnimplementedError', () {
        expect(
          () => platform.startFlexibleUpdateAndroid(),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('completeUpdateAndroid throws UnimplementedError', () {
        expect(
          () => platform.completeUpdateAndroid(),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('installStateStreamAndroid throws UnimplementedError', () {
        expect(
          () => platform.installStateStreamAndroid,
          throwsA(isA<UnimplementedError>()),
        );
      });
    });

    group('mock platform delegates', () {
      test('showUpdateForIos passes appStoreId to mock', () async {
        final mock = _MockPlatform();
        InAppUpdateFlutterPlatform.instance = mock;

        await InAppUpdateFlutterPlatform.instance.showUpdateForIos(
          appStoreId: '544007664',
        );
        expect(mock.lastAppStoreId, '544007664');
      });

      test('checkUpdateIos returns expected info', () async {
        final mock = _MockPlatform();
        InAppUpdateFlutterPlatform.instance = mock;

        final info = await InAppUpdateFlutterPlatform.instance.checkUpdateIos();
        expect(info.updateAvailability, UpdateAvailabilityIos.updateAvailable);
        expect(info.appStoreId, '544007664');
        expect(info.country, 'in');
      });

      test('checkUpdateAndroid returns expected info', () async {
        final mock = _MockPlatform();
        InAppUpdateFlutterPlatform.instance = mock;

        final info = await InAppUpdateFlutterPlatform.instance
            .checkUpdateAndroid();
        expect(
          info.updateAvailability,
          UpdateAvailabilityAndroid.updateAvailable,
        );
        expect(info.availableVersionCode, 42);
        expect(info.updatePriority, 3);
      });

      test('startImmediateUpdateAndroid returns success', () async {
        final mock = _MockPlatform();
        InAppUpdateFlutterPlatform.instance = mock;

        final result = await InAppUpdateFlutterPlatform.instance
            .startImmediateUpdateAndroid();
        expect(result, UpdateResultAndroid.success);
      });

      test('startFlexibleUpdateAndroid returns success', () async {
        final mock = _MockPlatform();
        InAppUpdateFlutterPlatform.instance = mock;

        final result = await InAppUpdateFlutterPlatform.instance
            .startFlexibleUpdateAndroid();
        expect(result, UpdateResultAndroid.success);
      });
    });
  });

  group('InAppUpdateFlutter.checkUpdateIos', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      InAppUpdateFlutterPlatform.instance = MethodChannelInAppUpdateFlutter();
    });

    test('throws UnsupportedError when not on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        () => InAppUpdateFlutter().checkUpdateIos(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('delegates to the platform on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      InAppUpdateFlutterPlatform.instance = _MockPlatform();

      final info = await InAppUpdateFlutter().checkUpdateIos();
      expect(info.appStoreId, '544007664');
    });
  });

  group('InAppUpdateFlutter.showUpdateForIos', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      InAppUpdateFlutterPlatform.instance = MethodChannelInAppUpdateFlutter();
    });

    test('throws UnsupportedError when not on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final mock = _MockPlatform();
      InAppUpdateFlutterPlatform.instance = mock;

      expect(
        () => InAppUpdateFlutter().showUpdateForIos(appStoreId: '544007664'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(mock.calls, isEmpty);
    });

    test('delegates to the platform on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final mock = _MockPlatform();
      InAppUpdateFlutterPlatform.instance = mock;

      await InAppUpdateFlutter().showUpdateForIos(appStoreId: '544007664');
      expect(mock.lastAppStoreId, '544007664');
    });
  });

  group('InAppUpdateFlutter Android methods', () {
    // Each Android member, called through the facade.
    final members = <String, Object? Function(InAppUpdateFlutter)>{
      'checkUpdateAndroid': (p) => p.checkUpdateAndroid(),
      'startImmediateUpdateAndroid': (p) => p.startImmediateUpdateAndroid(),
      'startFlexibleUpdateAndroid': (p) => p.startFlexibleUpdateAndroid(),
      'completeUpdateAndroid': (p) => p.completeUpdateAndroid(),
      'installStateStreamAndroid': (p) => p.installStateStreamAndroid,
    };

    late _MockPlatform mock;

    setUp(() {
      mock = _MockPlatform();
      InAppUpdateFlutterPlatform.instance = mock;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      InAppUpdateFlutterPlatform.instance = MethodChannelInAppUpdateFlutter();
    });

    for (final MapEntry(key: name, value: call) in members.entries) {
      test('$name throws UnsupportedError when not on Android', () {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

        expect(
          () => call(InAppUpdateFlutter()),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'message',
              contains(name),
            ),
          ),
        );
        expect(mock.calls, isEmpty);
      });

      test('$name delegates to the platform on Android', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;

        final result = call(InAppUpdateFlutter());
        if (result is Future) await result;
        expect(mock.calls, [name]);
      });
    }
  });
}
