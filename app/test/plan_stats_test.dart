// F-037 계획 통계 — 기간 집계(성공·해야 한 날·보류)·이름 바꾸기·지운 항목·기간 자르기·쉬는 날·빠른 선택(REQUIREMENTS F-037).
// 실제 PlanStore 파일로 만든 기록을 센다. 화면 모양은 사용자 실테스트.
import 'dart:io';

import 'package:chaerok/plan_stats.dart';
import 'package:chaerok/plans.dart';
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
