/// F-001 저장 규칙 — 파일 이름·확장자·종류 판정·사이드카.
///
/// 기존판(폰 + PC)에서 물려받은 규칙이다 — 기존판 형식의 파일도 그대로 읽는다. 구현은 이 파일 하나다.
/// 규칙을 바꾸면 docs/SCHEMA.md 변경 절차를 먼저 밟는다.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const schemaVersion = 1;

const inputs = ['share', 'paste', 'pc_text', 'pc_capture', 'pc_file', 'voice'];
const kinds = ['text', 'url', 'image', 'file'];

/// 사이드카 항목 순서 = docs/SCHEMA.md '사이드카 항목' 표 순서.
const sidecarKeys = [
  'schema_version', 'id', 'collected_at', 'input', 'kind', 'source',
  'device', 'original_name', 'mime', 'size', 'md5', 'caption', 'group_id', 'group_size',
];

const textMime = 'text/plain';

/// 녹음 수집물인가 — 앱 녹음(input voice) 또는 audio/* 파일. 분류·대화 맥락·목록이 같이 쓴다.
bool isVoiceMeta(Map<String, Object?> meta) =>
    meta['input'] == 'voice' || (meta['mime'] as String? ?? '').toLowerCase().startsWith('audio/');

/// 원래 파일명에 확장자가 없을 때만 쓰는 MIME → 확장자 표. 없는 MIME은 "bin".
/// 값은 record_test가 고정한다(바꾸면 같은 파일의 확장자가 달라진다).
const mimeExt = {
  'text/plain': 'txt',
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'application/pdf': 'pdf',
  'audio/mp4': 'm4a',
  'audio/mpeg': 'mp3',
  'video/mp4': 'mp4',
};
const fallbackExt = 'bin';

final _urlRe = RegExp(r'^https?://\S+$', caseSensitive: false);

/// 앞뒤에서 벗기는 공백 = 유니코드 White_Space + BOM. 기존판에서 정한 집합을 그대로 명시한다(Dart 기본 trim()과 다르다).
final Set<int> stripChars = {
  0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680,
  for (var c = 0x2000; c < 0x200B; c++) c,
  0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
};

/// 보낼 텍스트가 없다(빈 문자열 또는 공백뿐) — F-001 엣지케이스: 보내지 않고 알린다.
class EmptyTextError implements Exception {
  @override
  String toString() => 'EmptyTextError: 빈 텍스트';
}

/// 수집 ID(UUID v4). 보내는 쪽이 만든다.
String newId() {
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 기기 기준 현재 시각, 시간대 포함, 초 단위(예: 2026-10-28T14:05:31+09:00).
String nowLocal([DateTime? at]) {
  final t = at ?? DateTime.now();
  final off = t.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final m = off.inMinutes.abs();
  return '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}'
      'T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}'
      '$sign${_two(m ~/ 60)}:${_two(m % 60)}';
}

String _strip(String s) {
  final runes = s.runes.toList();
  var start = 0;
  var end = runes.length;
  while (start < end && stripChars.contains(runes[start])) {
    start++;
  }
  while (end > start && stripChars.contains(runes[end - 1])) {
    end--;
  }
  return String.fromCharCodes(runes.sublist(start, end));
}

/// 앞뒤 공백을 뺀 전체가 http(s) 주소 하나면 'url', 아니면 'text'. 비었으면 EmptyTextError.
String classifyText(String text) {
  final stripped = _strip(text);
  if (stripped.isEmpty) throw EmptyTextError();
  return _urlRe.hasMatch(stripped) ? 'url' : 'text';
}

/// 파일로 받은 것의 종류 — image/* 이면 'image', 그 외 'file'.
String kindForMime(String? mime) => (mime ?? '').toLowerCase().startsWith('image/') ? 'image' : 'file';

/// 메모가 공백뿐(stripChars)이면 null, 아니면 고치지 않고 그대로.
String? captionOrNone(String? memo) =>
    memo == null || _strip(memo).isEmpty ? null : memo;

final _safeExtRe = RegExp(r'^[A-Za-z0-9]{1,10}$');

/// 텍스트·URL은 txt, 이미지·파일은 원래 확장자(대소문자 그대로), 없거나 안전하지 않으면 MIME 표에서.
String extensionFor(String kind, String? originalName, String? mime) {
  if (kind == 'text' || kind == 'url') return 'txt';
  if (originalName != null && originalName.isNotEmpty) {
    final dot = originalName.lastIndexOf('.');
    if (dot > 0 && dot < originalName.length - 1) {
      // 확장자는 폰 파일 경로의 일부가 된다 — 영문·숫자 1~10자일 때만 그대로 쓰고, 아니면 MIME 표로 간다
      // (SCHEMA 변경 이력 2026-11-19. 원래 이름은 사이드카 original_name에 그대로 남는다).
      final ext = originalName.substring(dot + 1);
      if (_safeExtRe.hasMatch(ext)) return ext;
    }
  }
  if (mime != null) {
    return mimeExt[mime.split(';')[0].trim().toLowerCase()] ?? fallbackExt;
  }
  return fallbackExt;
}

/// 수집 시각 문자열의 현지 날짜·시각 부분(시간대 변환 안 함). DateTime.parse는 UTC로 바꿔 버려서 직접 읽는다.
final _isoRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})');

List<String> _parts(String collectedAt) {
  final m = _isoRe.firstMatch(collectedAt);
  if (m == null) throw FormatException('수집 시각 형식이 아니다', collectedAt);
  return [for (var i = 1; i <= 6; i++) m.group(i)!];
}

/// `YYYYMMDD-HHMMSS_<ID 앞 8자>` —수집 시각의 그 기기 현지 시각 기준.
String baseName(String collectedAt, String recordId) {
  final p = _parts(collectedAt);
  return '${p[0]}${p[1]}${p[2]}-${p[3]}${p[4]}${p[5]}_${recordId.substring(0, 8)}';
}

/// (원본 이름, 사이드카 이름).
(String, String) fileNames(String collectedAt, String recordId, String ext) {
  final base = baseName(collectedAt, recordId);
  return ('$base.$ext', '$base.meta.json');
}

/// 월별 폴더 이름 'YYYY-MM' — 수집 시각 기준.
String monthFolder(String collectedAt) {
  final p = _parts(collectedAt);
  return '${p[0]}-${p[1]}';
}

String md5Hex(Uint8List data) => md5.convert(data).toString();

/// SCHEMA.md 사이드카 14개 항목을 모두 채운다(값이 없으면 null → JSON null).
/// 묶음(groupId·groupSize)은 둘 다 없거나, 둘 다 있고 건수가 2 이상이어야 한다.
/// Dart Map 리터럴은 삽입 순서를 지킨다 — JSON 항목 순서가 SCHEMA.md 표와 같다.
Map<String, Object?> buildSidecar({
  required String recordId,
  required String collectedAt,
  required String input,
  required String kind,
  required String? source,
  required String device,
  required String? originalName,
  required String mime,
  required Uint8List data,
  String? caption,
  String? groupId,
  int? groupSize,
}) {
  if (!inputs.contains(input)) throw ArgumentError.value(input, 'input', '알 수 없는 input');
  if (!kinds.contains(kind)) throw ArgumentError.value(kind, 'kind', '알 수 없는 kind');
  if ((groupId == null) != (groupSize == null) || (groupSize != null && groupSize < 2)) {
    throw ArgumentError('묶음은 group_id·group_size가 함께, 건수 2 이상: $groupId / $groupSize');
  }
  String? orNull(String? s) => (s == null || s.isEmpty) ? null : s;
  final sidecar = <String, Object?>{
    'schema_version': schemaVersion,
    'id': recordId,
    'collected_at': collectedAt,
    'input': input,
    'kind': kind,
    'source': orNull(source),
    'device': device,
    'original_name': orNull(originalName),
    'mime': mime,
    'size': data.length,
    'md5': md5Hex(data),
    'caption': orNull(caption),
    'group_id': groupId,
    'group_size': groupSize,
  };
  assert(sidecar.keys.join(',') == sidecarKeys.join(','));
  return sidecar;
}
