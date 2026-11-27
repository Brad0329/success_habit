/// F-102 홈 화면 위젯 요약 — 앱이 계산해 `widget/today.json`에 **보일 글 그대로** 쓰고, 위젯(Kotlin `PlanWidget`)은
/// 읽어 그리기만 한다(판단은 날짜뿐 — 오늘인가·어제인가, 날짜 글). 계획 규칙(보류·주말·DON'T 기본 지킴·연속)을 위젯 쪽에 다시 구현하지 않으려고.
/// 형식의 결정은 docs/SCHEMA.md 2026-11-26. 산출물이라 지워져도 다음 실행에 다시 생긴다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'atomic_file.dart';
import 'log.dart';
import 'plan_streak.dart';
import 'plans.dart';

const widgetSummaryVersion = 1;

/// 그날([today]) 위젯 요약. 계획이 없거나 깨진 파일이면 `empty`.
Map<String, Object?> widgetSummary(PlanStore s, DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  final base = <String, Object?>{
    'v': widgetSummaryVersion,
    'date': dayKey(day), // 날짜 글("11월 26일 (목)")은 위젯이 이 값으로 만든다
    'identity': s.identities.isEmpty ? null : s.identities.first,
  };
  final items = s.broken ? null : s.itemsOn(day);
  if (items == null || items.isEmpty) return {...base, 'empty': true};
  final doSum = _part(s.summary(day, kind: PlanKind.doIt));
  final dontSum = _part(s.summary(day, kind: PlanKind.dont));
  final streaks = planStreaks(s, day).today;
  String? streak;
  var best = 0;
  var missed = 0;
  for (final i in items) {
    final st = streaks[i.id];
    if (st == null) continue;
    if (st.streak > best) {
      best = st.streak;
      streak = '🔥 ${i.title} ${st.streak}일';
    }
    if (st.misses > 0) missed++;
  }
  return {
    ...base,
    'empty': false,
    'do': doSum,
    'dont': dontSum,
    'streak': streak,
    'missed': missed == 0 ? null : '어제 놓침 $missed개',
    'summary': [
      if (doSum != null) 'DO ${doSum['label']}',
      if (dontSum != null) "DON'T ${dontSum['label']}",
    ].join(' · '),
  };
}

/// (한 수, 전체) → {label, pct}. 그 종류가 그날 하나도 없으면(보류 포함 0개) null.
Map<String, Object?>? _part((int, int)? sum) {
  if (sum == null) return null;
  final (done, total) = sum;
  if (total == 0) return null;
  return {'label': '$done/$total', 'pct': (done * 100 / total).round()};
}

/// 저장소가 알릴 때·앱이 다시 앞으로 올 때 요약을 다시 쓰고 위젯을 다시 그리게 한다. 같은 내용이면 쓰기 0.
class WidgetSync with WidgetsBindingObserver {
  WidgetSync(this.store, this.file, {this.now = DateTime.now, this.refresh = _refreshWidget});

  final PlanStore store;
  final File file;
  final DateTime Function() now;

  /// 위젯 다시 그리기(안드로이드 채널). 테스트는 가짜를 넘긴다.
  final Future<void> Function() refresh;

  String? _last;
  var writes = 0; // 테스트용 — 실제로 쓴 횟수

  void start() {
    store.addListener(_onChange);
    WidgetsBinding.instance.addObserver(this);
  }

  void _onChange() => sync();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sync(); // 자정을 넘겨 다시 열었을 때 새 날로
  }

  Future<void> _queue = Future.value();

  /// 요약을 쓰고 위젯을 다시 그린다 — 한 번에 하나씩(같은 임시 파일을 두 번 동시에 바꿔치지 않게).
  Future<void> sync() => _queue = _queue.then((_) => _sync());

  /// 줄 선 쓰기가 다 끝날 때 — 테스트가 알림으로 건 쓰기를 기다린다(손으로 [sync]를 불러 알림 누락을 가리지 않게).
  Future<void> get idle => _queue;

  /// 실패는 로그만 남긴다 — 위젯이 못 바뀌어도 계획 화면은 계속 써야 한다.
  Future<void> _sync() async {
    try {
      final text = jsonEncode(widgetSummary(store, now()));
      if (text == _last && file.existsSync()) return;
      await file.parent.create(recursive: true);
      await writeAtomic(file, text);
      _last = text;
      writes++;
      await refresh();
    } on Object catch (e, st) {
      logError('위젯 요약 쓰기 실패', e, st);
    }
  }
}

Future<void> _refreshWidget() async {
  try {
    await const MethodChannel('chaerok/app').invokeMethod<void>('refreshWidget');
  } on MissingPluginException catch (e, st) {
    // 채널이 없는 곳(PC 테스트·옛 껍데기) — 위젯이 다음 주기에 파일을 읽는다.
    logError('위젯 다시 그리기 채널 없음', e, st);
  }
}
