// R1(2026-11-15) 위젯 테스트의 진짜 I/O 대기는 `io_settle.dart`의 settleIo·settleUntil로만 —
// 손으로 쓴 `runAsync(() => Future<void>.delayed(…))`(+ 횟수 루프)가 같은 함정을 4회 더 밟게 했다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final handWait = RegExp(r'runAsync\(\s*\(\)\s*=>\s*Future(<void>)?\.delayed');

/// 위반 줄 목록 "파일:줄".
List<String> handWaits(Directory dir) => [
      for (final f in dir.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && !f.path.endsWith('io_settle.dart') && !f.path.endsWith('io_settle_guard_test.dart'))
          for (final (i, line) in f.readAsLinesSync().indexed)
            if (handWait.hasMatch(line)) '${f.path}:${i + 1}',
    ];

void main() {
  test('테스트 파일에 손으로 쓴 진짜 대기 0곳(settleIo·settleUntil을 쓴다)', () {
    expect(handWaits(Directory('test')), isEmpty);
  });

  test('검사기가 손 대기를 잡는다(한 줄·공백 변형)', () {
    expect(handWait.hasMatch('await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));'), isTrue);
    expect(handWait.hasMatch('await t.runAsync( () =>  Future.delayed(d));'), isTrue);
    expect(handWait.hasMatch('await settleIo(t);'), isFalse);
  });
}
