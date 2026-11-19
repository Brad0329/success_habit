import 'dart:io';

import 'package:flutter/material.dart';

import 'app_menu.dart';
import 'app_paths.dart';
import 'change_signal.dart';
import 'collection_list.dart';
import 'collection_screen.dart';
import 'log.dart';
import 'paste_screen.dart';
import 'phone_store.dart';
import 'plan_screen.dart';
import 'plans.dart';
import 'platform.dart';
import 'settings_screen.dart';
import 'share_entry.dart';
import 'theme.dart';
import 'voice.dart';

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
  final store = PhoneStore(paths.records);
  final list = CollectionDeps(
    collection: Collection(reader: () => store, deleter: () => store),
    openUrl: device.openUrl!,
    openBytes: device.openBytes!,
    changed: ChangeSignal(paths.changed),
  );
  // 계획 화면·설정 편집이 같은 것을 써야 한쪽에서 바꾼 것이 다른 쪽에 바로 보인다.
  final plans = PlanStore(paths.plans);
  try {
    await plans.splitFromToday(DateTime.now()); // F-031 나누기 전 목록이면 오늘부터 평일·주말로
  } on Object catch (e, st) {
    // 앱은 계속 띄운다 — 나누기 전 목록으로 보이고, 다음 저장이 나눈 칸을 쓴다.
    logError('계획 평일·주말 나누기 실패', e, st);
  }
  runApp(ChaerokApp(
    store: store,
    device: device,
    list: list,
    changed: ChangeSignal(paths.changed),
    sentClipFile: paths.sentClip,
    recorder: DeviceRecorder(),
    plans: plans,
    planFirst: true,
  ));
}

class ChaerokApp extends StatelessWidget {
  const ChaerokApp({
    super.key,
    required this.store,
    required this.device,
    this.list,
    this.changed,
    this.sentClipFile,
    this.recorder,
    this.plans,
    this.planFirst = false,
  });

  /// 켜자마자 계획 화면을 연다([plans]가 null이 아닐 때 — 계획이 비어 있어도 연다) — [PasteScreen.planFirst].
  final bool planFirst;

  /// F-016 계획 — null이면 메뉴에 '계획'·'설정'이 없다(테스트).
  final PlanStore? plans;

  /// F-029 화면에서 저장했을 때 쓰는 신호(목록이 위에 열려 있으면 새로 고친다).
  final ChangeSignal? changed;

  /// F-010 목록 — null이면 메뉴에 '목록'이 없다(테스트).
  final CollectionDeps? list;
  final PhoneStore store;
  final File? sentClipFile;
  final Recorder? recorder;
  final Device device;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '채록',
      theme: chaerokTheme(Brightness.light),
      darkTheme: chaerokTheme(Brightness.dark),
      // F-017 ⋯ 메뉴 — Navigator 바깥에 두어 쌓인 모든 화면이 찾는다.
      builder: (ctx, child) => AppNav(
        openPlan: plans == null ? null : (c) => _push(c, PlanScreen(store: plans!)),
        openList: list == null ? null : (c) => _push(c, CollectionScreen(deps: list!)),
        // Phase 004의 설정 화면은 계획 줄뿐이라 계획이 있을 때만 연다.
        openSettings: plans == null ? null : (c) => _push(c, SettingsScreen(plans: plans!)),
        child: guardTextScale(ctx, child),
      ),
      home: PasteScreen(
        store: store,
        device: device,
        changed: changed,
        sentClipFile: sentClipFile,
        recorder: recorder,
        planFirst: planFirst,
        onOpenPlan: plans == null ? null : (c) => _push(c, PlanScreen(store: plans!)),
      ),
    );
  }

  static void _push(BuildContext c, Widget page) =>
      Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => page));
}
