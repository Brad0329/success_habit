// F-101 도움말 — 맨 끝 제작자·버전, 버전 상수와 pubspec 대조, 본문에 꼭 있어야 할 두 가지. 글 모양은 사용자 실테스트.
import 'dart:io';

import 'package:chaerok/app_version.dart';
import 'package:chaerok/help_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('버전 상수 = pubspec.yaml version (올리고 상수를 안 고치면 실패)', () {
    final m = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(m, isNotNull, reason: 'pubspec.yaml에서 version 줄을 찾지 못함');
    expect(appVersion, m!.group(1));
  });

  test('버전 표시: 1.0.0+1 → "버전 1.0.0 (1)", 빌드 번호 없으면 "버전 1.0.0"', () {
    expect(versionLabel('1.0.0+1'), '버전 1.0.0 (1)');
    expect(versionLabel('1.0.0'), '버전 1.0.0');
  });

  testWidgets('화면: 마지막 두 글 = 제작자 한 줄 · 버전, 본문에 Atomic Habits와 데이터 경고', (t) async {
    t.view.physicalSize = const Size(800, 20000); // 전부 그려지게(ListView가 화면 밖을 안 그리면 마지막 글을 못 센다)
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: HelpScreen()));
    final texts = [
      for (final w in t.widgetList<Text>(find.descendant(of: find.byType(ListView), matching: find.byType(Text)))) w.data ?? '',
    ];
    expect(texts.sublist(texts.length - 2), ['이 앱은 Brad 2.0 이 제작했습니다.', versionLabel(appVersion)]);
    expect(texts.where((s) => s.contains('Atomic Habits')).length, 1);
    expect(texts.where((s) => s.contains('앱을 지우거나 폰을 바꾸면')).length, 1);
    expect(texts.where((s) => s.trim().isNotEmpty).length, greaterThan(40)); // 절 9개 · 문단 30여 개가 다 그려졌다
  });
}
