package com.brad0329.chaerok.phone

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 채널 "chaerok/app" — Dart가 부르는 기기 기능. 앱 files 폴더 경로·F-103 링크 열기(lib/platform.dart)와
 * F-102 위젯 다시 그리기(lib/widget_summary.dart).
 */
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
                "openUrl" -> result.success(openUrl(call.arguments as? String))
                else -> result.notImplemented()
            }
        }
    }

    /** F-103 링크를 기기가 고른 앱(유튜브 앱·브라우저)으로 연다. 열 앱이 없으면 false — 화면이 문구를 띄운다. 링크 글은 로그에 남기지 않는다. */
    private fun openUrl(url: String?): Boolean {
        if (url == null) {
            Log.w(TAG, "openUrl: 링크가 글이 아님")
            return false
        }
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            true
        } catch (e: ActivityNotFoundException) {
            Log.w(TAG, "openUrl: 링크를 열 앱이 없음", e)
            false
        }
    }

    private companion object {
        const val TAG = "chaerok"
    }
}
