/// F-018 목록에서 지우기 — 한 건의 파일(원본·사이드카·덧붙임) 전부를 폰에서 **완전 삭제**한다(휴지통 없음, 되돌릴 수 없음).
///
/// '한 번 쓰면 고치지 않는다'(SCHEMA 설계 원칙 4)의 **유일한 예외**다: 사용자가 목록에서 고르고 확인했을 때만 부른다.
/// 앱에서 수집물 파일을 지우는 호출은 [RecordDeleter]뿐이다 — 다른 쪽은 이 타입을 받지 않는다.
library;

import 'collection.dart';
import 'log.dart';
import 'phone_store.dart';

/// 중간에 실패 — [deleted]개를 지우고 멈췄다. 원본은 맨 마지막에 지우므로 남아 있다.
class DeleteFailed implements Exception {
  DeleteFailed(this.deleted, this.total, this.cause);
  final int deleted;
  final int total;
  final Object cause;

  String get userMessage => '지우지 못했습니다($total개 중 $deleted개 지움) — 다시 지우세요';

  @override
  String toString() => 'DeleteFailed($deleted/$total, ${cause.runtimeType})';
}

/// [base] 건의 파일을 그 날짜 달 폴더에서 찾아 지운다.
/// 순서 = 덧붙임 → 사이드카 → 원본. 지운(또는 이미 없던) 파일 수를 돌려준다. 하나도 없으면 0.
Future<int> deleteRecord(RecordReader r, RecordDeleter d, String base) => deleteRecords(r, d, [base]);

/// F-028 사진 묶음 한 건 = 여러 장. [bases]의 **마지막이 대표 장**이다 — 앞 장들을 차례로
/// (장마다 덧붙임 → 사이드카 → 원본) 지운 뒤 대표 장을 맨 마지막에 지운다. 중간에 멈춰도 대표와 묶음 결과가 남아 다시 지울 수 있다.
Future<int> deleteRecords(RecordReader r, RecordDeleter d, List<String> bases) async {
  if (bases.isEmpty) throw ArgumentError.value(bases, 'bases', '지울 수집물이 없음');
  for (final b in bases) {
    if (!isRecordBase(b)) throw ArgumentError.value(b, 'base', '수집물 이름 규칙에 안 맞음');
  }
  final base = bases.last; // 로그 이름 = 대표
  final targets = <StoreEntry>[];
  final months = <String, List<StoreEntry>>{}; // 묶음의 장은 대개 같은 달 — 달 폴더 목록은 한 번만 읽는다
  for (final b in bases) {
    targets.addAll(await _filesOf(r, b, months));
  }
  var done = 0;
  for (final f in targets) {
    try {
      if (!await d.delete(f.path)) logWarn('지우기: $base 파일 하나가 이미 없음(건너뜀)');
      done++;
    } on Object catch (e) {
      logError('지우기 실패: $base ${targets.length}개 중 $done개 지움', e);
      throw DeleteFailed(done, targets.length, e);
    }
  }
  logInfo('지우기: $base${bases.length > 1 ? '(사진 ${bases.length}장)' : ''} 파일 $done개 완전 삭제');
  return done;
}

/// 한 장의 파일 — 지울 순서(덧붙임 → 사이드카 → 원본)로.
/// [months] = 이번 지우기에서 이미 읽은 달 폴더의 파일 목록(달 이름 → 파일).
Future<List<StoreEntry>> _filesOf(RecordReader r, String base, Map<String, List<StoreEntry>> months) async {
  final month = monthOfBase(base);
  final prefix = '$base.';
  final files = months[month] ??= await r.files(month);
  return [for (final f in files) if (f.name.startsWith(prefix)) f]
    ..sort((a, b) => _order(a, prefix).compareTo(_order(b, prefix)));
}

/// 0 = 덧붙임(ai·user·자막·모르는 꼬리), 1 = 사이드카, 2 = 원본(확장자에 점이 없다 — record.extensionFor).
int _order(StoreEntry f, String prefix) {
  final tail = f.name.substring(prefix.length);
  if (tail == 'meta.json') return 1;
  return tail.contains('.') ? 0 : 2;
}
