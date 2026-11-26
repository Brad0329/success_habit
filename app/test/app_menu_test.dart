// F-017 ⋯ 메뉴 — 항목 순서·입구 없는 항목 숨김·화면이 쌓이는 순서. 모양은 사용자 실테스트.
import 'dart:io';

import 'package:chaerok/app_menu.dart';
import 'package:chaerok/help_screen.dart';
import 'package:chaerok/log.dart';
import 'package:chaerok/main.dart';
import 'package:chaerok/plan_screen.dart';
import 'package:chaerok/plans.dart';
import 'package:chaerok/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _page(String name, AppMenuItem? current) =>
    Scaffold(appBar: AppBar(title: Text(name), actions: [AppMenu(current: current)]));

void _push(BuildContext c, String name, AppMenuItem current) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => _page(name, current)));

void main() {
  Widget app({bool settings = true, bool help = false}) => MaterialApp(
        builder: (_, child) => AppNav(
          openPlan: (c) => _push(c, '계획 화면', AppMenuItem.plan),
          openSettings: settings ? (c) => _push(c, '설정 화면', AppMenuItem.settings) : null,
          openHelp: help ? (c) => _push(c, '도움말 화면', AppMenuItem.help) : null,
          child: child!,
        ),
        home: _page('바닥', null),
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

  testWidgets('입구가 다 있으면 메뉴 순서 = 계획·설정·도움말', (t) async {
    await t.pumpWidget(app(help: true));
    final items = await menu(t);
    expect(items.map((i) => i.value), AppMenuItem.values);
    expect(items.map((i) => (i.child! as Row).children.whereType<Text>().single.data), ['계획', '설정', '도움말']);
    expect(items.map((i) => i.enabled), [true, true, true]);
  });

  testWidgets('입구가 없는 항목(설정)은 메뉴에 안 나온다', (t) async {
    await t.pumpWidget(app(settings: false));
    expect((await menu(t)).map((i) => i.value), [AppMenuItem.plan]);
  });

  testWidgets('메뉴로 연 화면은 위에 쌓인다: 계획 → 설정 뒤 뒤로 2번 = 계획·바닥 차례로, 지금 화면 항목은 잠김', (t) async {
    await t.pumpWidget(app());
    await pick(t, '계획');
    await pick(t, '설정');
    expect(top(t), '설정 화면');
    expect((await menu(t)).map((i) => i.enabled), [true, false]);
    await t.tapAt(const Offset(5, 5)); // 메뉴 닫기
    await t.pumpAndSettle();
    final back = <String>[];
    for (var n = 0; n < 2; n++) {
      await t.pageBack();
      await t.pumpAndSettle();
      back.add(top(t));
    }
    expect(back, ['계획 화면', '바닥']);
  });

  testWidgets('조립: 맨 밑 화면이 계획이고 메뉴는 계획(잠김)·설정·도움말 / 설정에 계획 두 줄 / 설정에서 계획을 고르면 맨 밑으로', (t) async {
    final tmp = Directory.systemTemp.createTempSync('chaerok_menu');
    addTearDown(() => tmp.deleteSync(recursive: true));
    initLog(tmp);
    await t.pumpWidget(ChaerokApp(plans: PlanStore(Directory('${tmp.path}/plans'))));
    await t.pumpAndSettle();
    expect(find.byType(PlanScreen), findsOneWidget);
    final items = await menu(t);
    expect(items.map((i) => i.value), [AppMenuItem.plan, AppMenuItem.settings, AppMenuItem.help]);
    expect(items.map((i) => i.enabled), [false, true, true]);
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

  testWidgets('F-101 조립: 도움말을 누르면 도움말 화면이 위에 열리고 그 항목은 잠긴다 / 뒤로 = 계획 화면', (t) async {
    final tmp = Directory.systemTemp.createTempSync('chaerok_menu');
    addTearDown(() => tmp.deleteSync(recursive: true));
    initLog(tmp);
    await t.pumpWidget(ChaerokApp(plans: PlanStore(Directory('${tmp.path}/plans'))));
    await t.pumpAndSettle();
    await pick(t, '도움말');
    expect(find.byType(HelpScreen), findsOneWidget);
    expect((await menu(t)).map((i) => i.enabled), [true, true, false]);
    await t.tapAt(const Offset(5, 5)); // 메뉴 닫기
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(HelpScreen), findsNothing);
    expect(find.byType(PlanScreen), findsOneWidget);
  });
}
