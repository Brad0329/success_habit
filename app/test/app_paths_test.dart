// 저장 위치 이름 고정 — 폰에 쌓이는 사용자 데이터 위치라 이름을 바꾸면 기존 것을 못 읽는다(기존판 D6 2026-11-15).
// 이름의 근거는 docs/SCHEMA.md '폰 안의 폴더 나무'. 위치를 더하면 여기에도 더한다.
import 'package:chaerok/app_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('files 폴더 안 저장 위치 이름이 그대로다(바꾸면 옛 데이터를 못 읽음)', () {
    expect(const AppPaths('/f').plans.path, '/f/plans');
  });
}
