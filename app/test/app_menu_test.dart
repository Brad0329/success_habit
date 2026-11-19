// F-017 ⋯ 메뉴 — 항목 순서·입구 없는 항목 숨김·화면이 쌓이는 순서. 모양은 사용자 실테스트.
import 'dart:io';

import 'package:chaerok/app_menu.dart';
import 'package:chaerok/log.dart';
import 'package:chaerok/main.dart';
import 'package:chaerok/paste_screen.dart';
import 'package:chaerok/plan_screen.dart';
import 'package:chaerok/plans.dart';
import 'package:chaerok/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _page(String name, AppMenuItem current) =>
    Scaffold(appBar: AppBar(title: Text(name), actions: [AppMenu(current: current)]));

void _push(BuildContext c, String name, AppMenuItem current) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => _page(name, current)));

void main() {
  Widget app({bool all = false}) => MaterialApp(
        builder: (_, child) => AppNav(
          openPlan: (c) => _push(c, '계획 화면', AppMenuItem.plan),
          openList: (c) => _push(c, '목록 화면', AppMenuItem.list),
          openChat: (c) => _push(c, '대화 화면', AppMenuItem.chat),
          openMemorize: all ? (c) => _push(c, '외울 문장 화면', AppMenuItem.memorize) : null,
          openSettings: all ? (c) => _push(c, '설정 화면', AppMenuItem.settings) : null,
          child: child!,
        ),
        home: _page('바닥', AppMenuItem.paste),
      );

  Future<void> pick(WidgetTester t, String label) async {
    await t.tap(find.byTooltip('메뉴').last);
    await t.pumpAndSettle();
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  Future<List<PopupMenuItem<AppMenuItem>>> menu(WidgetTester t) async {
    await t.tap(find.byTooltip('메뉴').last);
    await t.pumpAndSettle();
    return t.widgetList<PopupMenuItem<AppMenuItem>>(find.byType(PopupMenuItem<AppMenuItem>)).toList();
  }

  String top(WidgetTester t) => t.widget<Text>(find.descendant(of: find.byType(AppBar).last, matching: find.byType(Text))).data!;

  testWidgets('입구가 다 있으면 메뉴 순서 = 계획·붙여넣기·목록·대화·외울 문장·설정, 지금 화면은 잠김', (t) async {
    await t.pumpWidget(app(all: true));
    final items = await menu(t);
    expect(items.map((i) => i.value), AppMenuItem.values);
    expect(items.map((i) => (i.child! as Row).children.whereType<Text>().single.data),
        ['계획', '붙여넣기', '목록', '대화', '외울 문장', '설정']);
    expect(items.map((i) => i.enabled), [true, false, true, true, true, true]);
  });

  testWidgets('입구가 없는 항목(외울 문장·설정)은 메뉴에 안 나온다', (t) async {
    await t.pumpWidget(app());
    expect((await menu(t)).map((i) => i.value), [AppMenuItem.plan, AppMenuItem.paste, AppMenuItem.list, AppMenuItem.chat]);
  });

  testWidgets('showPaste를 끄면 메뉴에 붙여넣기가 없다', (t) async {
    await t.pumpWidget(MaterialApp(
      builder: (_, child) =>
          AppNav(openPlan: (c) => _push(c, '계획 화면', AppMenuItem.plan), showPaste: false, child: child!),
      home: _page('바닥', AppMenuItem.plan),
    ));
    expect((await menu(t)).map((i) => i.value), [AppMenuItem.plan]);
  });

  // 목록·붙여넣기 숨김(2026-11-19 사용자) 조립 — 되살리면 이 테스트를 git 이력의 'Phase 004 조립' 테스트로 되돌린다.
  testWidgets('조립(목록·붙여넣기 숨김): 맨 밑 화면이 계획이고 메뉴는 계획(잠김)·설정 둘 / 설정에 계획 두 줄 / 설정에서 계획을 고르면 맨 밑으로',
      (t) async {
    final tmp = Directory.systemTemp.createTempSync('chaerok_menu');
    addTearDown(() => tmp.deleteSync(recursive: true));
    initLog(tmp);
    await t.pumpWidget(ChaerokApp(plans: PlanStore(Directory('${tmp.path}/plans'))));
    await t.pumpAndSettle();
    expect(find.byType(PlanScreen), findsOneWidget);
    expect(find.byType(PasteScreen, skipOffstage: false), findsNothing);
    final items = await menu(t);
    expect(items.map((i) => i.value), [AppMenuItem.plan, AppMenuItem.settings]);
    expect(items.map((i) => i.enabled), [false, true]);
    await t.tap(find.text('설정').last);
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('평일 계획'), findsOneWidget);
    expect(find.text('주말·휴일 계획'), findsOneWidget);
    await pick(t, '계획');
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(PlanScreen), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('계획 → 목록 → 대화 → 계획으로 옮긴 뒤 뒤로 4번 = 대화·목록·계획·바닥 차례로', (t) async {
    await t.pumpWidget(app());
    for (final l in ['계획', '목록', '대화', '계획']) {
      await pick(t, l);
    }
    expect(top(t), '계획 화면');
    final back = <String>[];
    for (var n = 0; n < 4; n++) {
      await t.pageBack();
      await t.pumpAndSettle();
      back.add(top(t));
    }
    expect(back, ['대화 화면', '목록 화면', '계획 화면', '바닥']);
  });

  testWidgets('붙여넣기는 위를 걷어내고 맨 밑 화면으로 내려간다(같은 화면을 둘 만들지 않음)', (t) async {
    await t.pumpWidget(app());
    await pick(t, '계획');
    await pick(t, '목록');
    await pick(t, '붙여넣기');
    expect(top(t), '바닥');
    expect(find.byType(AppBar), findsOneWidget);
  });
}
