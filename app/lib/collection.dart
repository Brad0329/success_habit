/// 수집물 나무를 이름 규칙으로 읽기 — 원본·사이드카·덧붙임 파일을 base로 짝짓는다(F-035 · F-010).
///
/// **읽기만 한다**: [RecordReader]만 받는다 — 쓰기·지우기는 타입에 없어 부를 수 없다.
/// 기존판 collection.dart의 짝짓기 부분이다. 대화 맥락 만들기(F-009 `gather`)는 Phase 005에서 이 파일에 옮긴다.
library;

import 'ai_result.dart';
import 'log.dart';
import 'phone_store.dart';

/// 읽는 쪽 이름 규칙은 여기 한 곳(기존판 D7 2026-11-15: 목록·지우기가 따로 적었다). 쓰는 규칙은 record.dart `baseName`·`monthFolder` —
/// 둘이 맞는지는 phone_store_test '읽는 이름 규칙이 쓰는 이름 규칙과 맞는다(D7)'가 대조한다.
const _base = r'(\d{8})-(\d{6})_([0-9a-f]{8})';

/// `YYYYMMDD-HHMMSS_<8자>.<확장자>` / `….meta.json`.
final _nameRe = RegExp('^$_base\\.(.+)\$');
final _baseOnlyRe = RegExp('^$_base\$');

/// 수집물 이름 앞부분(base)인가 — F-018 지우기가 파일을 찾기 전에 본다.
bool isRecordBase(String base) => _baseOnlyRe.hasMatch(base);

final _monthRe = RegExp(r'^\d{4}-\d{2}$');

/// `YYYY-MM` 달 폴더 이름인가.
bool isMonthFolder(String name) => _monthRe.hasMatch(name);

/// base(`YYYYMMDD-…`)가 든 달 폴더 이름 `YYYY-MM`.
String monthOfBase(String base) => '${base.substring(0, 4)}-${base.substring(4, 6)}';

/// 이름으로 짝지은 수집물 하나. 원본·사이드카 중 하나가 없으면 읽지 못함으로 센다.
/// 덧붙임 파일(AI 결과·사용자 수정·자막)은 여럿일 수 있다 — 고르는 규칙은 ai_result.dart.
class ListedRecord {
  ListedRecord(this.base, {this.original, this.meta});
  final String base;
  StoreEntry? original;
  StoreEntry? meta;

  final aiFiles = <StoreEntry>[];
  final userFiles = <StoreEntry>[];
  final transcriptFiles = <StoreEntry>[];

  String get date => base.substring(0, 8);
  String get month => monthOfBase(base);
}

/// 달 폴더들의 파일을 원본·사이드카 짝으로 모은다. 이름이 규칙에 안 맞는 파일 수를 함께 돌려준다.
/// [months]가 null이면 `YYYY-MM` 이름 폴더 전부(F-010 목록) — 다른 이름의 폴더는 읽지 않는다.
Future<(Map<String, ListedRecord>, int)> listRecords(RecordReader r, {List<String>? months, required String who}) async {
  final listed = <String, ListedRecord>{};
  var odd = 0;
  final all = [for (final m in await r.months()) if (isMonthFolder(m)) m]..sort();
  for (final month in months == null ? all : all.where(months.contains)) {
    odd += _pair(listed, await r.files(month), who);
  }
  return (listed, odd);
}

/// 한 폴더의 파일을 짝에 더한다. 이름이 규칙에 안 맞는 파일 수를 돌려준다.
int _pair(Map<String, ListedRecord> listed, List<StoreEntry> files, String who) {
  var odd = 0;
  for (final f in files) {
    final match = _nameRe.firstMatch(f.name);
    if (match == null) {
      odd++;
      logWarn('$who: 규칙에 안 맞는 파일 이름 건너뜀(${f.name.length}자)');
      continue;
    }
    final base = '${match.group(1)}-${match.group(2)}_${match.group(3)}';
    final tail = match.group(4)!;
    // 원본 확장자에는 점이 없다(record.extensionFor). 점 있는 꼬리 중 meta.json·결과 파일 말고는
    // 모르는 덧붙임 파일(쓰다 만 `.tmp` 포함)이라 원본으로 오인하면 진짜 원본을 가린다 — 건너뛴다(읽지 못함으로 세지 않음).
    final isAi = aiTailRe.hasMatch(tail), isUser = userTailRe.hasMatch(tail), isTranscript = transcriptTailRe.hasMatch(tail);
    if (tail != 'meta.json' && !isAi && !isUser && !isTranscript && tail.contains('.')) {
      logInfo('$who: 원본·사이드카가 아닌 덧붙임 파일 건너뜀($base, 꼬리 ${tail.length}자)');
      continue;
    }
    final e = listed.putIfAbsent(base, () => ListedRecord(base));
    if (tail == 'meta.json') {
      e.meta = f;
    } else if (isAi) {
      e.aiFiles.add(f);
    } else if (isUser) {
      e.userFiles.add(f);
    } else if (isTranscript) {
      e.transcriptFiles.add(f);
    } else {
      e.original = f;
    }
  }
  return odd;
}
