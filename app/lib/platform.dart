/// 채널 "chaerok/app"(MainActivity.kt)과 클립보드 — 화면이 쓰는 기기 기능. 테스트는 같은 모양의 가짜를 넣는다.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'log.dart';

class Device {
  Device({
    required this.filesDir,
    required this.hasWindowFocus,
    required this.readClipboard,
    required this.clearClipboard,
    required this.notificationsEnabled,
    required this.requestNotificationPermission,
    required this.openNotificationSettings,
    required this.windowFocus,
    this.openAppSettings,
    this.openUrl,
    this.openBytes,
  });

  /// F-010 링크를 브라우저로 열기.
  final Future<void> Function(String url)? openUrl;

  /// F-010 녹음 재생 — 폰 파일을 폰 기본 앱으로.
  final Future<void> Function(Uint8List data, String mime, String name)? openBytes;

  final Future<String> Function() filesDir;
  final Future<bool> Function() hasWindowFocus;
  final Future<String?> Function() readClipboard;

  /// 폰 클립보드를 비운다(F-017 비우기 버튼). 삼성 키보드의 '클립보드 기록'은 시스템 것이라 남는다.
  final Future<void> Function() clearClipboard;
  final Future<bool> Function() notificationsEnabled;
  final Future<void> Function() requestNotificationPermission;
  final Future<void> Function() openNotificationSettings;

  /// 앱 정보 화면(권한 켜기) — 마이크 권한이 거부됐을 때(F-007).
  final Future<void> Function()? openAppSettings;

  /// 창이 포커스를 얻을 때마다(앱을 열 때·다른 앱에서 돌아올 때).
  final Stream<void> windowFocus;
}

Device androidDevice() {
  const ch = MethodChannel('chaerok/app');
  final focus = StreamController<void>.broadcast();
  ch.setMethodCallHandler((call) async {
    if (call.method == 'windowFocus') {
      focus.add(null);
    } else {
      logWarn('알 수 없는 채널 호출: ${call.method}');
    }
  });
  return Device(
    filesDir: () async => (await ch.invokeMethod<String>('filesDir'))!,
    hasWindowFocus: () async => await ch.invokeMethod<bool>('hasWindowFocus') ?? false,
    readClipboard: () async => (await Clipboard.getData(Clipboard.kTextPlain))?.text,
    // Flutter의 setData('')는 안드로이드 13+에서 "복사됨" 안내를 띄운다 — 네이티브 clearPrimaryClip으로 지운다.
    clearClipboard: () => ch.invokeMethod<void>('clearClipboard'),
    notificationsEnabled: () async => await ch.invokeMethod<bool>('notificationsEnabled') ?? false,
    requestNotificationPermission: () => ch.invokeMethod<void>('requestNotificationPermission'),
    openNotificationSettings: () => ch.invokeMethod<void>('openNotificationSettings'),
    windowFocus: focus.stream,
    openAppSettings: () => ch.invokeMethod<void>('openAppSettings'),
    openUrl: (url) => ch.invokeMethod<void>('openUrl', {'url': url}),
    openBytes: (data, mime, name) => ch.invokeMethod<void>('openBytes', {'data': data, 'mime': mime, 'name': name}),
  );
}
