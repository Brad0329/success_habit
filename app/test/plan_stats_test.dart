// F-037 계획 통계 — 기간 집계(성공·해야 한 날·보류)·이름 바꾸기·지운 항목·기간 자르기·쉬는 날·빠른 선택(REQUIREMENTS F-037).
// 실제 PlanStore 파일로 만든 기록을 센다. 화면 모양은 사용자 실테스트.
import 'dart:io';

import 'package:chaerok/plan_stats.dart';
import 'package:chaerok/plan_stats_screen.dart';
import 'package:chaerok/plan_streak.dart';
import 'package:chaerok/plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 10월 5~9일 = 월~금, 10·11일 = 토·일.
DateTime d(int day) => DateTime(2026, 10, day);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chaerok_plan_stats'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String idOf(PlanStore s, String title) => s.current.firstWhere((i) => i.title == title).id;
  (String, int, int, int) row(PlanStat s) => (s.item.title, s.done, s.due, s.held);

  test('집계: 성공·해야 한 날·보류한 날', () async {
    final s = PlanStore(tmp);
    await s.saveList([(null, '운동'), (null, '독서')], d(5));
    final run = idOf(s, '운동'), read = idOf(s, '독서');
    await s.toggle(d(5), run, d(7));
    await s.toggle(d(6), run, d(7));
    await s.toggleHold(d(6), read, d(7));
    final st = planStats(PlanStore(tmp), d(5), d(7), d(7));
    expect([for (final x in st.current) row(x)], [('운동', 2, 3, 0), ('독서', 0, 2, 1)]);
    expect(st.removed, isEmpty);
    expect(st.days, 3);
  });

  test('이름을 바꿔도 한 줄(지금 이름)로 기간 전체를 센다', () async {
    final s = PlanStore(tmp);
    await s.saveList([(null, '운동')], d(5));
    final id = idOf(s, '운동');
    await s.toggle(d(5), id, d(7));
    await s.saveList([(id, '운동 30분')], d(6));
    await s.toggle(d(6), id, d(7));
    final st = planStats(s, d(5), d(7), d(7));
    expect([for (final x in st.current) row(x)], [('운동 30분', 2, 3, 0)]);
    expect(st.removed, isEmpty);
  });

  test('지운 항목은 지운 항목 묶음에(있던 날만 셈), 지금 항목 묶음에는 없다', () async {
    final s = PlanStore(tmp);
    await s.saveList([(null, '운동'), (null, '독서')], d(5));
    await s.toggle(d(5), idOf(s, '독서'), d(7));
    await s.saveList([(idOf(s, '운동'), '운동')], d(6));
    final st = planStats(s, d(5), d(7), d(7));
    expect([for (final x in st.current) x.item.title], ['운동']);
    expect([for (final x in st.removed) row(x)], [('독서', 1, 1, 0)]);
  });

  test('미래는 오늘까지로 자르고, 첫 목록 전 날은 건너뛰고, 계획 없는 기간은 빈 결과', () async {
    final s = PlanStore(tmp);
    await s.saveList([(null, '운동')], d(5));
    final future = planStats(s, d(5), d(9), d(7));
    expect((future.to, future.days, future.current.single.due), (d(7), 3, 3));
    expect(planStats(s, d(1), d(7), d(7)).current.single.due, 3);
    expect(planStats(s, d(1), d(4), d(7)).isEmpty, isTrue);
    final notYet = planStats(s, d(8), d(9), d(7));
    expect((notYet.days, notYet.isEmpty), (0, true));
  });

  test('쉬는 날 기본 보류인 평일 계획은 안 세고, 그날 푼 날은 해야 한 날에 든다', () async {
    final s = PlanStore(tmp);
    await s.saveList([(null, '운동')], d(9)); // 금 — 새 저장은 평일·주말이 나뉜 칸(주말 계획 빈 목록)
    final id = idOf(s, '운동');
    expect(row(planStats(s, d(9), d(11), d(11)).current.single), ('운동', 0, 1, 0));
    await s.toggleHold(d(11), id, d(11)); // 일요일 그날만 풀기
    expect(row(planStats(s, d(9), d(11), d(11)).current.single), ('운동', 0, 2, 0));
  });

  test("DON'T는 DON'T 합계로, DO와 섞이지 않는다", () async {
    final s = PlanStore(tmp);
    await s.saveItems([(null, '운동', PlanKind.doIt), (null, '야식', PlanKind.dont)], d(5));
    await s.toggle(d(5), idOf(s, '야식'), d(5));
    final st = planStats(s, d(5), d(5), d(5));
    expect((st.total(PlanKind.doIt), st.total(PlanKind.dont)), ((0, 1), (1, 1)));
  });

  test("DON'T 기본 지킴 날: 3일 중 1일 어김 → (2, 3)", () async {
    final s = PlanStore(tmp, now: () => DateTime(2026, 10, 7, 21));
    await s.saveItems([(null, '야식', PlanKind.dont)], d(5));
    await s.adoptDontDefault(d(5));
    await s.toggle(d(6), s.current.single.id, d(7));
    expect(row(planStats(s, d(5), d(7), d(7)).current.single), ('야식', 2, 3, 0));
  });

  group('F-043 달별 비율 추이', () {
    // 2026-09: 1일 = 화, 주말 8일 → 평일 22일. 10-01~14: 평일 10일.
    final today = DateTime(2026, 10, 14);
    DateTime sep(int day) => DateTime(2026, 9, day);

    /// 9-01부터 [운동, 독서] — 9월은 1·2일 빼고 평일 전부(20/22), 10월은 13·14일 빼고 전부(8/10) '운동' 체크.
    /// [dropRead]면 10-01에 '독서'를 지운다.
    Future<(PlanStore, String)> seed({bool dropRead = false}) async {
      final s = PlanStore(tmp);
      await s.saveList([(null, '운동'), (null, '독서')], sep(1));
      final id = idOf(s, '운동');
      for (var k = 0; k < 44; k++) {
        final day = DateTime(2026, 9, 3 + k); // 9-03 ~ 10-16
        if (isWeekend(day) || !day.isBefore(DateTime(2026, 10, 13))) continue;
        await s.toggle(day, id, today);
      }
      if (dropRead) await s.saveList([(id, '운동')], d(1));
      return (s, id);
    }

    test('첫 목록 달부터 이번 달까지 — 9월 91%·10월 80%, 지난달 대비 −11%p, 절단 없음', () async {
      final (s, id) = await seed();
      final tr = planTrend(s, today);
      expect(tr.months, [DateTime(2026, 9), DateTime(2026, 10)]);
      expect(tr.totalMonths, 2);
      expect([for (final r in tr.rates[id]!) (r! * 100).round()], [91, 80]);
      expect(tr.delta(id), -11);
    });

    test('첫 목록이 3달보다 앞이면 최근 3달 + 전체 달 수', () async {
      final s = PlanStore(tmp);
      await s.saveList([(null, '운동')], DateTime(2026, 6, 15));
      final tr = planTrend(s, today);
      expect(tr.months, [DateTime(2026, 8), DateTime(2026, 9), DateTime(2026, 10)]);
      expect(tr.totalMonths, 5);
    });

    testWidgets('화면: 3달보다 오래된 기록이면 "전체 5달 중 최근 3달"', (t) async {
      final s = PlanStore(tmp);
      await t.runAsync(() => s.saveList([(null, '운동')], DateTime(2026, 6, 15)));
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: PlanStatsScreen(store: s, now: () => DateTime(2026, 10, 14, 21))));
      expect(t.widget<Text>(find.byKey(const ValueKey('trend-cut'))).data, '전체 5달 중 최근 3달');
    });

    test('해야 한 날 0인 달은 null, 그러면 지난달 대비도 없음', () async {
      final s = PlanStore(tmp);
      await s.saveList([(null, '운동')], sep(28));
      final id = idOf(s, '운동');
      for (var k = 1; k <= 14; k++) {
        if (!isWeekend(d(k))) await s.toggleHold(d(k), id, today);
      }
      final tr = planTrend(s, today);
      expect(tr.rates[id]!.last, isNull);
      expect(tr.delta(id), isNull);
    });

    test('깨진 파일 → 달 0개, 최장 연속 0건', () {
      File('${tmp.path}/plans.json').writeAsStringSync('{깨짐');
      final s = PlanStore(tmp);
      expect(planTrend(s, today).months, isEmpty);
      expect(planBestStreaks(s, sep(1), today, today), isEmpty);
    });

    testWidgets('화면: 연속 · 달별 추이 묶음 — 기간을 바꾸면 최장 연속만 바뀌고, 지운 항목은 없고, 풍선에 규칙', (t) async {
      final (s, id) = (await t.runAsync(() => seed(dropRead: true)))!;
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: PlanStatsScreen(store: s, now: () => DateTime(2026, 10, 14, 21))));
      Text txt(String key) => t.widget<Text>(find.byKey(ValueKey(key)));
      expect(find.text('연속 · 달별 추이'), findsOneWidget);
      expect(txt('trend-$id-0').data, '9월 91%');
      expect(txt('trend-$id-1').data, '10월 80%');
      expect(txt('delta-$id').data, '▼ 11%p');
      expect(find.byKey(const ValueKey('trend-cut')), findsNothing);
      expect(txt('best-$id').data, '최장 🔥 8일'); // 이번 달: 10-01·02·05~09·12 이어짐, 13 놓침
      await t.tap(find.text('지난 달'));
      await t.pump();
      expect(txt('best-$id').data, '최장 🔥 20일'); // 9-03~30 평일 전부
      // 10-01에 지운 '독서'는 9월 기간의 '지운 항목' 막대에만 — 이 묶음의 줄은 '운동' 하나
      expect(find.text('지운 항목'), findsOneWidget);
      expect(
          find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('best-')),
          findsOneWidget);
      expect(txt('trend-$id-0').data, '9월 91%');
      final help = t.widget<Tooltip>(find.byKey(const ValueKey('plan-stats-help')));
      expect(help.message, allOf(contains('최장 연속'), contains('달별 추이')));
    });
  });

  test('기간 빠른 선택', () {
    final today = DateTime(2026, 11, 24); // 화요일
    expect(periodRange(PlanPeriod.week, today), (DateTime(2026, 11, 22), today));
    expect(periodRange(PlanPeriod.month, today), (DateTime(2026, 11, 1), today));
    expect(periodRange(PlanPeriod.lastMonth, today), (DateTime(2026, 10, 1), DateTime(2026, 10, 31)));
    expect(periodRange(PlanPeriod.days30, today), (DateTime(2026, 10, 26), today));
    expect(periodRange(PlanPeriod.lastMonth, DateTime(2027, 1, 5)), (DateTime(2026, 12, 1), DateTime(2026, 12, 31)));
    expect(periodRange(PlanPeriod.week, DateTime(2026, 11, 22)).$1, DateTime(2026, 11, 22)); // 일요일 당일
  });
}
