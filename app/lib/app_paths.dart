/// 앱 files 폴더 안 저장 위치 — Dart 안에서는 이름을 여기 한 곳에서만 조합한다(위젯 요약 이름은 Kotlin `PlanWidget`도 쓴다 — `widget_contract_test`가 대조).
/// 이름의 근거는 docs/SCHEMA.md '폰 안의 폴더 나무'. 이름을 바꾸면 폰에 쌓인 계획을 못 읽는다(`app_paths_test`가 고정).
library;

import 'dart:io';

class AppPaths {
  const AppPaths(this.root);

  /// 앱 files 폴더 경로.
  final String root;

  /// 계획(`plans.json`)·하루 평가(`reviews.json`).
  Directory get plans => Directory('$root/plans');

  /// F-102 홈 화면 위젯 요약(산출물). 위젯(Kotlin `PlanWidget`)이 같은 이름을 읽는다.
  File get widgetSummary => File('$root/widget/today.json');
}
