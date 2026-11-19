// R2(2026-11-15) 창(showDialog·showModalBottomSheet)을 연 함수 안 지역 TextEditingController를 창이 닫히자마자
// dispose하면, 닫히는 애니메이션 동안 창이 그것을 계속 써서 빨간 화면(74e90de·086ae60, 2회).
// 처방: 입력 칸이 있는 창은 자기 State 위젯으로 빼고 컨트롤러는 그 State의 필드로(dispose는 창이 다 닫힌 뒤).
// 이 검사는 lib에서 함수 안 지역 컨트롤러 선언(들여쓰기 4칸 이상의 final·var)을 0으로 지킨다 — State 필드(2칸)는 된다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final localController = RegExp(r'^ {4,}(final|var|late final)\s+\w+\s*=\s*TextEditingController\(');

List<String> localControllers(Directory dir) => [
      for (final f in dir.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart'))
          for (final (i, line) in f.readAsLinesSync().indexed)
            if (localController.hasMatch(line)) '${f.path}:${i + 1}',
    ];

void main() {
  test('lib에 함수 안 지역 TextEditingController 0곳(창은 자기 State 위젯으로)', () {
    expect(localControllers(Directory('lib')), isEmpty);
  });

  test('검사기: 함수 안 지역 선언은 잡고 State 필드는 넘긴다', () {
    expect(localController.hasMatch("    final c = TextEditingController(text: '');"), isTrue);
    expect(localController.hasMatch('      var c = TextEditingController();'), isTrue);
    expect(localController.hasMatch('  final _c = TextEditingController();'), isFalse);
    expect(localController.hasMatch('  late final _c = TextEditingController(text: widget.initial);'), isFalse);
  });
}
