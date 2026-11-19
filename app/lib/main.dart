// ★ 목록·붙여넣기 숨김(2026-11-19 사용자 결정 — 앱 이름 '성공습관'): 화면에서 완전히 안 보이게 조립만 주석으로 막았다.
//   소스(paste_screen·collection_*·phone_store 등)와 그 테스트는 그대로 있다. 되살리려면 이 파일의 `[숨김]` 주석을 풀고
//   `AppNav(showPaste: false)`를 지우고 home을 PasteScreen으로 되돌린다(`app_menu_test`의 조립 테스트도 함께).
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_menu.dart';
import 'app_paths.dart';
// [숨김] import 'change_signal.dart';
// [숨김] import 'collection_list.dart';
// [숨김] import 'collection_screen.dart';
import 'log.dart';
// [숨김] import 'paste_screen.dart';
// [숨김] import 'phone_store.dart';
import 'plan_screen.dart';
import 'plans.dart';
import 'platform.dart';
import 'settings_screen.dart';
import 'share_entry.dart';
import 'theme.dart';
// [숨김] import 'voice.dart';

/// 공유 메뉴(ShareActivity.kt)의 Dart 진입점 — **공유 엔진**. main.dart에 있어야 Flutter가 찾는다.
@pragma('vm:entry-point')
Future<void> shareMain() => runShare();

/// **메인 화면 엔진**의 진입점.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final device = androidDevice();
  final files = Directory(await device.filesDir());
  initLog(files);
  FlutterError.onError = (d) {
    logError('Flutter 오류', d.exception, d.stack);
    FlutterError.presentError(d);
  };
  final paths = AppPaths(files.path);
  // [숨김] final store = PhoneStore(paths.records);
  // [숨김] final list = CollectionDeps(
  // [숨김]   collection: Collection(reader: () => store, deleter: () => store),
  // [숨김]   openUrl: device.openUrl!,
  // [숨김]   openBytes: device.openBytes!,
  // [숨김]   changed: ChangeSignal(paths.changed),
  // [숨김] );
  // 계획 화면·설정 편집이 같은 것을 써야 한쪽에서 바꾼 것이 다른 쪽에 바로 보인다.
  final plans = PlanStore(paths.plans);
  try {
    await plans.splitFromToday(DateTime.now()); // F-031 나누기 전 목록이면 오늘부터 평일·주말로
  } on Object catch (e, st) {
    // 앱은 계속 띄운다 — 나누기 전 목록으로 보이고, 다음 저장이 나눈 칸을 쓴다.
    logError('계획 평일·주말 나누기 실패', e, st);
  }
  runApp(ChaerokApp(
    // [숨김] store: store,
    // [숨김] device: device,
    // [숨김] list: list,
    // [숨김] changed: ChangeSignal(paths.changed),
    // [숨김] sentClipFile: paths.sentClip,
    // [숨김] recorder: DeviceRecorder(),
    plans: plans,
    // [숨김] planFirst: true,
  ));
}

class ChaerokApp extends StatelessWidget {
  const ChaerokApp({
    super.key,
    // [숨김] required this.store,
    // [숨김] required this.device,
    // [숨김] this.list,
    // [숨김] this.changed,
    // [숨김] this.sentClipFile,
    // [숨김] this.recorder,
    required this.plans,
    // [숨김] this.planFirst = false,
  });

  // [숨김] /// 켜자마자 계획 화면을 연다 — [PasteScreen.planFirst].
  // [숨김] final bool planFirst;

  /// F-016 계획 — 첫 화면이자 설정 화면의 내용.
  final PlanStore plans;

  // [숨김] /// F-029 화면에서 저장했을 때 쓰는 신호(목록이 위에 열려 있으면 새로 고친다).
  // [숨김] final ChangeSignal? changed;
  // [숨김]
  // [숨김] /// F-010 목록 — null이면 메뉴에 '목록'이 없다(테스트).
  // [숨김] final CollectionDeps? list;
  // [숨김] final PhoneStore store;
  // [숨김] final File? sentClipFile;
  // [숨김] final Recorder? recorder;
  // [숨김] final Device device;

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
        // [숨김] openList: list == null ? null : (c) => _push(c, CollectionScreen(deps: list!)),
        openSettings: (c) => _push(c, SettingsScreen(plans: plans)),
        showPaste: false, // [숨김] 붙여넣기 항목
        child: guardTextScale(ctx, child),
      ),
      home: PlanScreen(store: plans),
      // [숨김] home: PasteScreen(
      // [숨김]   store: store,
      // [숨김]   device: device,
      // [숨김]   changed: changed,
      // [숨김]   sentClipFile: sentClipFile,
      // [숨김]   recorder: recorder,
      // [숨김]   planFirst: planFirst,
      // [숨김]   onOpenPlan: plans == null ? null : (c) => _push(c, PlanScreen(store: plans!)),
      // [숨김] ),
    );
  }

  static void _push(BuildContext c, Widget page) =>
      Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => page));
}
