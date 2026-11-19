// 앱이 파일을 쓰는 곳 등록부 — 새 쓰기 지점이 생기면 여기서 실패한다(기존판 debt-audit 2026-11-04 R1).
//
// 왜: 기존판에서 '두 쓰기 주체가 같은 상태 파일을 고침'이 3번 났고 문서로는 안 막혔다. 이 앱은 쓰는 주체가 셋이다
// (plan.md '실행 주체 셋': 메인 화면 엔진 / 공유 엔진 / 백그라운드 분류 작업). 그래서 쓰기 지점마다 "누가 쓰나"를 정해 적게 하고,
// 둘 이상이 쓰면 그 경합을 재현하는 테스트 이름을 요구한다.
//
// 새 쓰기를 넣었으면: 그 파일을 누가 쓰는지 정해 아래에 적는다.
// 'multi'면 동시에 쓸 때를 재현하는 테스트(실패를 먼저 본 것)의 이름을 적는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 직접 쓰기 + 바꿔치기 도우미(`atomic_file.dart`) 부르기. 도우미 파일 자체는 쓰는 주체가 아니라 뺀다.
final _writeCall = RegExp(r'\.(writeAsString|writeAsBytes)(Sync)?\(|\bwriteAtomic(Sync)?\(');
const _helper = 'atomic_file.dart';

/// lib 파일 → (쓰기 호출 수, 쓰는 주체, 근거).
/// 쓰는 주체: ui = 메인 화면 엔진만 / share = 공유 엔진만 / bg = 백그라운드 작업만 / multi = 둘 이상.
const registry = <String, (int, String, String)>{
  'log.dart': (1, 'multi', '덧붙이기(append)만 — 줄이 섞일 뿐 내용을 덮지 않는다'),
  'phone_store.dart': (
    1,
    'multi',
    '화면·공유 엔진이 쓴다 — 건마다 base(수집 ID)가 달라 서로 다른 파일이고 같은 이름이 있으면 거부한다. '
        "phone_store_test '공유 엔진과 화면이 번갈아 저장해도'·'같은 이름이 이미 있으면'",
  ),
  'change_signal.dart': (
    1,
    'multi',
    "화면·공유 엔진이 쓴다 — 값은 시각 하나라 마지막 것만 남아도 된다(바꿔치기 아님, SCHEMA 원칙 6 예외). change_signal_test '두 주체가 번갈아 써도'",
  ),
  'paste_screen.dart': (1, 'ui', '채운 클립보드의 MD5(sent_clip.md5) — 붙여넣기 화면만'),
};

void main() {
  test('파일을 쓰는 lib 파일과 호출 수가 등록부와 같다', () {
    final found = <String, int>{};
    for (final f in Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final n = _writeCall.allMatches(f.readAsStringSync()).length;
      final name = f.uri.pathSegments.last;
      if (n > 0 && name != _helper) found[name] = n;
    }
    // 정규식이 비어 '통과'하지 않게 건수를 건다 — 쓰는 파일을 옮겨 올 때마다 이 하한을 올린다.
    expect(found.length, greaterThanOrEqualTo(4));
    expect(found, {for (final e in registry.entries) e.key: e.value.$1},
        reason: '새 파일 쓰기가 생겼거나 사라졌다 — 누가 쓰는지 정해 registry에 적을 것(머리말)');
  });

  test("'multi'인 곳은 근거에 경합 테스트·선점·덧붙이기 중 하나를 적었다", () {
    for (final e in registry.entries.where((e) => e.value.$2 == 'multi')) {
      expect(e.value.$3, contains(RegExp(r'append|_test|선점')), reason: e.key);
    }
  });
}
