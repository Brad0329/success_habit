// F-029 목록 자동 갱신 신호 — 감시 규칙과, 쓰는 주체가 둘(화면·공유 엔진)일 때.
import 'dart:io';

import 'package:chaerok/change_signal.dart';
import 'package:chaerok/log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late File f;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chaerok_sig');
    initLog(tmp);
    f = File('${tmp.path}/changed.txt');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('감시: 기준값과 같으면 아님, 다른 값이 쓰이면 한 번만 바뀜 / 파일 없음 → 아님', () {
    final watcher = ChangeSignal(f)..start();
    expect(watcher.changed(), isFalse); // 파일 없음
    ChangeSignal(f).mark(DateTime(2026, 11, 19, 10));
    expect(watcher.changed(), isTrue);
    expect(watcher.changed(), isFalse);
    ChangeSignal(f).mark(DateTime(2026, 11, 19, 10)); // 같은 값
    expect(watcher.changed(), isFalse);
  });

  test('들어올 때 이미 있던 신호는 기준일 뿐 바뀜이 아니다', () {
    ChangeSignal(f).mark(DateTime(2026, 11, 19, 9));
    final watcher = ChangeSignal(f)..start();
    expect(watcher.changed(), isFalse);
  });

  test('두 주체가 번갈아 써도(화면·공유 엔진) 감시는 쓰일 때마다 바뀜을 본다 — 마지막 값만 남아도 된다', () {
    final watcher = ChangeSignal(f)..start();
    final ui = ChangeSignal(f), share = ChangeSignal(f);
    ui.mark(DateTime(2026, 11, 19, 10, 0, 1));
    share.mark(DateTime(2026, 11, 19, 10, 0, 2));
    expect(watcher.changed(), isTrue);
    ui.mark(DateTime(2026, 11, 19, 10, 0, 3));
    expect(watcher.changed(), isTrue);
    expect(watcher.changed(), isFalse);
  });

  test('깨진 파일·읽을 수 없는 자리도 터지지 않고, 쓰기 실패는 로그만', () {
    f.writeAsBytesSync([0xff, 0xfe, 0x00]);
    final watcher = ChangeSignal(f)..start();
    expect(watcher.changed(), isFalse);
    final dirInPlace = File('${tmp.path}/as_dir')..parent.createSync();
    Directory(dirInPlace.path).createSync(); // 파일 자리에 폴더
    ChangeSignal(dirInPlace).mark(DateTime(2026)); // 던지지 않는다
    expect(File('${tmp.path}/chaerok.log').readAsStringSync(), contains('목록 갱신 신호를 쓰지 못함'));
  });
}
