// F-016 계획관리 — 목록 이력·체크·집계·검증(REQUIREMENTS F-016 수용 기준). 모양은 사용자 실테스트.
import 'dart:io';

import 'package:chaerok/log.dart';
import 'package:chaerok/plan_settings.dart';
import 'package:chaerok/plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 10월 5~9·12~16·20일 = 평일 — 아래 F-016~F-026 테스트는 평일 규칙을 본다. 주말·휴일(F-031)은 '평일·주말' 묶음이 11월 날짜로 따로 건다.
DateTime d(int day) => DateTime(2026, 10, day);

/// 저장 호출만 받아 적는 가짜 — 위젯 테스트의 가짜 시계 안에서는 파일 쓰기가 끝나지 않는다('이름 바꾸기 창' 주석).
class _Capture extends PlanStore {
  _Capture(super.dir);
  final saved = <List<(String?, String, PlanKind)>>[];
  final savedWeekend = <List<PlanRow>>[];

  @override
  Future<String?> saveItems(List<(String?, String, PlanKind)> rows, DateTime today) async {
    saved.add(rows);
    return null;
  }

  @override
  Future<String?> saveWeekend(List<PlanRow> rows, DateTime today) async {
    savedWeekend.add(rows);
    return null;
  }
}

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chaerok_plans');
    file = File('${tmp.path}/plans.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  PlanStore open() => PlanStore(tmp);
  List<String> titles(List<PlanItem>? xs) => [for (final x in xs!) x.title];
  String idOf(PlanStore s, DateTime day, String title) => s.itemsOn(day)!.firstWhere((i) => i.title == title).id;

  test('첫 저장: 이력 1개, 그날 목록 2개, 전날은 계획 없음', () async {
    final s = open();
    expect(await s.saveList([(null, '운동'), (null, '독서')], d(8)), isNull);
    expect(titles(s.itemsOn(d(8))), ['운동', '독서']);
    expect(s.itemsOn(d(7)), isNull);
    expect(s.summary(d(7)), isNull);
    expect(file.readAsStringSync(), contains('"from":"2026-10-08"'));
    expect(RegExp('"from"').allMatches(file.readAsStringSync()).length, 1);
  });

  test('같은 날 다시 바꾸면 이력이 늘지 않는다 / 그대로면 파일 쓰기 0', () async {
    final s = open();
    await s.saveList([(null, '운동')], d(8));
    final id = s.current.single.id;
    await s.saveList([(id, '운동'), (null, '독서')], d(8));
    expect(RegExp('"from"').allMatches(file.readAsStringSync()).length, 1);
    expect(titles(open().itemsOn(d(8))), ['운동', '독서']);
    file.deleteSync();
    expect(await s.saveList([for (final i in s.current) (i.id, i.title)], d(8)), isNull);
    expect(file.existsSync(), isFalse);
  });

  test('지난 날 그대로: 목록을 바꿔도 지난 날의 목록·체크는 남는다', () async {
    final s = open();
    await s.saveList([(null, '운동'), (null, '독서')], d(5));
    expect(await s.toggle(d(6), idOf(s, d(6), '독서'), d(6)), isTrue);
    final run = idOf(s, d(8), '운동');
    await s.saveList([(run, '운동'), (null, '일기')], d(8));
    final r = open();
    expect(titles(r.itemsOn(d(6))), ['운동', '독서']);
    expect(r.summary(d(6)), (1, 2));
    expect(titles(r.itemsOn(d(8))), ['운동', '일기']);
    expect(titles(r.itemsOn(d(20))), ['운동', '일기']);
  });

  test('순서 바꾸기: 다시 열어도 새 순서, 오늘 체크 유지, 지난 날은 옛 순서', () async {
    final s = open();
    await s.saveList([(null, '운동'), (null, '독서'), (null, '일기')], d(5));
    final today = s.current;
    expect(await s.toggle(d(8), today[2].id, d(8)), isTrue);
    await s.saveList([for (final i in [today[2], today[0], today[1]]) (i.id, i.title)], d(8));
    final r = open();
    expect(titles(r.itemsOn(d(8))), ['일기', '운동', '독서']);
    expect(r.doneOn(d(8)), {today[2].id});
    expect(titles(r.itemsOn(d(6))), ['운동', '독서', '일기']);
  });

  test('이름 바꾸기: 오늘 체크 유지, 지난 날은 옛 이름', () async {
    final s = open();
    await s.saveList([(null, '운동')], d(7));
    final id = s.current.single.id;
    await s.toggle(d(8), id, d(8));
    await s.saveList([(id, '운동 30분')], d(8));
    expect(s.doneOn(d(8)), {id});
    expect(titles(s.itemsOn(d(8))), ['운동 30분']);
    expect(titles(s.itemsOn(d(7))), ['운동']);
  });

  test('오늘 지운 항목의 오늘 체크는 집계에서 빠진다', () async {
    final s = open();
    await s.saveList([(null, '운동'), (null, '독서')], d(8));
    final run = idOf(s, d(8), '운동');
    await s.toggle(d(8), idOf(s, d(8), '독서'), d(8));
    await s.saveList([(run, '운동')], d(8));
    expect(s.summary(d(8)), (0, 1));
    expect(s.doneOn(d(8)), isEmpty);
  });

  test('체크·해제: 다시 읽어도 체크, 다시 누르면 해제', () async {
    final s = open();
    await s.saveList([(null, '운동')], d(8));
    final id = s.current.single.id;
    expect(await s.toggle(d(8), id, d(8)), isTrue);
    expect(open().doneOn(d(8)), {id});
    expect(await s.toggle(d(8), id, d(8)), isTrue);
    expect(open().doneOn(d(8)), isEmpty);
  });

  test('미래·계획 없는 날·목록에 없는 id 체크는 거부, 쓰기 0', () async {
    final s = open();
    await s.saveList([(null, '운동')], d(8));
    final id = s.current.single.id;
    file.deleteSync();
    expect(await s.toggle(d(9), id, d(8)), isFalse);
    expect(await s.toggle(d(7), id, d(8)), isFalse);
    expect(await s.toggle(d(8), 'p999', d(8)), isFalse);
    expect(file.existsSync(), isFalse);
    expect(await s.toggle(d(8), id, d(8)), isTrue); // 오늘은 된다(위 거부가 늘 거부라서 통과한 게 아님)
  });

  test('달력 집계: 날짜별 (한 수, 전체), 계획 없는 날 null', () async {
    final s = open();
    await s.saveList([(null, '운동'), (null, '독서')], d(5));
    await s.toggle(d(6), idOf(s, d(6), '운동'), d(8));
    expect(s.summary(d(6)), (1, 2));
    expect(s.summary(d(7)), (0, 2));
    expect(s.summary(d(4)), isNull);
  });

  test('검증: 빈 이름·31개·41자·같은 이름은 거부, 파일은 그대로', () async {
    final s = open();
    await s.saveList([(null, '운동')], d(8));
    final before = file.readAsStringSync();
    expect(await s.saveList([(null, '   ')], d(8)), isNotNull);
    expect(await s.saveList([for (var k = 0; k < 31; k++) (null, '계획$k')], d(8)), contains('30'));
    expect(await s.saveList([(null, '가' * 41)], d(8)), contains('40'));
    expect(await s.saveList([(null, '운 동'), (null, '운동')], d(8)), isNotNull);
    expect(file.readAsStringSync(), before);
    expect(await s.saveList([for (var k = 0; k < 30; k++) (null, '계획$k')], d(8)), isNull);
    expect(await s.saveList([(null, '가' * 40)], d(8)), isNull);
  });

  // 2026-11-08 실기기: 이름 바꾸기 창에서 '취소' → 빨간 화면(창이 닫히는 중에 이미 버린 입력 칸 컨트롤러를 씀).
  // 바꾸기(저장)는 위 '이름 바꾸기' 테스트가 저장소에서 건다 — 위젯 테스트의 가짜 시계 안에서 시작한 파일 쓰기는
  // 끝나지 않아 폴더를 잠근다(2026-11-08 시도). 그래서 여기는 창 닫기만 본다.
  testWidgets('이름 바꾸기 창: 취소해도 오류 없이 닫히고 그대로(두 번 열어도)', (t) async {
    final s = PlanStore(tmp);
    await t.runAsync(() => s.saveList([(null, '운동')], d(8)));
    await t.pumpWidget(MaterialApp(home: PlanEditScreen(store: s, now: () => d(8))));
    for (var k = 0; k < 2; k++) {
      await t.tap(find.byTooltip('이름 바꾸기'));
      await t.pumpAndSettle();
      await t.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '바꿀까');
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    }
    expect(s.current.single.title, '운동');
  });

  test('깨진 파일: 저장·체크 거부, 파일 덮어쓰기 0', () async {
    file.writeAsStringSync('{깨짐');
    final s = open();
    expect(s.broken, isTrue);
    expect(await s.saveList([(null, '운동')], d(8)), isNotNull);
    expect(await s.toggle(d(8), 'p1', d(8)), isFalse);
    expect(file.readAsStringSync(), '{깨짐');
  });

  // ---- F-025 보류 ------------------------------------------------------------------
  group('보류', () {
    test('보류 + 체크 → (1, 2), 새로 읽어도 같음 / 해제 → (1, 3)', () async {
      final s = open();
      await s.saveList([(null, '운동'), (null, '독서'), (null, '회사')], d(15));
      expect(await s.toggleHold(d(15), idOf(s, d(15), '회사'), d(15)), isTrue);
      expect(await s.toggle(d(15), idOf(s, d(15), '운동'), d(15)), isTrue);
      expect(s.summary(d(15)), (1, 2));
      final r = open();
      expect(r.summary(d(15)), (1, 2));
      expect(r.heldOn(d(15)), {idOf(r, d(15), '회사')});
      expect(await r.toggleHold(d(15), idOf(r, d(15), '회사'), d(15)), isTrue);
      expect(open().summary(d(15)), (1, 3));
    });

    test('체크한 항목을 보류하면 체크가 풀린다 / 보류한 항목 체크는 거부, 쓰기 0', () async {
      final s = open();
      await s.saveList([(null, '운동')], d(15));
      final id = s.current.single.id;
      await s.toggle(d(15), id, d(15));
      expect(await s.toggleHold(d(15), id, d(15)), isTrue);
      expect(s.doneOn(d(15)), isEmpty);
      expect(open().doneOn(d(15)), isEmpty);
      final before = file.readAsStringSync();
      expect(await s.toggle(d(15), id, d(15)), isFalse);
      expect(file.readAsStringSync(), before);
      expect(s.summary(d(15)), (0, 0));
    });

    test('미래·계획 없는 날·목록에 없는 id·깨진 파일 → 거부, 쓰기 0', () async {
      final s = open();
      await s.saveList([(null, '운동')], d(15));
      final id = s.current.single.id;
      file.deleteSync();
      expect(await s.toggleHold(d(16), id, d(15)), isFalse);
      expect(await s.toggleHold(d(14), id, d(15)), isFalse);
      expect(await s.toggleHold(d(15), 'p999', d(15)), isFalse);
      expect(file.existsSync(), isFalse);
      expect(await s.toggleHold(d(15), id, d(15)), isTrue); // 오늘은 된다
      file.writeAsStringSync('{깨짐');
      expect(await open().toggleHold(d(15), id, d(15)), isFalse);
      expect(file.readAsStringSync(), '{깨짐');
    });

    test('held 키 없는 옛 plans.json → 목록·체크 그대로, 보류 0건', () async {
      file.writeAsStringSync('{"version":1,"next_id":3,"lists":[{"from":"2026-10-10","items":'
          '[{"id":"p1","title":"운동"},{"id":"p2","title":"독서"}]}],"done":{"2026-10-12":["p2"]}}');
      final s = open();
      expect(s.broken, isFalse);
      expect(s.summary(d(12)), (1, 2));
      expect(s.heldOn(d(12)), isEmpty);
      expect(await s.toggleHold(d(12), 'p1', d(15)), isTrue);
      expect(open().summary(d(12)), (1, 1));
    });

    test('이름 바꾸기 → 보류 유지 / 오늘 지운 항목의 보류는 집계에서 빠진다', () async {
      final s = open();
      await s.saveList([(null, '운동'), (null, '회사')], d(15));
      final run = idOf(s, d(15), '운동');
      final work = idOf(s, d(15), '회사');
      await s.toggleHold(d(15), work, d(15));
      await s.saveList([(run, '운동'), (work, '회사 업무')], d(15));
      expect(s.heldOn(d(15)), {work});
      await s.saveList([(run, '운동')], d(15));
      expect(s.heldOn(d(15)), isEmpty);
      expect(s.summary(d(15)), (0, 1));
    });
  });

  // ---- F-026 DO · DON'T --------------------------------------------------------------
  group("DO · DON'T", () {
    test('종류별 저장 → 다시 열어도 종류 그대로, 종류별 집계', () async {
      final s = open();
      await s.saveItems([(null, '운동', PlanKind.doIt), (null, '독서', PlanKind.doIt), (null, '야식', PlanKind.dont)], d(15));
      final r = open();
      expect([for (final i in r.itemsOn(d(15))!) i.kind], [PlanKind.doIt, PlanKind.doIt, PlanKind.dont]);
      expect(r.summary(d(15), kind: PlanKind.doIt), (0, 2));
      expect(r.summary(d(15), kind: PlanKind.dont), (0, 1));
      expect(file.readAsStringSync(), contains('"kind":"dont"'));
    });

    test('kind 없는 옛 항목은 DO / 모르는 kind는 깨진 파일(저장 거부, 파일 그대로)', () async {
      file.writeAsStringSync('{"version":1,"next_id":2,"lists":[{"from":"2026-10-10","items":'
          '[{"id":"p1","title":"운동"}]}],"done":{}}');
      expect(open().current.single.kind, PlanKind.doIt);
      const bad = '{"version":1,"next_id":2,"lists":[{"from":"2026-10-10","items":'
          '[{"id":"p1","title":"운동","kind":"maybe"}]}],"done":{}}';
      file.writeAsStringSync(bad);
      final s = open();
      expect(s.broken, isTrue);
      expect(await s.saveList([(null, '독서')], d(15)), isNotNull);
      expect(file.readAsStringSync(), bad);
    });

    test('종류를 모르는 저장(이름·순서 바꾸기)도 종류를 그대로 둔다', () async {
      final s = open();
      await s.saveItems([(null, '운동', PlanKind.doIt), (null, '야식', PlanKind.dont)], d(15));
      final run = idOf(s, d(15), '운동'), night = idOf(s, d(15), '야식');
      await s.saveList([(night, '야식 금지'), (run, '운동')], d(15));
      expect({for (final i in open().current) i.title: i.kind}, {'야식 금지': PlanKind.dont, '운동': PlanKind.doIt});
    });

    test('같은 이름은 종류가 달라도 거부', () async {
      final s = open();
      expect(await s.saveItems([(null, '운동', PlanKind.doIt), (null, '운 동', PlanKind.dont)], d(15)), isNotNull);
      expect(file.existsSync(), isFalse);
    });

    test("DON'T 체크 = 지켰다 → (1, 1), 보류하면 (0, 0)", () async {
      final s = open();
      await s.saveItems([(null, '운동', PlanKind.doIt), (null, '야식', PlanKind.dont)], d(15));
      final night = idOf(s, d(15), '야식');
      expect(await s.toggle(d(15), night, d(15)), isTrue);
      expect(s.summary(d(15), kind: PlanKind.dont), (1, 1));
      expect(s.summary(d(15), kind: PlanKind.doIt), (0, 1));
      await s.toggleHold(d(15), night, d(15));
      expect(s.summary(d(15), kind: PlanKind.dont), (0, 0));
    });

    testWidgets("설정 편집: DON'T 칸에 추가 → 종류 dont로 저장 호출", (t) async {
      final s = _Capture(tmp);
      await t.pumpWidget(MaterialApp(home: PlanEditScreen(store: s, now: () => d(15))));
      await t.enterText(find.byKey(const ValueKey('plan-add-dont')), '야식');
      await t.tap(find.byKey(const ValueKey('plan-add-button-dont')));
      await t.pump();
      expect(s.saved, [
        [(null, '야식', PlanKind.dont)],
      ]);
      await t.enterText(find.byKey(const ValueKey('plan-add-do')), '운동');
      await t.tap(find.byKey(const ValueKey('plan-add-button-do')));
      await t.pump();
      expect(s.saved.last, [(null, '운동', PlanKind.doIt)]);
    });
  });

  // ---- F-031 평일 · 주말(휴일) ---------------------------------------------------------
  // 2026-11: 14·21·28 = 토, 16 = 월, 17 = 화, 18 = 수.
  group('평일·주말', () {
    DateTime n(int day) => DateTime(2026, 11, day);
    const oldFile = '{"version":1,"next_id":3,"lists":[{"from":"2026-11-02","items":'
        '[{"id":"p1","title":"운동"},{"id":"p2","title":"독서"}]}],"done":{"2026-11-14":["p1"]}}';
    List<String> heldTitles(PlanStore s, DateTime day) =>
        [for (final i in s.itemsOn(day)!) if (s.heldOn(day).contains(i.id)) i.title];

    /// 평일 [운동, 독서] + 주말 [등산](11-16 월요일에 저장).
    Future<PlanStore> withHike() async {
      final s = open();
      await s.saveList([(null, '운동'), (null, '독서')], n(16));
      expect(await s.saveWeekend([(null, '등산', PlanKind.doIt)], n(16)), isNull);
      return s;
    }

    test('나누기: 옛 파일 → 오늘부터 나눈 칸, 지난 주말은 그대로, 다음 주말은 평일 계획 전부 보류', () async {
      file.writeAsStringSync(oldFile);
      final s = open();
      await s.splitFromToday(n(17));
      final r = open();
      expect(RegExp('"from"').allMatches(file.readAsStringSync()).length, 2);
      expect(titles(r.itemsOn(n(14))), ['운동', '독서']);
      expect(r.heldOn(n(14)), isEmpty);
      expect(r.summary(n(14)), (1, 2));
      expect(heldTitles(r, n(21)), ['운동', '독서']);
      expect(r.summary(n(21)), (0, 0));
      expect(titles(r.weekdayItems), ['운동', '독서']);
      expect(r.weekendItems, isEmpty);
    });

    test('다시 나누기는 쓰기 0 / 깨진 파일도 쓰기 0', () async {
      file.writeAsStringSync(oldFile);
      final s = open();
      await s.splitFromToday(n(17));
      final once = file.readAsStringSync();
      file.deleteSync();
      await s.splitFromToday(n(17)); // 이미 나눈 메모리 → 쓰지 않는다
      expect(file.existsSync(), isFalse);
      file.writeAsStringSync(once);
      await open().splitFromToday(n(18)); // 나눈 파일을 다시 읽어도 → 쓰지 않는다
      expect(file.readAsStringSync(), once);
      file.writeAsStringSync('{깨짐');
      await open().splitFromToday(n(17));
      expect(file.readAsStringSync(), '{깨짐');
    });

    test('주말 계획 추가 → 토요일 = 등산(위) · 운동·독서(보류), (0, 1) / 평일엔 등산 없음', () async {
      final s = await withHike();
      final r = open();
      expect(titles(r.itemsOn(n(21))), ['등산', '운동', '독서']);
      expect(heldTitles(r, n(21)), ['운동', '독서']);
      expect(r.summary(n(21)), (0, 1));
      expect(titles(r.itemsOn(n(18))), ['운동', '독서']);
      expect(titles(s.weekdayItems), ['운동', '독서']);
    });

    test('설정에서 풀기 → 토요일 운동 보류 아님 (0, 2) / 주말에서 지우면 다시 보류, 평일엔 그대로', () async {
      final s = await withHike();
      final hike = s.weekendItems.single.id, run = idOf(s, n(18), '운동');
      await s.saveWeekend([(hike, '등산', PlanKind.doIt), (run, '운동', PlanKind.doIt)], n(17));
      final r = open();
      expect(titles(r.itemsOn(n(21))), ['등산', '운동', '독서']);
      expect(heldTitles(r, n(21)), ['독서']);
      expect(r.summary(n(21)), (0, 2));
      await r.saveWeekend([(hike, '등산', PlanKind.doIt)], n(17));
      expect(heldTitles(open(), n(21)), ['운동', '독서']);
      expect(titles(open().itemsOn(n(18))), ['운동', '독서']);
    });

    test('평일에서 편입한 항목을 지우면 주말에서도 없어진다 / 주말에서 이름 바꾸면 평일도', () async {
      final s = await withHike();
      final hike = s.weekendItems.single.id, run = idOf(s, n(18), '운동'), read = idOf(s, n(18), '독서');
      await s.saveWeekend([(hike, '등산', PlanKind.doIt), (run, '운동', PlanKind.doIt), (read, '독서', PlanKind.doIt)], n(17));
      await s.saveWeekend([(hike, '등산', PlanKind.doIt), (run, '운동 30분', PlanKind.doIt), (read, '독서', PlanKind.doIt)], n(17));
      expect(titles(open().itemsOn(n(18))), ['운동 30분', '독서']);
      await s.saveItems([(read, '독서', PlanKind.doIt)], n(17));
      final r = open();
      expect(titles(r.weekendItems), ['등산', '독서']);
      expect(titles(r.itemsOn(n(21))), ['등산', '독서']);
      expect(titles(r.itemsOn(n(18))), ['독서']);
    });

    test('같은 이름은 평일·주말이 달라도 거부, 파일 그대로', () async {
      final s = await withHike();
      final before = file.readAsStringSync();
      expect(await s.saveWeekend([...s.weekendItems.map((i) => (i.id, i.title, i.kind)), (null, '운 동', PlanKind.dont)], n(17)),
          isNotNull);
      expect(await s.saveList([(null, '등 산')], n(17)), isNotNull);
      expect(file.readAsStringSync(), before);
    });

    test('그날만 풀기: 토요일 보류된 독서를 길게 눌러 풀면 체크 가능, 다음 토요일은 보류 / 다시 누르면 보류·체크 풀림', () async {
      final s = await withHike();
      final read = idOf(s, n(18), '독서');
      expect(await s.toggle(n(21), read, n(21)), isFalse);
      expect(await s.toggleHold(n(21), read, n(21)), isTrue);
      expect(await s.toggle(n(21), read, n(21)), isTrue);
      final r = open();
      expect(heldTitles(r, n(21)), ['운동']);
      expect(r.summary(n(21)), (1, 2));
      expect(heldTitles(r, n(28)), ['운동', '독서']);
      expect(await r.toggleHold(n(21), read, n(21)), isTrue);
      expect(heldTitles(open(), n(21)), ['운동', '독서']);
      expect(open().doneOn(n(21)), isEmpty);
      expect(open().summary(n(21)), (0, 1));
    });

    test('휴일 지정: 수요일 → 주말 목록, 다시 읽어도 휴일 / 해제 → 평일 목록·체크 다시 / 토·일·나누기 전 날은 거부', () async {
      file.writeAsStringSync(oldFile);
      final s = open();
      await s.splitFromToday(n(16));
      expect(await s.saveWeekend([(null, '등산', PlanKind.doIt)], n(16)), isNull);
      final run = idOf(s, n(18), '운동');
      expect(await s.toggle(n(18), run, n(18)), isTrue);
      expect(await s.toggleHoliday(n(18)), isTrue);
      final r = open();
      expect(r.isHoliday(n(18)), isTrue);
      expect(titles(r.itemsOn(n(18))), ['등산', '운동', '독서']);
      expect(r.summary(n(18)), (0, 1));
      expect(r.doneOn(n(18)), isEmpty);
      expect(await r.toggleHoliday(n(18)), isTrue);
      final back = open();
      expect(back.isHoliday(n(18)), isFalse);
      expect(titles(back.itemsOn(n(18))), ['운동', '독서']);
      expect(back.summary(n(18)), (1, 2));
      final before = file.readAsStringSync();
      expect(await back.toggleHoliday(n(21)), isFalse);
      expect(await back.toggleHoliday(n(13)), isFalse, reason: '11-13은 나누기 전 칸');
      expect(file.readAsStringSync(), before);
    });

    test('주말 계획에 새로 넣은 것은 그날 묶음 맨 위, 보류된 평일 계획은 그 아래', () async {
      final s = await withHike();
      final hike = s.weekendItems.single.id;
      await s.saveWeekend([(null, '산책', PlanKind.doIt), (hike, '등산', PlanKind.doIt)], n(17));
      final r = open();
      expect(titles(r.itemsOn(n(21))), ['산책', '등산', '운동', '독서']);
      expect(heldTitles(r, n(21)), ['운동', '독서']);
    });

    // 2026-11-24 사용자: 평일 DON'T는 주말·휴일에도 보류 없이 — 오늘부터 주말 계획에 자동 편입(SCHEMA `dont_rest_from`).
    const beforeDontFile = '{"version":1,"next_id":4,"lists":[{"from":"2026-11-09","items":'
        '[{"id":"p1","title":"운동","kind":"do"},{"id":"p2","title":"야식","kind":"dont"},'
        '{"id":"p3","title":"등산","kind":"do","weekday":false}],"weekend":["p3"]}],"done":{}}';

    test("평일 DON'T 자동 편입: 표시 없는 파일 → 오늘부터 주말에 야식 활성, 운동은 보류 / 지난 토요일 그대로 / 다시 해도 쓰기 0", () async {
      file.writeAsStringSync(beforeDontFile);
      final s = open();
      await s.includeWeekdayDontsOnRest(n(17));
      final r = open();
      expect(titles(r.itemsOn(n(21))), ['등산', '야식', '운동']);
      expect(heldTitles(r, n(21)), ['운동']);
      expect(r.summary(n(21), kind: PlanKind.dont), (0, 1));
      expect(heldTitles(r, n(14)), ['운동', '야식'], reason: '지난 토요일은 그대로');
      expect(file.readAsStringSync(), contains('"dont_rest_from":"2026-11-17"'));
      file.deleteSync();
      await s.includeWeekdayDontsOnRest(n(17));
      expect(file.existsSync(), isFalse, reason: '이미 넣었으면 쓰기 0');
    });

    test("평일 DON'T 자동 편입: 보류로 되돌린 DON'T는 다시 켜도 다시 안 들어온다 / 깨진 파일은 쓰기 0", () async {
      file.writeAsStringSync(beforeDontFile);
      await open().includeWeekdayDontsOnRest(n(17));
      final s = open();
      await s.saveWeekend([for (final i in s.weekendItems) if (i.title != '야식') (i.id, i.title, i.kind)], n(17));
      final r = open();
      await r.includeWeekdayDontsOnRest(n(18));
      expect(heldTitles(open(), n(21)), ['운동', '야식']);
      file.writeAsStringSync('{깨짐');
      await open().includeWeekdayDontsOnRest(n(17));
      expect(file.readAsStringSync(), '{깨짐');
    });

    test("평일 편집에서 새로 넣은 DON'T는 주말에도 들어간다, 새 DO는 주말에 보류", () async {
      final s = await withHike();
      final rows = [for (final i in s.weekdayItems) (i.id, i.title, i.kind)];
      await s.saveItems([...rows, (null, '청소', PlanKind.doIt), (null, '야식', PlanKind.dont)], n(17));
      final r = open();
      expect(titles(r.weekendItems), ['등산', '야식']);
      expect(heldTitles(r, n(21)), ['운동', '독서', '청소']);
    });

    testWidgets('주말 편집: 새 항목은 맨 위로 저장 호출 / 보류된 평일 계획은 보이지 않는다', (t) async {
      await t.runAsync(() async {
        final w = PlanStore(tmp);
        await w.saveList([(null, '운동')], n(16));
        await w.saveWeekend([(null, '등산', PlanKind.doIt)], n(16));
      });
      final store = _Capture(tmp);
      await t.pumpWidget(MaterialApp(home: PlanEditScreen(store: store, weekend: true, now: () => n(17))));
      final hike = store.weekendItems.single.id;
      expect(find.text('등산'), findsOneWidget);
      expect(find.text('운동'), findsNothing, reason: '보류된 평일 계획은 설정에 안 보인다');
      expect(find.text('풀기'), findsNothing);
      await t.enterText(find.byKey(const ValueKey('plan-add-do')), '산책');
      await t.tap(find.byKey(const ValueKey('plan-add-button-do')));
      await t.pump();
      expect(store.savedWeekend.last, [(null, '산책', PlanKind.doIt), (hike, '등산', PlanKind.doIt)]);
      expect(store.saved, isEmpty, reason: '주말 편집은 평일 계획 저장을 부르지 않는다');
    });
  });

  // ---- F-024 하루 평가 ----------------------------------------------------------
  group('하루 평가', () {
    late File reviews;
    setUp(() => reviews = File('${tmp.path}/reviews.json'));

    test('오늘·지난 날 저장 → 새로 읽어도 그 글 / 미래는 거부, 쓰기 0', () async {
      final s = open();
      expect(await s.saveReview(d(13), '보고서 끝냄', d(13)), isTrue);
      expect(await s.saveReview(d(10), '지난 날\n두 줄', d(13)), isTrue);
      final before = reviews.readAsStringSync();
      expect(await s.saveReview(d(14), '내일', d(13)), isFalse);
      expect(reviews.readAsStringSync(), before);
      final again = open();
      expect(again.reviewOn(d(13)), '보고서 끝냄');
      expect(again.reviewOn(d(10)), '지난 날\n두 줄');
      expect(again.reviewOn(d(14)), isNull);
      expect(file.existsSync(), isFalse, reason: '계획 파일은 건드리지 않는다');
    });

    test('같은 글이면 쓰기 0 / 공백뿐이면 지움 / 1001자 거부', () async {
      final s = open();
      await s.saveReview(d(13), '그대로', d(13));
      reviews.writeAsStringSync('{"version":1,"reviews":{"2026-10-13":"그대로"},"표시":1}');
      expect(await s.saveReview(d(13), '그대로', d(13)), isTrue);
      expect(reviews.readAsStringSync(), contains('"표시":1'), reason: '같은 글이면 다시 쓰지 않는다');
      expect(await s.saveReview(d(13), '가' * (maxReviewChars + 1), d(13)), isFalse);
      expect(await s.saveReview(d(13), '가' * maxReviewChars, d(13)), isTrue);
      expect(await s.saveReview(d(13), '  \n ', d(13)), isTrue);
      expect(s.reviewOn(d(13)), isNull);
      expect(open().reviewOn(d(13)), isNull);
    });

    test('깨진 reviews.json: 로그 1줄 · 평가 저장 거부·덮어쓰기 0, 계획 체크는 된다', () async {
      final logDir = Directory('${tmp.path}/log')..createSync();
      initLog(logDir);
      final s0 = open();
      await s0.saveList([(null, '운동')], d(13));
      reviews.writeAsStringSync('{깨짐');
      final s = open();
      expect(s.reviewOn(d(13)), isNull);
      expect(s.reviewsBroken, isTrue);
      expect(await s.saveReview(d(13), '글', d(13)), isFalse);
      expect(reviews.readAsStringSync(), '{깨짐');
      expect(await s.toggle(d(13), s.current.single.id, d(13)), isTrue);
      final log = File('${logDir.path}/chaerok.log').readAsStringSync();
      expect('하루 평가 파일을 읽지 못함'.allMatches(log).length, 1);
    });
  });
}
