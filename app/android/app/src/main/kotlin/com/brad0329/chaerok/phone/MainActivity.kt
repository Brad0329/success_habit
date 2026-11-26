package com.brad0329.chaerok.phone

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** 채널 "chaerok/app" — Dart가 부르는 기기 기능. 앱 files 폴더 경로(lib/platform.dart)와 F-102 위젯 다시 그리기(lib/widget_summary.dart). */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chaerok/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "filesDir" -> result.success(filesDir.absolutePath)
                "refreshWidget" -> {
                    PlanWidget.refreshAll(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
