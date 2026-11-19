/// F-029 목록 자동 갱신 신호 — 수집물을 저장한 쪽(화면·공유 엔진, Phase 005부터 분류 작업)이 폰 안 파일 하나에 시각을 쓰고,
/// 열려 있는 목록 화면이 몇 초마다 그 파일만 읽어 값이 바뀌었으면 새로 고친다.
/// 파일은 산출물이다 — 없거나 깨져도 "바뀜 아님"으로 보고 넘어간다(그 사실은 로그에).
library;

import 'dart:io';

import 'log.dart';

class ChangeSignal {
  ChangeSignal(this.file);
  final File file;

  /// 마지막으로 본 값([start]·[changed]가 갱신).
  String? _seen;

  /// 저장한 쪽 — 지금 시각을 쓴다. 실패는 로그만(저장 결과는 그대로, 목록은 다음 새로 고침에 보인다).
  void mark(DateTime now) {
    try {
      file.writeAsStringSync('${now.microsecondsSinceEpoch}', flush: true);
    } on Object catch (e, st) {
      logError('목록 갱신 신호를 쓰지 못함(목록은 새로 고침 때 보인다)', e, st);
    }
  }

  String? _read() {
    try {
      return file.existsSync() ? file.readAsStringSync() : null;
    } on Object catch (e) {
      logWarn('목록 갱신 신호를 읽지 못함 — 바뀜 아님으로 봄: ${e.runtimeType}');
      return null;
    }
  }

  /// 목록 화면 쪽 — 들어올 때 기준값만 잡는다(들어오며 이미 새로 고친다).
  void start() => _seen = _read();

  /// 기준값과 다른 값이 쓰였으면 true 한 번(기준을 그 값으로 옮긴다). 파일 없음·같은 값 → false.
  bool changed() {
    final v = _read();
    if (v == null || v == _seen) return false;
    _seen = v;
    return true;
  }
}
