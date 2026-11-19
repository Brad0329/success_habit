package com.brad0329.chaerok.phone

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/**
 * 공유 메뉴의 '채록'(F-002). 투명 화면 — Dart 진입점 shareMain(lib/main.dart)이 받아서 폰에 저장하고 알린 뒤 닫는다.
 *
 * content:// 파일은 이 화면이 끝나면 읽기 권한이 사라진다 → 'takeShare'에서 앱 폴더로 복사를 끝낸다.
 * 100MB 상한: 크기를 알면 복사 전에, 모르면 복사하며 세다가 넘는 순간 중단하고 복사본을 지운다.
 */
class ShareActivity : FlutterActivity() {
    companion object {
        private const val TAG = "chaerok"
        private const val MAX_BYTES = 100L * 1024 * 1024
    }

    override fun getDartEntrypointFunctionName(): String = "shareMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chaerok/share").setMethodCallHandler { call, result ->
            when (call.method) {
                "filesDir" -> result.success(filesDir.absolutePath)
                "takeShare" -> {
                    val main = Handler(Looper.getMainLooper())
                    Thread {
                        try {
                            val share = takeShare(intent)
                            main.post { result.success(share) }
                        } catch (e: Exception) {
                            Log.e(TAG, "공유 받기 실패: ${e.javaClass.simpleName}")
                            // 예외 문구에 content:// 주소·파일 이름이 섞일 수 있어 종류만 넘긴다(Dart가 앱 로그에 적는다).
                            main.post { result.error("share", e.javaClass.simpleName, null) }
                        }
                    }.start()
                }
                "finish" -> {
                    result.success(null)
                    finish()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun takeShare(intent: Intent): Map<String, Any?> {
        val inbox = File(filesDir, "share_inbox/${UUID.randomUUID()}").apply { mkdirs() }
        val files = try {
            streams(intent).mapIndexed { i, uri -> copy(uri, intent.type, File(inbox, "$i")) }
        } catch (e: Exception) {
            // 복사 도중 실패하면 경로가 Dart에 가지 않아 치울 주체가 없다 — 앞서 복사한 사본(파일당 최대 100MB)을 여기서 지운다.
            if (!inbox.deleteRecursively()) Log.w(TAG, "공유 사본 폴더를 지우지 못함: ${inbox.name}")
            throw e
        }
        return mapOf(
            "text" to intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
            "source" to source(),
            "files" to files,
            "inbox" to inbox.absolutePath,
        )
    }

    /** 공유해 온 앱 패키지. 안드로이드가 안 알려 주면 null(SCHEMA '모르면 null'). 보낸 앱이 위조할 수 있다 — 참고용. */
    private fun source(): String? {
        val host = referrer?.host
        return if (host.isNullOrEmpty() || host == packageName) null else host
    }

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND -> listOfNotNull(
            if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else intent.getParcelableExtra(Intent.EXTRA_STREAM)
        )
        Intent.ACTION_SEND_MULTIPLE -> (
            if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        ) ?: emptyList()
        else -> emptyList()
    }

    private fun copy(uri: Uri, intentType: String?, dest: File): Map<String, Any?> {
        var name: String? = null
        var size: Long? = null
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val s = c.getColumnIndex(OpenableColumns.SIZE)
                if (n >= 0 && !c.isNull(n)) name = c.getString(n)
                if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
            }
        }
        if (name == null) Log.w(TAG, "파일 이름을 못 받음")
        val mime = contentResolver.getType(uri) ?: intentType?.takeUnless { it.contains('*') }
        val info = mutableMapOf<String, Any?>("name" to name, "mime" to mime, "path" to null, "tooBig" to false)
        if ((size ?: 0) > MAX_BYTES) {
            Log.w(TAG, "용량 초과(크기 정보 ${size}B)")
            info["tooBig"] = true
            return info
        }
        val input = contentResolver.openInputStream(uri) ?: throw IllegalStateException("공유받은 파일을 열 수 없음")
        var total = 0L
        input.use { inp ->
            dest.outputStream().use { out ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = inp.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > MAX_BYTES) break
                    out.write(buf, 0, n)
                }
            }
        }
        if (total > MAX_BYTES) {
            dest.delete()
            Log.w(TAG, "용량 초과(복사 중 ${MAX_BYTES}B 넘음, 복사본 지움)")
            info["tooBig"] = true
            return info
        }
        info["path"] = dest.absolutePath
        return info
    }
}
