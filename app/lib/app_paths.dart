/// 앱 files 폴더 안 저장 위치 — 화면·공유 엔진·백그라운드 작업이 같은 이름을 쓰게 한 곳에서
/// (기존판 D6 2026-11-15: 같은 경로 글자를 세 파일이 따로 조합했다 — 한쪽만 바꾸면 화면과 작업이 다른 파일을 본다).
/// 이름의 근거는 docs/SCHEMA.md '폰 안의 폴더 나무'. 지금은 사용자 데이터 폴더뿐이고, 산출물 위치는 쓰는 기능과 함께 넣는다.
library;

import 'dart:io';

class AppPaths {
  const AppPaths(this.root);

  /// 앱 files 폴더 경로.
  final String root;

  /// 수집물 — 그 아래 `YYYY-MM/`.
  Directory get records => Directory('$root/records');
  Directory get chat => Directory('$root/chat');
  Directory get plans => Directory('$root/plans');
  Directory get memorize => Directory('$root/memorize');
  Directory get settings => Directory('$root/settings');
}
