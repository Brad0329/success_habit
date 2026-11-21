// app/lib의 catch 블록 검사 — CLAUDE.md 'Silent failure 절대 금지'를 구조로(기존판 debt-audit 2026-11-04 R2).
//
// 왜: 빈 catch는 flutter_lints(empty_catches)가 잡지만, 기존판에서 실제로 난 것은 빈 catch가 아니었다 —
// ① catch 안에서 부른 알림이 다시 던져 작업이 알림·로그 없이 FAILED로 끝남 ② 로그 없이 넘어가는 폴백.
// 규칙: catch 블록은 로그(logWarn·logError·logInfo)·다시 던지기·이유 주석(//) 중 하나를 담는다.
//       (알림 호출 규칙은 알림이 있는 M채록 쪽에만 남았다 — 이 앱은 알림을 쓰지 않는다.)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// try의 닫는 } 뒤에 오는 `on X {` · `on X catch (e) {` · `catch (e) {`
final _catchHead = RegExp(r'\}\s*(?:on\s+[\w<>?.]+(?:\s+catch\s*\([^)]*\))?|catch\s*\([^)]*\))\s*\{');
// debugPrint = log.dart 자신(로그 파일을 못 쓸 때 로그 함수는 못 부른다)
final _handled = RegExp(r'log(?:Warn|Error|Info)\(|\brethrow\b|\bthrow\b|//|debugPrint\(');

/// (파일:줄, 블록 본문) 목록.
List<(String, String)> _catchBlocks() {
  final out = <(String, String)>[];
  for (final f in Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    final src = f.readAsStringSync();
    for (final m in _catchHead.allMatches(src)) {
      var i = m.end, depth = 1;
      while (depth > 0 && i < src.length) {
        final c = src[i++];
        if (c == '{') depth++;
        if (c == '}') depth--;
      }
      final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
      out.add(('${f.uri.pathSegments.last}:$line', src.substring(m.end, i - 1)));
    }
  }
  return out;
}

void main() {
  final blocks = _catchBlocks();

  test('catch 블록을 실제로 찾는다(정규식이 비어 통과하지 않게)', () {
    // 수집·목록이 갈라져 나간 뒤(2026-11-21) lib의 catch는 18곳 남짓.
    expect(blocks.length, greaterThanOrEqualTo(15));
  });

  test('모든 catch 블록이 로그·다시 던지기·이유 주석 중 하나를 담는다', () {
    final silent = [for (final (at, body) in blocks) if (!_handled.hasMatch(body)) at];
    expect(silent, isEmpty, reason: '로그도 주석도 없이 넘어가는 catch — 로그를 남기거나 넘어가는 이유를 주석으로');
  });
}
