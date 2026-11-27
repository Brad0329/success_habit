// F-102 홈 화면 위젯 요약 — 앱이 계산해 쓰는 글(REQUIREMENTS 앱_설정.md F-102 수용 기준). 위젯 모양은 사용자 실테스트.
import 'dart:convert';
import 'dart:io';

import 'package:chaerok/plans.dart';
import 'package:chaerok/widget_summary.dart';
import 'package:flutter_test/flutter_test.dart';

// 10월 5~9일 = 월~금.
DateTime d(int day) => DateTime(2026, 10, day);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chaerok_widget'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String idOf(PlanStore s, String title) => s.current.firstWhere((i) => i.title == title).id;

  test('DO 2/2(보류 뺌)·DON\'T 1/1(기본 지킴) → 막대 글·비율·지난 날 요약 줄', () async {
    final s = PlanStore(tmp, now: () => d(8));
    await s.saveItems([
      (null, '운동', PlanKind.doIt),
      (null, '독서', PlanKind.doIt),
      (null, '회사', PlanKind.doIt),
      (null, '야식', PlanKind.dont),
    ], d(8));
    await s.adoptDontDefault(d(8));
    await s.toggle(d(8), idOf(s, '운동'), d(8));
    await s.toggle(d(8), idOf(s, '독서'), d(8));
    await s.toggleHold(d(8), idOf(s, '회사'), d(8));
    final w = widgetSummary(s, d(8));
    expect(w['empty'], false);
    expect(w['date'], '2026-10-08');
    expect(w['do'], {'label': '2/2', 'pct': 100});
    expect(w['dont'], {'label': '1/1', 'pct': 100});
    expect(w['summary'], "DO 2/2 · DON'T 1/1");
  });

  test("DON'T가 없으면 dont null / 첫 목록 전 날 → empty / 깨진 파일 → empty(예외 없음)", () async {
    final s = PlanStore(tmp, now: () => d(8));
    await s.saveList([(null, '운동')], d(7));
    await s.toggle(d(8), idOf(s, '운동'), d(8));
    final w = widgetSummary(s, d(8));
    expect(w['dont'], isNull);
    expect(w['do'], {'label': '1/1', 'pct': 100});
    expect(w['summary'], 'DO 1/1');
    expect(widgetSummary(s, d(6))['empty'], true);

    File('${tmp.path}/plans.json').writeAsStringSync('{깨짐');
    final broken = PlanStore(tmp, now: () => d(8));
    expect(widgetSummary(broken, d(8))['empty'], true);
  });

  test('🔥 = 연속이 가장 긴 항목(같으면 목록 앞) / 모두 0이면 null', () async {
    final s = PlanStore(tmp, now: () => d(8));
    await s.saveList([(null, '독서'), (null, '운동'), (null, '물')], d(5));
    for (final k in [5, 6, 7]) {
      await s.toggle(d(k), idOf(s, '운동'), d(8));
    }
    await s.toggle(d(7), idOf(s, '독서'), d(8));
    expect(widgetSummary(s, d(8))['streak'], '🔥 운동 3일');

    final t = Directory('${tmp.path}/b')..createSync();
    final same = PlanStore(t, now: () => d(8));
    await same.saveList([(null, '독서'), (null, '운동')], d(7));
    await same.toggle(d(7), idOf(same, '독서'), d(8));
    await same.toggle(d(7), idOf(same, '운동'), d(8));
    expect(widgetSummary(same, d(8))['streak'], '🔥 독서 1일');

    final u = Directory('${tmp.path}/c')..createSync();
    final none = PlanStore(u, now: () => d(8));
    await none.saveList([(null, '운동')], d(7));
    expect(widgetSummary(none, d(8))['streak'], isNull);
  });

  test("직전 놓침 강조 2개 → '어제 놓침 2개' / 0개 → null", () async {
    final s = PlanStore(tmp, now: () => d(8));
    await s.saveList([(null, '운동'), (null, '독서'), (null, '물')], d(7));
    await s.toggle(d(7), idOf(s, '물'), d(8)); // 운동·독서는 7일에 놓침
    expect(widgetSummary(s, d(8))['missed'], '어제 놓침 2개');
    await s.toggle(d(8), idOf(s, '운동'), d(8));
    await s.toggle(d(8), idOf(s, '독서'), d(8));
    expect(widgetSummary(s, d(8))['missed'], isNull);
  });

  test('정체성 문장 2개 → 첫 문장 / 0개 → null', () async {
    final s = PlanStore(tmp, now: () => d(8));
    await s.saveList([(null, '운동')], d(8));
    expect(widgetSummary(s, d(8))['identity'], isNull);
    await s.saveIdentities(['나는 운동하는 사람이다', '나는 읽는 사람이다']);
    expect(widgetSummary(s, d(8))['identity'], '나는 운동하는 사람이다');
  });

  test('저장소가 알리면(체크·보류·휴일) 파일이 새 숫자로 / 같은 내용이면 쓰기 0 / 다시 그리기 호출', () async {
    final s = PlanStore(Directory('${tmp.path}/plans'), now: () => d(8));
    await s.saveList([(null, '운동'), (null, '독서')], d(8));
    final file = File('${tmp.path}/widget/today.json');
    var refreshed = 0;
    final ws = WidgetSync(s, file, now: () => d(8), refresh: () async => refreshed++);
    ws.start(); // 앱과 같은 연결(main.dart) — 저장소 알림으로만 다시 쓴다
    await ws.sync();
    expect(jsonDecode(file.readAsStringSync())['do'], {'label': '0/2', 'pct': 0});
    expect((ws.writes, refreshed), (1, 1));

    // 체크·보류·휴일 각각 — 손으로 sync()를 부르지 않는다(Phase 007 A1: 알림이 빠지면 여기서 잡힌다).
    await s.toggle(d(8), idOf(s, '운동'), d(8));
    await ws.idle;
    expect(jsonDecode(file.readAsStringSync())['do'], {'label': '1/2', 'pct': 50});
    expect((ws.writes, refreshed), (2, 2));

    await s.toggleHold(d(8), idOf(s, '독서'), d(8));
    await ws.idle;
    expect(jsonDecode(file.readAsStringSync())['do'], {'label': '1/1', 'pct': 100});
    expect((ws.writes, refreshed), (3, 3));

    await s.toggleHoliday(d(8)); // 목요일 → 쉬는 날: 주말 계획이 비어 평일 계획 전부 기본 보류
    await ws.idle;
    expect(jsonDecode(file.readAsStringSync())['do'], isNull);
    expect((ws.writes, refreshed), (4, 4));

    await ws.sync(); // 같은 내용이면 쓰기 0
    expect((ws.writes, refreshed), (4, 4));
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });
}
