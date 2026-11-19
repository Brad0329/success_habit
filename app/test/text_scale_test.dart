// 글자 크기 계산 고장 우회 — 공유 화면 엔진이 같은 프로세스에 뜬 뒤 메인 화면의 새 글자가 안 그려지던 것(기존판 2026-11-03).
// 원인: 안드로이드 SettingsChannel의 설정 대기열이 엔진끼리 공유(static)라, 다른 엔진이 메인 엔진의 설정을 지운다.
// 디버그 빌드에서는 그 뒤 글자 크기 계산이 AssertionError를 던져 화면이 통째로 안 그려졌다.
import 'dart:io';

import 'package:chaerok/log.dart';
import 'package:chaerok/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 엔진이 메인 화면의 설정을 잃은 상태 — 디버그 빌드의 실제 오류 문구 그대로.
class _BrokenScaler extends TextScaler {
  const _BrokenScaler();

  @override
  double scale(double fontSize) => throw AssertionError('Flutter Error: incorrect configuration id: -2147483648.');

  @override
  double get textScaleFactor => 1.5;
}

void main() {
  testWidgets('엔진의 글자 크기 계산이 고장 나도 화면이 그려지고, 시스템 배율(1.5)로 대신 계산한다', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final tmp = Directory.systemTemp.createTempSync('chaerok_scale');
    addTearDown(() => tmp.deleteSync(recursive: true));
    initLog(tmp); // 대신 계산했다는 로그가 여기에 남는다
    // 로그는 콘솔에도 스택(120줄)째 찍힌다 — 테스트 출력에서만 끄고, 남았는지는 아래에서 파일로 본다.
    // (테스트 본문이 끝나기 전에 되돌려야 한다 — 프레임워크가 본문 끝에서 debugPrint가 바뀌었는지 검사한다.)
    final print = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};

    await t.pumpWidget(MediaQuery(
      data: MediaQueryData.fromView(t.view).copyWith(textScaler: const _BrokenScaler()),
      child: const ChaerokApp(),
    ));
    await t.pumpAndSettle();
    debugPrint = print;

    expect(t.takeException(), isNull);
    expect(MediaQuery.textScalerOf(t.element(find.byType(Scaffold))).scale(10), 15);
    // 조용히 넘어가지 않는다 — 대신 계산했다는 사실이 로그 파일에 한 번 남는다.
    final log = File('${tmp.path}/chaerok.log').readAsStringSync();
    expect('글자 크기 계산 실패'.allMatches(log).length, 1);
  });
}
