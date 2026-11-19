package com.brad0329.chaerok.phone

import android.Manifest
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import java.io.File
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 채널 "chaerok/app" — Dart(lib/platform.dart)가 부르는 기기 기능.
 * 창 포커스를 Dart에 알린다: 안드로이드 10+는 포커스를 얻기 전에 클립보드를 읽을 수 없다(F-003).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chaerok/app")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "filesDir" -> result.success(filesDir.absolutePath)
                "hasWindowFocus" -> result.success(hasWindowFocus())
                "clearClipboard" -> {
                    // F-017 비우기 — 28+는 진짜 지우기, 그 아래는 빈 글로 덮는다.
                    val cm = getSystemService(ClipboardManager::class.java)
                    if (Build.VERSION.SDK_INT >= 28) cm.clearPrimaryClip() else cm.setPrimaryClip(ClipData.newPlainText("", ""))
                    result.success(null)
                }
                "notificationsEnabled" ->
                    result.success(getSystemService(NotificationManager::class.java).areNotificationsEnabled())
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    }
                    result.success(null)
                }
                "openNotificationSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    )
                    result.success(null)
                }
                "openAppSettings" -> {
                    // 마이크 권한을 다시 켜는 곳(F-007) — 한 번 거부하면 앱이 다시 물을 수 없다.
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            .setData(android.net.Uri.fromParts("package", packageName, null))
                    )
                    result.success(null)
                }
                "openUrl" -> {
                    // F-010 링크 — 브라우저가 받는다.
                    val url = call.argument<String>("url")!!
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        result.success(null)
                    } catch (e: ActivityNotFoundException) {
                        // 메시지에 주소(수집물 본문)가 들어 있어 넘기지 않는다.
                        result.error("no_app", "열 앱 없음", null)
                    }
                }
                "openBytes" -> openBytes(call.argument<ByteArray>("data")!!, call.argument<String>("mime")!!,
                    call.argument<String>("name")!!, result)
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    /**
     * F-010 녹음 재생 — 받은 내용을 캐시 폴더 `open/`에 쓰고 FileProvider 주소로 폰 기본 앱에 넘긴다.
     * 앞서 연 파일은 지운다(한 번에 하나만 남김 — 원본은 수집물 나무에 있다). 수집물 나무 자체는 밖에 열지 않는다.
     */
    private fun openBytes(data: ByteArray, mime: String, name: String, result: MethodChannel.Result) {
        try {
            val dir = File(cacheDir, "open")
            dir.deleteRecursively()
            dir.mkdirs()
            val file = File(dir, File(name).name) // 경로 조각은 버리고 이름만
            file.writeBytes(data)
            val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
            val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(intent)
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("no_app", "열 앱 없음($mime)", null)
        } catch (e: Exception) {
            result.error("open_failed", "파일 준비 실패: ${e.javaClass.simpleName}", null)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) channel?.invokeMethod("windowFocus", null)
    }
}
