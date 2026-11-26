package com.brad0329.chaerok.phone

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * F-102 홈 화면 위젯(보기 전용). 앱(Dart `widget_summary.dart`)이 `files/widget/today.json`에 **보일 글 그대로** 쓰고,
 * 여기서는 읽어 그리기만 한다 — 계획 규칙을 다시 구현하지 않는다. 하는 판단은 날짜뿐(요약한 날이 오늘·어제인가, 날짜 글)과 DON'T만 있는 날의 작은 모양.
 * 크기를 바꾸면 모양이 바뀐다(Android 12 이상, 작은 모양·큰 모양). 11 이하는 큰 모양만.
 * 누르면 앱이 열린다. 자정에 다시 그리도록 정확하지 않은 알람 하나(권한 없음 — 몇 분 늦을 수 있다).
 */
class PlanWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) draw(context, manager, id)
        scheduleMidnight(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        draw(context, manager, id)
    }

    override fun onDisabled(context: Context) {
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(midnightIntent(context))
    }

    companion object {
        private const val TAG = "PlanWidget"

        /** 앱이 요약을 새로 쓴 뒤 부른다(MainActivity 채널 "refreshWidget"). */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, PlanWidget::class.java))
            for (id in ids) draw(context, manager, id)
        }

        private fun draw(context: Context, manager: AppWidgetManager, id: Int) {
            val s = read(context)
            val large = large(context, s)
            val views = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                RemoteViews(mapOf(SizeF(110f, 110f) to small(context, s), SizeF(220f, 110f) to large))
            } else {
                large
            }
            manager.updateAppWidget(id, views)
        }

        /** 요약 파일. 없거나 깨졌으면 null(빈 모양 — 앱을 열면 다시 쓴다). */
        private fun read(context: Context): JSONObject? {
            val f = File(context.filesDir, "widget/today.json")
            if (!f.exists()) {
                Log.i(TAG, "요약 파일 없음 — 앱을 열면 생긴다")
                return null
            }
            return try {
                JSONObject(f.readText())
            } catch (e: Exception) {
                Log.e(TAG, "요약 파일을 읽지 못함 — 빈 모양으로 그린다", e)
                null
            }
        }

        private fun dayKey(c: Calendar) = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(c.time)

        private val weekdays = arrayOf("일", "월", "화", "수", "목", "금", "토")

        /** "11월 26일 (목)" — 위젯의 날짜 글은 여기서만 만든다(앱 요약에는 `date`만 있다 — 앱 화면의 같은 모양 글은 plan_screen.dart가 따로 만든다, 표시라 대조 안 함). */
        private fun dayLabel(c: Calendar) =
            "${c.get(Calendar.MONTH) + 1}월 ${c.get(Calendar.DAY_OF_MONTH)}일 (${weekdays[c.get(Calendar.DAY_OF_WEEK) - 1]})"

        private fun parseDay(key: String): Calendar? = try {
            Calendar.getInstance().apply { time = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(key)!! }
        } catch (e: Exception) {
            Log.e(TAG, "요약 날짜를 읽지 못함 — '어제'로 적는다", e)
            null
        }

        private fun JSONObject.str(key: String): String? = if (isNull(key)) null else optString(key, "").ifEmpty { null }

        /** 요약이 오늘 것인가. 아니면 '새 하루예요' 모양. */
        private fun isToday(s: JSONObject) = s.optString("date") == dayKey(Calendar.getInstance())

        private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        private fun RemoteViews.text(id: Int, value: String?) {
            if (value == null) {
                setViewVisibility(id, View.GONE)
            } else {
                setViewVisibility(id, View.VISIBLE)
                setTextViewText(id, value)
            }
        }

        private fun RemoteViews.bar(row: Int, bar: Int, label: Int, part: JSONObject?) {
            if (part == null) {
                setViewVisibility(row, View.GONE)
                return
            }
            setViewVisibility(row, View.VISIBLE)
            setProgressBar(bar, 100, part.optInt("pct"), false)
            setTextViewText(label, part.optString("label"))
        }

        private fun large(context: Context, s: JSONObject?): RemoteViews {
            val v = RemoteViews(context.packageName, R.layout.widget_large)
            v.setOnClickPendingIntent(R.id.widget_root, openApp(context))
            val today = Calendar.getInstance()
            v.text(R.id.identity, s?.str("identity"))
            if (s != null && isToday(s) && !s.optBoolean("empty", true)) {
                v.setTextViewText(R.id.title, "오늘 · ${dayLabel(today)}")
                v.setViewVisibility(R.id.progress, View.VISIBLE)
                v.setViewVisibility(R.id.message, View.GONE)
                v.bar(R.id.do_row, R.id.do_bar, R.id.do_label, s.optJSONObject("do"))
                v.bar(R.id.dont_row, R.id.dont_bar, R.id.dont_label, s.optJSONObject("dont"))
                v.text(R.id.streak, s.str("streak"))
                v.text(R.id.missed, s.str("missed"))
                return v
            }
            v.setViewVisibility(R.id.progress, View.GONE)
            v.setViewVisibility(R.id.message, View.VISIBLE)
            if (s == null || isToday(s)) {
                // 파일이 없거나 오늘 계획이 없다(깨진 파일 포함).
                v.setTextViewText(R.id.title, "오늘 · ${dayLabel(today)}")
                v.setTextViewText(R.id.message_main, "눌러서 계획을 넣으세요")
                v.text(R.id.message_sub, null)
                return v
            }
            // 자정을 넘겨 앱을 아직 안 열었다 — 지난 요약은 그날 결과로 보인다.
            v.setTextViewText(R.id.title, dayLabel(today))
            v.setTextViewText(R.id.message_main, "새 하루예요. 눌러서 오늘 계획을 여세요")
            val yesterday = (today.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, -1) }
            val day = if (s.optString("date") == dayKey(yesterday)) "어제" else dayLabel(parseDay(s.optString("date")) ?: yesterday)
            val summary = if (s.optBoolean("empty", true)) null else s.str("summary")
            v.text(R.id.message_sub, summary?.let { "$day · $it" })
            return v
        }

        private fun small(context: Context, s: JSONObject?): RemoteViews {
            val v = RemoteViews(context.packageName, R.layout.widget_small)
            v.setOnClickPendingIntent(R.id.widget_root, openApp(context))
            v.setTextViewText(R.id.title, dayLabel(Calendar.getInstance()))
            val fresh = s != null && isToday(s) && !s.optBoolean("empty", true)
            if (!fresh) {
                v.text(R.id.do_name, null)
                v.setTextViewText(R.id.do_value, if (s != null && !isToday(s)) "새 하루" else "계획 넣기")
                v.text(R.id.dont_line, null)
                return v
            }
            val d = s!!.optJSONObject("do")
            val n = s.optJSONObject("dont")
            if (d == null) {
                // DON'T만 있는 날 — DON'T를 크게.
                v.text(R.id.do_name, "DON'T")
                v.setTextViewText(R.id.do_value, n?.optString("label") ?: "")
                v.text(R.id.dont_line, null)
                return v
            }
            v.text(R.id.do_name, "DO")
            v.setTextViewText(R.id.do_value, d.optString("label"))
            v.text(R.id.dont_line, n?.let { "DON'T ${it.optString("label")}" })
            return v
        }

        private fun midnightIntent(context: Context): PendingIntent {
            val i = Intent(context, PlanWidget::class.java).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
            val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, PlanWidget::class.java))
            i.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            return PendingIntent.getBroadcast(context, 1, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        /** 다음 자정 1분 뒤에 다시 그린다 — 정확하지 않은 알람(권한 없음). 다시 그릴 때마다 다음 자정을 잡는다. */
        private fun scheduleMidnight(context: Context) {
            val next = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_MONTH, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 1)
                set(Calendar.SECOND, 0)
            }
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
                .set(AlarmManager.RTC, next.timeInMillis, midnightIntent(context))
        }
    }
}
