// F-024 계획 화면 하루 평가 — 자동 저장(1초·날짜 바꿀 때)·미래 칸 없음·말풍선. 모양·위치는 사용자 실테스트.
//
// 저장소는 저장만 가로채는 가짜 — 위젯 테스트의 가짜 시계 안에서 시작한 파일 쓰기는 끝나지 않아 폴더를 잠근다
// (plans_test '이름 바꾸기 창' 주석). 실제 파일 저장은 plans_test '하루 평가'가 건다.
import 'dart:io';

import 'package:chaerok/plan_screen.dart';
import 'package:chaerok/plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int day) => DateTime(2026, 11, day);

class _Store extends PlanStore {
  _Store(super.dir, {this.items = _items});
  final List<PlanItem> items;
  final saved = <(String, String)>[];
  final _mem = <String, String>{};

  @override
  String? reviewOn(DateTime day) => _mem[dayKey(day)];

  @override
  Future<bool> saveReview(DateTime day, String text, DateTime today) async {
    if (dayKey(day).compareTo(dayKey(today)) > 0) return false;
    saved.add((dayKey(day), text));
    _mem[dayKey(day)] = text;
    return true;
  }

  // F-025 보류 — 목록 DO [운동, 회사] + DON'T [야식](F-026) 고정, 보류만 메모리에.
  static const _items = [PlanItem('p1', '운동'), PlanItem('p2', '회사'), PlanItem('p3', '야식', PlanKind.dont)];
  final _held = <String>{};

  // F-031 휴일 — 지정한 날만 메모리에, 쉬는 날 목록은 주말 목록 고정.
  static const _restItems = [PlanItem('p9', '등산'), PlanItem('p1', '운동')];
  final _holidays = <String>{};

  @override
  bool isHoliday(DateTime day) => _holidays.contains(dayKey(day));

  @override
  bool isRestDay(DateTime day) => isWeekend(day) || isHoliday(day);

  @override
  bool canSetHoliday(DateTime day) => !isWeekend(day);

  @override
  Future<bool> toggleHoliday(DateTime day) async {
    if (!_holidays.remove(dayKey(day))) _holidays.add(dayKey(day));
    return true;
  }

  @override
  List<PlanItem>? itemsOn(DateTime day) => isRestDay(day) ? _restItems : items;

  // F-037 통계의 '지금 항목' 묶음 — 평일 목록 고정.
  @override
  List<PlanItem> get current => items;

  @override
  Set<String> doneOn(DateTime day) => const {};

  @override
  Set<String> heldOn(DateTime day) => Set.of(_held);

  @override
  Future<bool> toggleHold(DateTime day, String id, DateTime today) async {
    if (!_held.remove(id)) _held.add(id);
    return true;
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chaerok_plan_screen'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<_Store> show(WidgetTester t, {Map<int, String> reviews = const {}, List<PlanItem>? items}) async {
    // 달력·목록·평가 칸이 한 화면에 다 보이게 — ListView는 화면 밖 칸을 만들지 않는다.
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = items == null ? _Store(tmp) : _Store(tmp, items: items);
    reviews.forEach((day, text) => s._mem[dayKey(d(day))] = text);
    await t.pumpWidget(MaterialApp(home: PlanScreen(store: s, now: () => DateTime(2026, 11, 13, 21, 4))));
    await t.pump();
    return s;
  }

  final field = find.byKey(const ValueKey('review-field'));
  Finder day(int n) => find.text('$n').first;

  testWidgets('F-037 통계 아이콘을 누르면 통계 화면에 이번 달 항목 줄', (t) async {
    await show(t);
    await t.tap(find.byKey(const ValueKey('plan-stats')));
    await t.pumpAndSettle();
    expect(find.text('계획 통계'), findsOneWidget);
    expect(find.text('2026-11-01 ~ 11-13 (13일)'), findsOneWidget);
    // 11-01~13 평일 9일 — 운동은 평일 목록에도, 쉬는 날 목록에도 있어 13일 모두 해야 한 날.
    expect(find.text('0 / 13일'), findsOneWidget);
    expect(find.text('회사'), findsOneWidget);
  });

  testWidgets('쓰고 1초 지나면 저장, 그 전엔 저장 안 함', (t) async {
    final s = await show(t);
    await t.enterText(field, '보고서 끝냄');
    await t.pump(const Duration(milliseconds: 900));
    expect(s.saved, isEmpty);
    await t.pump(const Duration(milliseconds: 200));
    expect(s.saved, [('2026-11-13', '보고서 끝냄')]);
    await t.pump();
    expect(find.text('저장됨 · 21:04'), findsOneWidget);
  });

  // 계획 화면이 맨 밑 화면이면 뒤로 = 앱 닫힘이라 dispose가 불린다는 보장이 없다(2026-11-19 spec-checker R1).
  // 앱이 화면에서 내려가는 순간(뒤로·홈·최근 앱에서 밀어 끄기 모두 paused를 거친다) 안 저장한 글을 저장한다.
  testWidgets('1초 전에 앱이 내려가면(paused) 그때 저장 / 고친 게 없으면 저장 0', (t) async {
    final s = await show(t);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(s.saved, isEmpty, reason: '고친 게 없으면 저장하지 않는다');
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.enterText(field, '쓰다가 바로 뒤로');
    await t.pump(const Duration(milliseconds: 300));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(s.saved, [('2026-11-13', '쓰다가 바로 뒤로')]);
    await t.pump(const Duration(seconds: 2));
    expect(s.saved.length, 1, reason: '타이머가 풀려 두 번 저장하지 않는다');
  });

  testWidgets('1초 전에 다른 날짜를 누르면 이전 날 글이 저장되고 칸은 그날 글로', (t) async {
    final s = await show(t, reviews: {10: '10일의 글'});
    await t.enterText(field, '오늘 글');
    await t.tap(day(10));
    await t.pump();
    expect(s.saved, [('2026-11-13', '오늘 글')]);
    expect(t.widget<TextField>(field).controller!.text, '10일의 글');
    await t.pump(const Duration(seconds: 2));
    expect(s.saved.length, 1, reason: '옮겨 간 날은 고치지 않았으니 저장 없음');
  });

  testWidgets('F-025 항목을 길게 누르면 보류 표시·체크 칸 꺼짐·완료 분모 줄어듦, 다시 길게 누르면 해제', (t) async {
    await show(t);
    Finder box(String title) => find.widgetWithText(CheckboxListTile, title);
    expect(find.text('0 / 2 완료'), findsOneWidget);
    expect(t.widget<CheckboxListTile>(box('회사')).onChanged, isNotNull);
    await t.longPress(find.text('회사'));
    await t.pump();
    expect(find.text('0 / 1 완료'), findsOneWidget);
    expect(find.text('보류'), findsOneWidget);
    expect(t.widget<CheckboxListTile>(box('회사')).onChanged, isNull);
    expect(t.widget<CheckboxListTile>(box('운동')).onChanged, isNotNull);
    await t.longPress(find.text('회사'));
    await t.pump();
    expect(find.text('0 / 2 완료'), findsOneWidget);
    expect(find.text('보류'), findsNothing);
  });

  testWidgets("F-026 그날 목록: DO 묶음 위 · DON'T 묶음 아래, 묶음마다 N / M", (t) async {
    await show(t);
    final doHead = find.text('DO');
    final dontHead = find.text("DON'T");
    expect(doHead, findsOneWidget);
    expect(dontHead, findsOneWidget);
    expect(find.text('0 / 2 완료'), findsOneWidget);
    expect(find.text('0 / 1 지킴'), findsOneWidget);
    final yDo = t.getTopLeft(doHead).dy, yDont = t.getTopLeft(dontHead).dy;
    expect(yDo < t.getTopLeft(find.text('운동')).dy, isTrue);
    expect(t.getTopLeft(find.text('회사')).dy < yDont, isTrue);
    expect(yDont < t.getTopLeft(find.text('야식')).dy, isTrue);
  });

  testWidgets("F-026 DON'T 항목이 없으면 DON'T 묶음 없음", (t) async {
    await show(t, items: const [PlanItem('p1', '운동')]);
    expect(find.text('DO'), findsOneWidget);
    expect(find.text("DON'T"), findsNothing);
  });

  testWidgets("F-031 평일엔 '휴일로 지정' — 누르면 그날 목록이 주말 목록 / 토·일엔 단추 없음", (t) async {
    await show(t); // 11-13 금요일
    final toggle = find.byKey(const ValueKey('holiday-toggle'));
    expect(find.text('휴일로 지정'), findsOneWidget);
    expect(find.text('등산'), findsNothing);
    await t.tap(toggle);
    await t.pump();
    expect(find.text('등산'), findsOneWidget);
    expect(find.text('회사'), findsNothing);
    expect(find.text('휴일 해제'), findsOneWidget);
    await t.tap(day(14)); // 토요일
    await t.pump();
    expect(toggle, findsNothing);
    expect(find.text('등산'), findsOneWidget);
  });

  testWidgets('미래 날짜는 평가 칸 없음', (t) async {
    await show(t);
    expect(find.text('하루 평가하기'), findsOneWidget);
    await t.tap(day(20));
    await t.pump();
    expect(find.text('하루 평가하기'), findsNothing);
    expect(field, findsNothing);
  });

  testWidgets('평가를 쓴 날을 누르면 말풍선에 그 글, 안 쓴 날은 없음, 말풍선을 누르면 닫힘', (t) async {
    await show(t, reviews: {10: '보고서 초안을 끝냄'});
    final bubble = find.byKey(const ValueKey('review-bubble'));
    await t.tap(day(11));
    await t.pump();
    expect(bubble, findsNothing);
    await t.tap(day(10));
    await t.pump();
    expect(bubble, findsOneWidget);
    expect(find.descendant(of: bubble, matching: find.text('보고서 초안을 끝냄')), findsOneWidget);
    await t.tap(bubble);
    await t.pump();
    expect(bubble, findsNothing);
  });

  // 2026-11-24 사용자: 설정에서 평일·주말 계획을 넣었는데 달력에 안 나왔다 — 맨 밑 계획 화면이 돌아와도 다시 그리지 않았다.
  testWidgets('설정(위 화면)에서 계획을 바꾸고 돌아오면 계획 화면에 바로 보인다', (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = PlanStore(tmp); // 진짜 저장소 — 저장이 알리는 것까지 건다
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
        navigatorKey: nav, home: PlanScreen(store: s, now: () => DateTime(2026, 11, 13, 21, 4))));
    expect(find.text('운동'), findsNothing);
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('설정'))));
    await t.pumpAndSettle();
    // 파일 쓰기는 진짜 비동기라 가짜 시계 밖에서 기다린다.
    await t.runAsync(() => s.saveItems([(null, '운동', PlanKind.doIt)], d(13)));
    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(find.text('운동'), findsOneWidget);
  });
}
