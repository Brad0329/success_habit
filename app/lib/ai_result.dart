/// F-011 덧붙임 파일 — 원본 옆 AI 분류 결과 `<base>.ai-<YYYYMMDD-HHMMSS>.json`(role=ai)과
/// 사용자 수정 `<base>.user-<YYYYMMDD-HHMMSS>.json`(role=user). 결정: docs/SCHEMA.md 변경 이력 2026-11-03.
///
/// 고치지 않고 매번 새 파일을 만든다(원본 불변 규칙) — 종류마다 이름이 가장 늦은 것을 쓰고, user가 ai보다 우선.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'log.dart';
import 'phone_store.dart';

/// 짝짓기 꼬리(점 포함 — `.meta.json`처럼 `<base>.` 뒤).
final aiTailRe = RegExp(r'^ai-\d{8}-\d{6}\.json$');
final userTailRe = RegExp(r'^user-\d{8}-\d{6}\.json$');

const aiSchemaVersion = 1;
const userSchemaVersion = 1;

String _two(int n) => n.toString().padLeft(2, '0');

/// `YYYYMMDD-HHMMSS`(기기 현지 시각).
String resultStamp(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}${_two(t.month)}${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

String aiFileName(String base, DateTime at) => '$base.ai-${resultStamp(at)}.json';
String userFileName(String base, DateTime at) => '$base.user-${resultStamp(at)}.json';

/// F-014 자막 파일(SCHEMA 2026-11-05) — 같은 덧붙임 꼴이라 여기 둔다(짝짓기가 collection.dart에서 읽는다).
final transcriptTailRe = RegExp(r'^transcript-\d{8}-\d{6}\.json$');
String transcriptFileName(String base, DateTime at) => '$base.transcript-${resultStamp(at)}.json';

/// 이름이 가장 늦은 것. 여럿이면 로그 1줄(본문 없이 base·건수만).
StoreEntry? latestResult(List<StoreEntry> files, {required String base, required String what}) {
  if (files.isEmpty) return null;
  final sorted = [...files]..sort((a, b) => b.name.compareTo(a.name));
  if (files.length > 1) logInfo('목록: $base의 $what 파일 ${files.length}개 — 가장 늦은 것을 씀');
  return sorted.first;
}

/// 화면이 문자열로 읽는 항목 — 타입이 틀리면 깨진 파일로 본다.
const _stringKeys = ['category', 'title', 'summary', 'description', 'extracted_text'];

/// 결과 파일 내용을 읽는다. 깨졌으면 로그 1줄 + null(그 수집물은 결과 없이 보인다 — 원본 목록은 지키고, 다시 받지 않는다).
Map<String, Object?>? parseResult(Uint8List data, {required String base, required String what}) {
  try {
    final j = jsonDecode(utf8.decode(data));
    if (j is! Map<String, Object?>) throw const FormatException('객체가 아님');
    for (final k in _stringKeys) {
      final v = j[k];
      if (v != null && v is! String) throw FormatException('$k가 문자열이 아님');
    }
    return j;
  } on FormatException catch (e) {
    logWarn('목록: 깨진 $what 파일 $base: ${e.message}');
    return null;
  }
}
