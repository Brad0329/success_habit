// Phase 007 B6·B7: 한 규칙이 여러 곳에 따로 구현되면 한쪽만 바뀌어 어긋난다 — 한 함수로 모으고, 다시 갈라지면 소스 훑기가 잡는다.
//  - B6 % 반올림: 통계 화면 합계·항목, 달별 추이·▲▼(delta), 위젯 막대가 모두 [ratePct] 하나로 % 를 만든다.
//    (rate*100).round()와 (done*100/due).round()는 같은 수에서 갈린다(29/200 → 14 / 15).
//  - B7 '해야 한 날': 연속(plan_streak)·통계(plan_stats)가 모두 [PlanStore.dueOn] 하나로 판정한다.
import 'dart:io';

import 'package:chaerok/plan_stats.dart';
import 'package:chaerok/plans.dart';
import 'package:flutter_test/flutter_test.dart';

// 10월 5~9일 = 월~금, 10·11일 = 토·일.
DateTime d(int day) => DateTime(2026, 10, day);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chaerok_one_rule'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('ratePct: 부동소수 오차에도 반올림 — 29/200 = 15, 1/3 = 33, 2/3 = 67, 0·1', () {
    expect(ratePct(29 / 200), 15); // 0.145 * 100 = 14.4999…
    expect(ratePct(1 / 3), 33);
    expect(ratePct(2 / 3), 67);
    expect(ratePct(1 / 8), 13); // 12.5 — 반올림은 올림
    expect(ratePct(0), 0);
    expect(ratePct(1), 100);
  });

  test('lib에서 %를 만드는 반올림은 ratePct 한 곳뿐', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var k = 0; k < lines.length; k++) {
        if (lines[k].contains('100') && lines[k].contains('.round()')) hits.add('${f.uri.pathSegments.last}:${k + 1}');
      }
    }
    expect(hits, hasLength(1), reason: '$hits — % 는 ratePct로');
    expect(hits.single, startsWith('plan_stats.dart:'));
  });

  test('dueOn: 평일 = 목록 전부 / 보류한 날 빠짐 / 쉬는 날 기본 보류 빠짐·그날 푼 것은 듦 / 계획 없는 날 빈 집합', () async {
    final s = PlanStore(tmp, now: () => d(10));
    await s.saveItems([(null, '운동', PlanKind.doIt), (null, '야식', PlanKind.dont)], d(5));
    final run = s.current.firstWhere((i) => i.title == '운동').id;
    final night = s.current.firstWhere((i) => i.title == '야식').id;
    expect(s.dueOn(d(5)), {run, night});
    await s.toggleHold(d(6), run, d(10));
    expect(s.dueOn(d(6)), {night});
    expect(s.dueOn(d(10)), {night}); // 토요일 — 평일 DO는 기본 보류, 평일 DON'T는 주말에도
    await s.toggleHold(d(10), run, d(10)); // 그날만 풀기
    expect(s.dueOn(d(10)), {run, night});
    expect(s.dueOn(d(4)), isEmpty);
  });

  test('연속·통계는 해야 한 날을 dueOn으로만 판정한다(heldOn을 직접 안 부름)', () {
    for (final name in ['plan_streak.dart', 'plan_stats.dart']) {
      final src = File('lib/$name').readAsStringSync();
      expect(src, contains('dueOn('), reason: name);
      expect(src, isNot(contains('heldOn(')), reason: '$name — 해야 한 날 판정이 두 벌로 갈라진다');
    }
  });
}
