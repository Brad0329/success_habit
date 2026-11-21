// '성공습관' — 계획 달력 전용 앱. 화면은 계획(맨 밑)과 설정 둘이다.
// 수집·목록·공유(채록 기능)는 2026-11-21에 다른 저장소(M채록, `chaerok_phone`)로 갈라졌다 — 여기에는 소스가 없다.
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_menu.dart';
import 'app_paths.dart';
import 'log.dart';
import 'plan_screen.dart';
import 'plans.dart';
import 'platform.dart';
import 'settings_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final files = Directory(await androidFilesDir());
  initLog(files);
  FlutterError.onError = (d) {
    logError('Flutter 오류', d.exception, d.stack);
    FlutterError.presentError(d);
  };
  final paths = AppPaths(files.path);
  // 계획 화면·설정 편집이 같은 것을 써야 한쪽에서 바꾼 것이 다른 쪽에 바로 보인다.
  final plans = PlanStore(paths.plans);
  try {
    await plans.splitFromToday(DateTime.now()); // F-031 나누기 전 목록이면 오늘부터 평일·주말로
  } on Object catch (e, st) {
    // 앱은 계속 띄운다 — 나누기 전 목록으로 보이고, 다음 저장이 나눈 칸을 쓴다.
    logError('계획 평일·주말 나누기 실패', e, st);
  }
  runApp(ChaerokApp(plans: plans));
}

class ChaerokApp extends StatelessWidget {
  const ChaerokApp({super.key, required this.plans});

  /// F-016 계획 — 첫 화면이자 설정 화면의 내용.
  final PlanStore plans;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '성공습관',
      theme: chaerokTheme(Brightness.light),
      darkTheme: chaerokTheme(Brightness.dark),
      // F-017 ⋯ 메뉴 — Navigator 바깥에 두어 쌓인 모든 화면이 찾는다.
      builder: (ctx, child) => AppNav(
        // 맨 밑 화면이 계획이라 메뉴의 '계획'은 위를 걷어내고 내려간다(같은 화면을 둘 만들지 않는다).
        openPlan: (c) => Navigator.of(c).popUntil((r) => r.isFirst),
        openSettings: (c) => _push(c, SettingsScreen(plans: plans)),
        child: guardTextScale(ctx, child),
      ),
      home: PlanScreen(store: plans),
    );
  }

  static void _push(BuildContext c, Widget page) =>
      Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => page));
}
