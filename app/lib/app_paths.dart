/// 앱 files 폴더 안 저장 위치 — 이름을 한 곳에서만 조합한다.
/// 이름의 근거는 docs/SCHEMA.md '폰 안의 폴더 나무'. 이름을 바꾸면 폰에 쌓인 계획을 못 읽는다(`app_paths_test`가 고정).
library;

import 'dart:io';

class AppPaths {
  const AppPaths(this.root);

  /// 앱 files 폴더 경로.
  final String root;

  /// 계획(`plans.json`)·하루 평가(`reviews.json`).
  Directory get plans => Directory('$root/plans');
}
