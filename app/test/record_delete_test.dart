// F-018 목록에서 지우기 — 수용 기준(docs/requirements/목록.md). 되돌릴 수 없는 삭제라 범위·순서를 실제 파일로 건다.
import 'dart:io';

import 'package:chaerok/log.dart';
import 'package:chaerok/phone_store.dart';
import 'package:chaerok/record_delete.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late Directory tmp, records;
  late CountingStore store;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chaerok_del');
    records = Directory('${tmp.path}/records');
    initLog(tmp);
    store = CountingStore(PhoneStore(records));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String log() => File('${tmp.path}/chaerok.log').readAsStringSync();
  void put(String name) => File('${records.path}/2026-11/$name').writeAsStringSync('x');

  /// 그 건 파일 5개(원본·meta·ai·user·자막) + 다른 건 2개.
  String five() {
    final b = putRecord(records, '20261119-100000', 'aaaaaaaa', body: '비밀본문XYZ');
    put('$b.ai-20261119-100100.json');
    put('$b.user-20261119-100200.json');
    put('$b.transcript-20261119-100300.json');
    putRecord(records, '20261119-100001', 'bbbbbbbb');
    return b;
  }

  test('그 건 파일 5개 + 다른 건 2개 → 5개 삭제(다른 건 0), 순서 = 덧붙임 → 사이드카 → 원본', () async {
    final b = five();
    expect(await deleteRecord(store, store, b), 5);
    expect(store.deletes.length, 5);
    expect(store.deletes[3], 'records/2026-11/$b.meta.json');
    expect(store.deletes[4], 'records/2026-11/$b.txt');
    expect(namesIn(records, '2026-11'), ['20261119-100001_bbbbbbbb.meta.json', '20261119-100001_bbbbbbbb.txt']);
  });

  test('모르는 꼬리·쓰다 만 .tmp도 지운다 / base로 시작만 하고 바로 뒤가 "."이 아닌 파일은 안 지운다', () async {
    final b = putRecord(records, '20261119-100000', 'aaaaaaaa');
    put('$b.foo.bar');
    put('$b.txt.tmp');
    put('${b}x.txt'); // 다른 건
    expect(await deleteRecord(store, store, b), 4);
    expect(namesIn(records, '2026-11'), ['${b}x.txt']);
  });

  test('중간 실패: 3번째에서 실패 → 그 뒤 삭제 0, 원본 남음, 문구에 "5개 중 2개 지움"', () async {
    final b = five();
    var n = 0;
    store.failDelete = (_) => ++n == 3;
    await expectLater(
        deleteRecord(store, store, b),
        throwsA(isA<DeleteFailed>()
            .having((e) => e.userMessage, '문구', '지우지 못했습니다(5개 중 2개 지움) — 다시 지우세요')
            .having((e) => e.deleted, '지운 수', 2)));
    expect(store.deletes.length, 2);
    expect(File('${records.path}/2026-11/$b.txt').existsSync(), isTrue);
    expect(File('${records.path}/2026-11/$b.meta.json').existsSync(), isTrue);
  });

  test('지우는 사이 이미 없어진 파일 → 건너뛰고 나머지를 지움, 로그 1줄', () async {
    final b = five();
    final inner = store.inner;
    final racing = _VanishingDeleter(inner, File('${records.path}/2026-11/$b.meta.json'));
    expect(await deleteRecord(inner, racing, b), 5);
    expect(namesIn(records, '2026-11').where((x) => x.startsWith(b)), isEmpty);
    expect('이미 없음'.allMatches(log()).length, 1);
  });

  test('하나도 못 찾으면 0 / base가 이름 규칙이 아니면 오류이고 지운 파일 0개', () async {
    putRecord(records, '20261119-100000', 'aaaaaaaa');
    expect(await deleteRecord(store, store, '20261119-100000_ffffffff'), 0);
    for (final bad in ['', '../x', '20261119-100000_aaaaaaa', '20261119-100000_aaaaaaaa.txt', '2026']) {
      await expectLater(deleteRecord(store, store, bad), throwsArgumentError, reason: bad);
    }
    await expectLater(deleteRecords(store, store, []), throwsArgumentError);
    expect(store.deletes, isEmpty);
    expect(namesIn(records, '2026-11').length, 2);
  });

  test('로그에 수집물 본문 0번(base·개수만)', () async {
    final b = five();
    await deleteRecord(store, store, b);
    expect(log(), contains('$b 파일 5개 완전 삭제'));
    expect(log(), isNot(contains('XYZ')));
  });
}

/// 사이드카를 지우려는 순간 다른 쪽이 먼저 지운 상황.
class _VanishingDeleter implements RecordDeleter {
  _VanishingDeleter(this.inner, this.victim);
  final PhoneStore inner;
  final File victim;

  @override
  Future<bool> delete(String path) {
    if (path.endsWith('.meta.json') && victim.existsSync()) victim.deleteSync();
    return inner.delete(path);
  }
}
