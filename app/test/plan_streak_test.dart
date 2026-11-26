// F-042 두 번 연속 빠지지 않기 — 연속(🔥)·직전 놓침 횟수·두 번 연속 놓친 날(REQUIREMENTS F-042 수용 기준).
// 실제 PlanStore 파일로 만든 기록을 센다. 화면 모양은 사용자 실테스트.
import 'dart:io';

import 'package:chaerok/plan_streak.dart';
import 'package:chaerok/plans.dart';
import 'package:flutter_test/flutter_test.dart';

// 10월 5~9일 = 월~금, 10·11일 = 토·일, 12일 = 월, 17일 = 토.
DateTime d(int day) => DateTime(2026, 10, day);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chaerok_plan_streak'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String idOf(PlanStore s, String title) => s.current.firstWhere((i) => i.title == title).id;

  /// [from]부터 [title] 하나, [checked] 날에 체크 — 오늘 [today].
  Future<(PlanStore, String)> one(String title, int from, List<int> checked, int today) async {
    final s = PlanStore(tmp);
    await s.saveList([(null, title)], d(from));
    final id = idOf(s, title);
    for (final k in checked) {
      await s.toggle(d(k), id, d(today));
    }
    return (s, id);
  }

  PlanStreak? at(PlanStore s, String id, int today) => planStreaks(s, d(today)).today[id];

  test('3일 이어 하고 오늘 아직 → 연속 3, 강조 없음 / 오늘 하면 4', () async {
    final (s, id) = await one('운동', 5, [5, 6, 7], 8);
    expect(at(s, id, 8), (streak: 3, misses: 0));
    await s.toggle(d(8), id, d(8));
    expect(at(s, id, 8), (streak: 4, misses: 0));
  });

  test('직전 날 놓침 + 오늘 아직 → 어제 놓침(1), 연속 0 / 오늘 하면 강조 없음·연속 1', () async {
    final (s, id) = await one('운동', 5, [5, 6], 8);
    expect(at(s, id, 8), (streak: 0, misses: 1));
    await s.toggle(d(8), id, d(8));
    expect(at(s, id, 8), (streak: 1, misses: 0));
  });

  test('이틀 놓침 + 오늘 아직 → 2회 연속 놓침', () async {
    final (s, id) = await one('운동', 5, [5], 8);
    expect(at(s, id, 8), (streak: 0, misses: 2));
  });

  test('그 전날만 놓쳤으면 강조 없음(직전 해야 한 날은 함)', () async {
    final (s, id) = await one('운동', 5, [5, 7], 8);
    expect(at(s, id, 8), (streak: 1, misses: 0));
  });

  test('보류한 날은 건너뛴다(끊지도 늘리지도 않음)', () async {
    final (s, id) = await one('운동', 5, [5, 7], 8);
    await s.toggleHold(d(6), id, d(8));
    expect(at(s, id, 8), (streak: 2, misses: 0));
  });

  test('평일 계획: 주말 기본 보류는 건너뛰고, 직전 해야 한 날은 금요일', () async {
    final (s, id) = await one('회사', 9, [9], 12);
    expect(at(s, id, 12), (streak: 1, misses: 0));
    await s.toggle(d(9), id, d(12)); // 금요일 체크를 푼다
    expect(at(s, id, 12), (streak: 0, misses: 1));
  });

  test('그날만 푼 토요일은 해야 한 날 — 안 했으면 연속이 끊긴다', () async {
    final (s, id) = await one('운동', 9, [9], 12);
    await s.toggleHold(d(10), id, d(12)); // 토요일 그날만 풀기
    expect(at(s, id, 12), (streak: 0, misses: 1));
    await s.toggle(d(12), id, d(12));
    expect(at(s, id, 12), (streak: 1, misses: 0));
  });

  test('주말 전용 계획: 평일은 건너뛰고 직전 해야 한 날은 지난 일요일', () async {
    final s = PlanStore(tmp);
    await s.saveList([(null, '운동')], d(10));
    expect(await s.saveWeekend([(null, '등산', PlanKind.doIt)], d(10)), isNull);
    final hike = idOf(s, '등산');
    await s.toggle(d(10), hike, d(17));
    expect(at(s, hike, 17), (streak: 0, misses: 1)); // 10 함 · 11 놓침 · 12~16 평일 건너뜀 · 17 아직
  });

  test('첫 목록 날 전에서 멈춘다(오류 없음)', () async {
    final (s, id) = await one('운동', 7, [7], 8);
    expect(at(s, id, 8), (streak: 1, misses: 0));
  });

  group("DON'T", () {
    Future<(PlanStore, String)> dont({int now = 7}) async {
      final s = PlanStore(tmp, now: () => DateTime(2026, 10, now, 21));
      await s.saveItems([(null, '야식', PlanKind.dont)], d(5));
      await s.adoptDontDefault(d(5));
      return (s, idOf(s, '야식'));
    }

    test('기본 지킴 3일 → 오늘 포함 연속 3 / 오늘 어기면 연속 0·강조 없음(첫 놓침)', () async {
      final (s, id) = await dont();
      expect(at(s, id, 7), (streak: 3, misses: 0));
      await s.toggle(d(7), id, d(7));
      expect(at(s, id, 7), (streak: 0, misses: 0));
    });

    test('어제 어김 + 오늘 지킴 → 어제 놓침 / 오늘도 어기면 2회 연속 놓침·오늘 점', () async {
      final (s, id) = await dont();
      await s.toggle(d(6), id, d(7));
      expect(at(s, id, 7), (streak: 1, misses: 1));
      await s.toggle(d(7), id, d(7));
      expect(at(s, id, 7), (streak: 0, misses: 2));
      expect(planStreaks(s, d(7)).doubleMissDays, {'2026-10-07'});
    });

    test('옛 규칙 날의 체크 안 함은 놓침(연속을 끊는다)', () async {
      final s = PlanStore(tmp, now: () => DateTime(2026, 10, 7, 21));
      await s.saveItems([(null, '야식', PlanKind.dont)], d(5));
      final id = idOf(s, '야식');
      await s.toggle(d(5), id, d(7));
      await s.toggle(d(7), id, d(7));
      expect(at(s, id, 7), (streak: 1, misses: 0));
    });
  });

  test('상한 없음: 400일 이어 하면 400', () async {
    final start = DateTime(2025, 9, 3);
    final today = DateTime(start.year, start.month, start.day + 399);
    final s = PlanStore(tmp);
    await s.saveItems([(null, '운동', PlanKind.doIt)], start);
    await s.saveWeekend([(idOf(s, '운동'), '운동', PlanKind.doIt)], start); // 주말에도 하는 계획
    final id = idOf(s, '운동');
    for (var k = 0; k < 400; k++) {
      await s.toggle(DateTime(start.year, start.month, start.day + k), id, today);
    }
    expect(planStreaks(s, today).today[id], (streak: 400, misses: 0));
    expect(planBestStreaks(s, start, today, today)[id], 400); // F-043
  });

  group('F-043 기간 안 최장 연속', () {
    test('끊긴 뒤 다시 이은 것보다 긴 쪽 / 기간 시작 전은 안 센다', () async {
      // 5·6·7 함, 8 놓침, 9 함, 10·11 주말 기본 보류, 12 함 — 오늘 14
      final (s, id) = await one('운동', 5, [5, 6, 7, 9, 12], 14);
      expect(planBestStreaks(s, d(5), d(12), d(14))[id], 3);
      expect(planBestStreaks(s, d(7), d(12), d(14))[id], 2);
    });

    test('사이의 보류는 건너뛰고, 오늘 아직 안 한 것은 끊지 않는다', () async {
      final (s, id) = await one('운동', 5, [5, 7], 8);
      await s.toggleHold(d(6), id, d(8));
      expect(planBestStreaks(s, d(5), d(8), d(8))[id], 2);
    });
  });

  test('달력 점: 두 번째로 놓친 날에만 — 오늘 아직인 DO와 미래엔 없다', () async {
    final (s, _) = await one('운동', 5, [5], 8);
    expect(planStreaks(s, d(8)).doubleMissDays, {'2026-10-07'}); // 6·7 놓침, 8은 아직
  });

  test('달력 점: 사이의 보류는 건너뛴다', () async {
    final (s, id) = await one('독서', 5, [5], 9);
    await s.toggleHold(d(7), id, d(9));
    expect(planStreaks(s, d(9)).doubleMissDays, {'2026-10-08'}); // 6 놓침 · 7 보류 · 8 놓침 · 9 아직
  });

  test('깨진 파일 → 연속·강조·점 0건', () async {
    File('${tmp.path}/plans.json').writeAsStringSync('{깨짐');
    final st = planStreaks(PlanStore(tmp), d(8));
    expect((st.today.length, st.doubleMissDays.length), (0, 0));
  });
}
