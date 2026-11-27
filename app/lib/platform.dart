/// 채널 "chaerok/app"(MainActivity.kt) — 앱이 쓰는 기기 기능은 앱 files 폴더 경로·F-103 링크 열기(여기)와
/// F-102 위젯 다시 그리기(`widget_summary.dart`)다.
library;

import 'package:flutter/services.dart';

const _channel = MethodChannel('chaerok/app');

/// 앱 files 폴더 경로(계획·로그·위젯 요약이 여기 쌓인다).
Future<String> androidFilesDir() async => (await _channel.invokeMethod<String>('filesDir'))!;

/// F-103 링크를 기기가 고른 앱(유튜브 앱, 없으면 브라우저)으로 연다. 열 앱이 없으면 false.
/// 우리 앱은 통신하지 않는다 — 여는 앱이 자기 권한으로 받는다(매니페스트 권한 없음 그대로).
Future<bool> openExternalUrl(String url) async => (await _channel.invokeMethod<bool>('openUrl', url)) ?? false;
