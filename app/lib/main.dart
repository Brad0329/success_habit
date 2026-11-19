import 'package:flutter/material.dart';

import 'log.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 로그 파일(initLog)은 앱 files 폴더를 받는 Phase 003에서 잇는다 — 그 전의 로그는 콘솔(adb logcat)에만 간다.
  FlutterError.onError = (d) {
    logError('Flutter 오류', d.exception, d.stack);
    FlutterError.presentError(d);
  };
  runApp(const ChaerokApp());
}

class ChaerokApp extends StatelessWidget {
  const ChaerokApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '채록',
      theme: chaerokTheme(Brightness.light),
      darkTheme: chaerokTheme(Brightness.dark),
      builder: guardTextScale,
      home: const _EmptyHome(),
    );
  }
}

/// Phase 002 빈 앱의 자리 표시 — Phase 003에서 붙여넣기 화면으로 바뀐다.
class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('채록')),
      body: const Center(child: Text('준비 중')),
    );
  }
}
