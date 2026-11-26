/// 채널 "chaerok/app"(MainActivity.kt) — 앱이 쓰는 기기 기능은 앱 files 폴더 경로(여기)와 F-102 위젯 다시 그리기(`widget_summary.dart`) 둘이다.
library;

import 'package:flutter/services.dart';

/// 앱 files 폴더 경로(계획·로그·위젯 요약이 여기 쌓인다).
Future<String> androidFilesDir() async =>
    (await const MethodChannel('chaerok/app').invokeMethod<String>('filesDir'))!;
