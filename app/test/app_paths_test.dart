// 저장 위치 이름 고정 — 폰에 쌓이는 사용자 데이터 위치라 이름을 바꾸면 기존 것을 못 읽는다(기존판 D6 2026-11-15).
// 이름의 근거는 docs/SCHEMA.md '폰 안의 폴더 나무'. 위치를 더하면 여기에도 더한다.
// widget/today.json은 사용자 데이터가 아니라 산출물 — 고정하는 이유는 Kotlin 위젯이 같은 이름을 읽어서다.
import 'dart:io';

import 'package:chaerok/app_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('files 폴더 안 저장 위치 이름이 그대로다(바꾸면 옛 데이터를 못 읽음)', () {
    expect(const AppPaths('/f').plans.path, '/f/plans');
    expect(const AppPaths('/f').widgetSummary.path, '/f/widget/today.json');
    expect(planFileName, 'plans.json');
    expect(reviewFileName, 'reviews.json');
    expect(logFileName, 'chaerok.log');
  });

  test('저장 파일 이름은 app_paths.dart에서만 적는다(Phase 007 B10 — 다른 파일이 조합하면 여기 고정이 안 걸린다)', () {
    final literal = RegExp(r"[/'](plans\.json|reviews\.json|chaerok\.log)'");
    final hits = <String>[];
    for (final f in Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final (k, line) in f.readAsLinesSync().indexed) {
        if (line.trimLeft().startsWith('//')) continue; // 주석의 설명은 괜찮다
        if (literal.hasMatch(line)) hits.add('${f.uri.pathSegments.last}:${k + 1}');
      }
    }
    expect(hits.length, 3, reason: '$hits');
    expect(hits.every((h) => h.startsWith('app_paths.dart:')), isTrue, reason: '$hits');
  });
}
