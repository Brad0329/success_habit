/// 채널 "chaerok/app"(MainActivity.kt) — 앱이 쓰는 기기 기능은 앱 files 폴더 경로 하나다.
library;

import 'package:flutter/services.dart';

/// 앱 files 폴더 경로(계획·로그가 여기 쌓인다).
Future<String> androidFilesDir() async =>
    (await const MethodChannel('chaerok/app').invokeMethod<String>('filesDir'))!;
