// 저장 위치 이름 고정 — 폰에 쌓이는 사용자 데이터 위치라 이름을 바꾸면 기존 것을 못 읽는다(기존판 D6 2026-11-15).
// 이름의 근거는 docs/SCHEMA.md '폰 안의 폴더 나무'. 위치를 더하면 여기에도 더한다.
import 'package:chaerok/app_paths.dart';
import 'package:chaerok/phone_store.dart' show recordsFolder;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('files 폴더 안 저장 위치 이름이 그대로다(바꾸면 옛 데이터를 못 읽음)', () {
    const p = AppPaths('/f');
    expect(
      [p.records.path, p.chat.path, p.plans.path, p.memorize.path, p.settings.path],
      ['/f/records', '/f/chat', '/f/plans', '/f/memorize', '/f/settings'],
    );
    expect(
      [p.sentClip.path, p.changed.path],
      ['/f/sent_clip.md5', '/f/changed.txt'],
    );
  });

  test('수집물 나무 안 상대 경로의 첫 조각이 저장 위치 이름과 같다', () {
    expect(const AppPaths('/f').records.path, '/f/$recordsFolder');
  });
}
