// R1(2026-11-15 부채 정리) 위젯 테스트(가짜 시계) 안에서 진짜 파일 I/O를 기다리는 곳은 이 파일의 두 함수뿐이다.
// 가짜 시계는 진짜 I/O를 못 기다려 그냥 await하면 타임아웃까지 매달리고(팩_Flutter_Android '테스트'),
// 횟수를 정한 손 루프(진짜 대기 + pump × N)는 느린 실행에서 간헐로 실패한다(setup_test 8068428).
// `io_settle_guard_test.dart`가 다른 테스트 파일의 `runAsync(() => Future<void>.delayed(…))` 직접 쓰기를 막는다.
import 'package:flutter_test/flutter_test.dart';

/// 진짜 시간을 [wait]만큼 흘린 뒤 화면을 맞춘다 — 화면이 연 파일 읽기·쓰기 한 번을 기다릴 때.
Future<void> settleIo(WidgetTester t, {Duration wait = const Duration(milliseconds: 50)}) async {
  await t.runAsync(() => Future<void>.delayed(wait));
  await t.pumpAndSettle();
}

/// [finder]가 보일 때까지 진짜 대기와 pump를 번갈아 한다 — 횟수가 아니라 조건으로 끝난다.
/// [limit] 안에 안 보이면 실패로 던진다(조용히 넘어가지 않는다). 보인 뒤 한 번 더 [settleIo] — 열린 파일이 닫히게.
Future<void> settleUntil(WidgetTester t, Finder finder, {Duration limit = const Duration(seconds: 10)}) async {
  final sw = Stopwatch()..start();
  while (finder.evaluate().isEmpty) {
    if (sw.elapsed > limit) throw TestFailure('settleUntil: ${limit.inSeconds}초 안에 안 보임 — $finder');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
  await settleIo(t);
}
