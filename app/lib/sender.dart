/// 수집 → 수집물(원본 + 사이드카) 만들기 (F-035). 기존판 sender.dart에서 업로드·임시 보관·MD5 대조를 걷어낸 것 —
/// 폰에 쓰는 것이 곧 저장이라 만든 것을 `phone_store.dart`의 [PhoneStore.save]에 바로 넘긴다.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'record.dart' as record;

const device = 'phone';

/// 저장할 수집물 하나 — 사이드카와 나무에 쓸 두 파일 이름.
class NewRecord {
  NewRecord(this.sidecar, this.originalName, this.metaName);

  final Map<String, Object?> sidecar;
  final String originalName; // `<base>.<확장자>`
  final String metaName; // `<base>.meta.json`

  String get id => sidecar['id'] as String;
  String get base => metaName.substring(0, metaName.length - '.meta.json'.length);
}

/// 앱 안 녹음 → 수집물(F-007). 원래 파일 이름은 없다(앱이 만든 녹음).
(NewRecord, Uint8List) prepareVoice(Uint8List data, String mime) =>
    prepare(data, input: 'voice', kind: 'file', source: null, originalName: null, mime: mime);

/// 붙여넣기 텍스트 → 수집물. 비었으면 record.EmptyTextError. 텍스트는 고치지 않고 그대로 저장한다.
(NewRecord, Uint8List) preparePaste(String text) {
  final kind = record.classifyText(text);
  return prepare(Uint8List.fromList(utf8.encode(text)),
      input: 'paste', kind: kind, source: null, originalName: null, mime: record.textMime);
}

(NewRecord, Uint8List) prepare(
  Uint8List data, {
  required String input,
  required String kind,
  required String? source,
  required String? originalName,
  required String mime,
  String? caption,
  String? groupId,
  int? groupSize,
}) {
  final id = record.newId();
  final at = record.nowLocal();
  final sidecar = record.buildSidecar(
    recordId: id, collectedAt: at, input: input, kind: kind, source: source, device: device,
    originalName: originalName, mime: mime, data: data, caption: caption,
    groupId: groupId, groupSize: groupSize,
  );
  final names = record.fileNames(at, id, record.extensionFor(kind, originalName, mime));
  return (NewRecord(sidecar, names.$1, names.$2), data);
}

Uint8List sidecarBytes(Map<String, Object?> sidecar) =>
    Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(sidecar)));
