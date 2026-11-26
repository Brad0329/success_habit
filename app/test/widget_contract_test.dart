// F-102 위젯 계약 — 같은 이름이 Dart(쓰는 쪽)와 Kotlin(읽는 쪽)에 따로 적혀 있다(CLAUDE.md '같은 규칙이 두 곳 이상').
// 파일 위치·Kotlin이 읽는 JSON 키·채널 메서드 이름이 어긋나면 위젯이 조용히 빈 모양이 된다 — 여기서 잡는다.
import 'dart:io';

import 'package:chaerok/app_paths.dart';
import 'package:chaerok/plans.dart';
import 'package:chaerok/widget_summary.dart';
import 'package:flutter_test/flutter_test.dart';

const _kt = 'android/app/src/main/kotlin/com/brad0329/chaerok/phone';

/// 요약 JSON에 나올 수 있는 키 전부(바깥 키 + do/dont 안 키).
Set<String> _keys(Map<String, Object?> m) => {
      for (final e in m.entries) ...[e.key, if (e.value is Map) ...(e.value! as Map).keys.cast<String>()],
    };

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chaerok_widget_contract'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('위젯이 읽는 파일 위치 = 앱이 쓰는 위치', () {
    final kt = File('$_kt/PlanWidget.kt').readAsStringSync();
    final dart = const AppPaths('/f').widgetSummary.path.substring('/f/'.length);
    expect(RegExp(r'File\(context\.filesDir, "([^"]+)"\)').firstMatch(kt)?.group(1), dart);
  });

  test('위젯(Kotlin)이 읽는 JSON 키는 모두 앱(Dart)이 쓰는 키다', () async {
    final s = PlanStore(tmp, now: () => DateTime(2026, 10, 8));
    await s.saveItems([(null, '운동', PlanKind.doIt), (null, '야식', PlanKind.dont)], DateTime(2026, 10, 8));
    final written = {
      ..._keys(widgetSummary(s, DateTime(2026, 10, 8))),
      ..._keys(widgetSummary(s, DateTime(2026, 10, 1))), // empty 모양
    };
    final kt = File('$_kt/PlanWidget.kt').readAsStringSync();
    final read = {for (final m in RegExp(r'\b(?:opt\w*|str)\("(\w+)"').allMatches(kt)) m.group(1)!};
    expect(read.length, greaterThanOrEqualTo(8), reason: '정규식이 비어 통과하지 않게');
    expect(read.difference(written), isEmpty, reason: 'Kotlin이 읽는데 Dart가 안 쓰는 키');
  });

  test("채널 메서드 'refreshWidget' — Dart가 부르는 이름을 MainActivity가 받는다", () {
    expect(File('lib/widget_summary.dart').readAsStringSync(), contains("invokeMethod<void>('refreshWidget')"));
    expect(File('$_kt/MainActivity.kt').readAsStringSync(), contains('"refreshWidget" ->'));
  });
}
