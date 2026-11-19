/// F-002 공유로 받은 것 → 수집물(F-035). 순수 로직 — 기기 쪽(복사·100MB 검사)은 ShareActivity.kt가 한다.
///
/// 규칙(REQUIREMENTS F-002): 파일마다 수집물 1건 / 파일과 함께 온 텍스트는 각 파일 사이드카의 caption /
/// 텍스트만 오면 텍스트(또는 URL) 1건 / 100MB를 넘은 파일은 저장하지 않고 이름을 돌려준다(알림용) /
/// 한 번의 공유로 2건 이상이면 모두 같은 group_id, group_size = 저장하는 건수.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'record.dart' as record;
import 'sender.dart';

const fallbackMime = 'application/octet-stream';

class SharedFile {
  const SharedFile({required this.path, this.name, this.mime, this.tooBig = false});
  final String? path; // 앱 폴더로 복사한 사본(tooBig이면 null)
  final String? name; // 원래 파일 이름(보낸 앱이 안 알려 주면 null)
  final String? mime;
  final bool tooBig;

  factory SharedFile.fromMap(Map<Object?, Object?> m) => SharedFile(
        path: m['path'] as String?,
        name: m['name'] as String?,
        mime: m['mime'] as String?,
        tooBig: m['tooBig'] == true,
      );
}

class ShareInput {
  const ShareInput({this.text, this.files = const [], this.source});
  final String? text;
  final List<SharedFile> files;
  final String? source; // 공유해 온 앱 패키지(안드로이드가 안 알려 주면 null — SCHEMA '모르면 null')

  factory ShareInput.fromMap(Map<Object?, Object?> m) => ShareInput(
        text: m['text'] as String?,
        source: m['source'] as String?,
        files: [for (final f in (m['files'] as List? ?? const [])) SharedFile.fromMap(f as Map<Object?, Object?>)],
      );
}

class ShareResult {
  ShareResult(this.items, this.tooBig, {this.empty = false});
  final List<(NewRecord, Uint8List)> items;
  final List<String> tooBig; // 저장하지 않은 파일 이름
  final bool empty; // 받은 것이 없거나 빈 텍스트뿐
}

String? _captionOf(String? text) => record.captionOrNone(text);

/// 파일이 있으면 함께 온 텍스트가 각 파일의 caption / 텍스트만 오면 받은 문장이 원본.
ShareResult buildShare(ShareInput input, Uint8List Function(String path) read) {
  final items = <(NewRecord, Uint8List)>[];
  final tooBig = <String>[];
  final caption = _captionOf(input.text);
  final count = input.files.where((f) => !f.tooBig && f.path != null).length;
  final groupId = count >= 2 ? record.newId() : null;
  final groupSize = count >= 2 ? count : null;
  for (final f in input.files) {
    if (f.tooBig || f.path == null) {
      tooBig.add(f.name ?? '이름 없는 파일');
      continue;
    }
    final mime = f.mime ?? fallbackMime;
    items.add(prepare(
      read(f.path!),
      input: 'share',
      kind: record.kindForMime(mime),
      source: input.source,
      originalName: f.name,
      mime: mime,
      caption: caption,
      groupId: groupId,
      groupSize: groupSize,
    ));
  }
  final body = input.text;
  if (input.files.isEmpty && body != null) {
    try {
      final kind = record.classifyText(body);
      items.add(prepare(Uint8List.fromList(utf8.encode(body)),
          input: 'share', kind: kind, source: input.source, originalName: null, mime: record.textMime));
    } on record.EmptyTextError {
      // 오류가 아니라 정해진 흐름 — empty를 받은 쪽(share_entry.dart)이 로그 + '보낼 내용 없음' 알림
      return ShareResult(items, tooBig, empty: true);
    }
  }
  return ShareResult(items, tooBig, empty: items.isEmpty && tooBig.isEmpty);
}
