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
import 'platform.dart';
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
  runApp(ChaerokApp(
    store: store,
    device: device,
    list: list,
    changed: ChangeSignal(paths.changed),
    sentClipFile: paths.sentClip,
    recorder: DeviceRecorder(),
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
  });

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
        openList: list == null ? null : (c) => _push(c, CollectionScreen(deps: list!)),
        child: guardTextScale(ctx, child),
      ),
      home: PasteScreen(
          store: store, device: device, changed: changed, sentClipFile: sentClipFile, recorder: recorder),
    );
  }

  static void _push(BuildContext c, Widget page) =>
      Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => page));
}
