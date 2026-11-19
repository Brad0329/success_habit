// F-010 목록·검색, F-028 사진 묶음(받기), F-029 감시 — 수용 기준(docs/requirements/목록.md)을 실제 임시 폴더로 건다.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chaerok/collection_list.dart';
import 'package:chaerok/log.dart';
import 'package:chaerok/phone_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late Directory tmp, records;
  late CountingStore store;
  late Collection col;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chaerok_list');
    records = Directory('${tmp.path}/records');
    initLog(tmp);
    store = CountingStore(PhoneStore(records));
    col = Collection(reader: () => store, deleter: () => store, now: () => DateTime(2026, 11, 19, 11, 2));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String log() => File('${tmp.path}/chaerok.log').readAsStringSync();
  void put(String month, String name, [String body = '{}']) =>
      (File('${records.path}/$month/$name')..parent.createSync(recursive: true)).writeAsStringSync(body);

  test('목록: 2026-10 2건 + 2026-11 3건 → 5건, 시각 내림차순, "전체 5건"', () async {
    putRecord(records, '20261030-090000', 'aaaaaaaa');
    putRecord(records, '20261031-120000', 'bbbbbbbb', device: 'pc', input: 'pc_text');
    putRecord(records, '20261101-080000', 'cccccccc');
    putRecord(records, '20261119-070000', 'dddddddd');
    putRecord(records, '20261119-093000', 'eeeeeeee');
    final s = await col.refresh();
    expect([for (final i in s.items) '${i.date} ${i.time}'],
        ['20261119 09:30', '20261119 07:00', '20261101 08:00', '20261031 12:00', '20261030 09:00']);
    expect(statusLine(s), '전체 5건 · 11:02 갱신');
    expect(s.items[3].deviceLabel, 'PC');
    expect(s.items[0].deviceLabel, '폰');
  });

  test('모든 달: YYYY-MM 폴더는 다 읽고 다른 이름의 폴더는 읽지 않는다', () async {
    putRecord(records, '20260901-000000', 'aaaaaaaa');
    putRecord(records, '20261001-000000', 'bbbbbbbb');
    putRecord(records, '20261101-000000', 'cccccccc');
    put('기타', '20261101-000001_dddddddd.txt', '안 읽힘');
    put('기타', '20261101-000001_dddddddd.meta.json');
    final s = await col.refresh();
    expect(s.items.length, 3);
    expect(s.unreadable, 0);
  });

  test('읽지 못함: 사이드카 없는 원본 + 원본 없는 사이드카 + 깨진 사이드카 2종 → 목록에서 빠지고 4건, 로그에 base', () async {
    putRecord(records, '20261119-100000', 'aaaaaaaa');
    final noMeta = putRecord(records, '20261119-100001', 'bbbbbbbb', sidecar: false);
    final noOrig = putRecord(records, '20261119-100002', 'cccccccc', original: false);
    final notJson = putRecord(records, '20261119-100003', 'dddddddd');
    put('2026-11', '$notJson.meta.json', '{깨짐');
    final badType = putRecord(records, '20261119-100004', 'eeeeeeee');
    put('2026-11', '$badType.meta.json', '{"kind": 3}');
    final s = await col.refresh();
    expect(s.items.length, 1);
    expect(s.unreadable, 4);
    expect(statusLine(s), '전체 1건 · 11:02 갱신 · 읽지 못함 4건');
    for (final b in [noMeta, noOrig, notJson, badType]) {
      expect(log(), contains(b));
    }
  });

  test('덧붙임 파일(ai·user·자막·모르는 꼬리·.tmp)이 있어도 1건이고 읽지 못함에 세지 않는다 / 제목은 user가 ai보다 우선·늦은 파일', () async {
    final b = putRecord(records, '20261119-100000', 'aaaaaaaa');
    put('2026-11', '$b.ai-20261119-100100.json', '{"title": "옛 AI 제목"}');
    put('2026-11', '$b.ai-20261119-100200.json', '{"title": "AI 제목"}');
    put('2026-11', '$b.transcript-20261119-100100.json');
    put('2026-11', '$b.foo.bar', 'x');
    put('2026-11', '$b.txt.tmp', '쓰다 만 것');
    var s = await col.refresh();
    expect(s.items.length, 1);
    expect(s.unreadable, 0);
    expect(s.items.single.title, 'AI 제목');
    expect(s.items.single.text, '본문');
    put('2026-11', '$b.user-20261119-100300.json', '{"title": "내가 고친 제목"}');
    store.reads.clear();
    s = await col.refresh();
    expect(s.items.single.title, '내가 고친 제목');
    // 결과 파일만 다시 읽는다 — 원본·사이드카는 다시 읽지 않는다
    expect(store.reads.where((p) => p.endsWith('.txt') || p.endsWith('.meta.json')), isEmpty);
  });

  test('규칙에 안 맞는 파일 이름은 읽지 못함으로 세고 로그에 이름을 남기지 않는다', () async {
    put('2026-11', '비밀 메모.txt', 'x');
    final s = await col.refresh();
    expect(s.unreadable, 1);
    expect(log(), isNot(contains('비밀 메모')));
  });

  test('상한 없음: 1,500건 → 목록 1,500건·"전체 1500건", 검색 결과도 자르지 않는다', () async {
    for (var k = 0; k < 1500; k++) {
      putRecord(records, '20261119-${(100000 + k).toString()}', k.toRadixString(16).padLeft(8, '0'), body: '공통 $k');
    }
    final s = await col.refresh();
    expect(s.items.length, 1500);
    expect(statusLine(s), startsWith('전체 1500건'));
    expect(searchItems(s.items, '공통').length, 1500);
  });

  test('검색 대상: 원문·메모·파일 이름은 걸리고 출처는 안 걸린다(4건 중 3건)', () async {
    putRecord(records, '20261119-100000', 'aaaaaaaa', body: '니체의 말');
    putRecord(records, '20261119-100001', 'bbbbbbbb', kind: 'image', ext: 'png', mime: 'image/png', caption: '니체 책 표지');
    putRecord(records, '20261119-100002', 'cccccccc', kind: 'file', ext: 'pdf', mime: 'application/pdf', originalName: '니체.pdf');
    putRecord(records, '20261119-100003', 'dddddddd', body: '다른 글', source: '니체 앱');
    final s = await col.refresh();
    expect(searchItems(s.items, '니체').length, 3);
  });

  test('검색 규칙: 두 단어 모두(AND) / 대소문자 무시 / 공백만이면 전체 / 0건 상태 줄', () async {
    putRecord(records, '20261119-100000', 'aaaaaaaa', body: 'Nietzsche 니체 공통 감각');
    putRecord(records, '20261119-100001', 'bbbbbbbb', body: '니체만');
    final s = await col.refresh();
    expect(searchItems(s.items, '니체 공통').length, 1);
    expect(searchItems(s.items, 'NIETZSCHE').length, 1);
    expect(searchItems(s.items, '   ').length, 2);
    expect(searchItems(s.items, '없는말'), isEmpty);
    expect(statusLine(s, matched: 0), '검색 결과 0건 / 전체 2건 · 11:02 갱신');
  });

  test('새로 고침이 겹쳐도 폴더 읽기는 한 번 / 두 번째 새로 고침은 새 수집물만 읽는다', () async {
    putRecord(records, '20261119-100000', 'aaaaaaaa');
    final both = await Future.wait([col.refresh(), col.refresh()]);
    expect(store.listings, 1);
    expect(identical(both[0], both[1]), isTrue);
    store.reads.clear();
    putRecord(records, '20261119-100001', 'bbbbbbbb');
    final s = await col.refresh();
    expect(s.items.length, 2);
    expect(store.reads.length, 2); // 새 건의 사이드카 + 원문
    expect(store.reads.every((p) => p.contains('bbbbbbbb')), isTrue);
  });

  test('일부 읽기 실패: 5건 중 1건 입출력 오류 → 4건 + "1건 못 읽음", 다음 새로 고침에 그 1건을 다시 읽는다', () async {
    for (var k = 0; k < 5; k++) {
      putRecord(records, '20261119-10000$k', '${k}aaaaaaa');
    }
    store.failRead = (p) => p.contains('3aaaaaaa') && p.endsWith('.meta.json');
    var s = await col.refresh();
    expect(s.items.length, 4);
    expect(statusLine(s), '전체 4건 · 11:02 갱신 · 1건 못 읽음');
    store.failRead = null;
    s = await col.refresh();
    expect(s.items.length, 5);
    expect(s.failed, 0);
  });

  test('폴더 나열이 실패하면 예외이고 마지막 목록은 그대로 남는다 / 상태 줄 "갱신 실패"', () async {
    putRecord(records, '20261119-100000', 'aaaaaaaa');
    final s = await col.refresh();
    final broken = Collection(reader: () => throw const FileSystemException('나열 실패'));
    await expectLater(broken.refresh(), throwsA(isA<FileSystemException>()));
    expect(col.cached()!.items.length, 1);
    expect(statusLine(s, refreshFailed: true), '전체 1건 · 11:02 갱신 · 갱신 실패');
  });

  test('로그에 수집물 본문·메모가 0번 나온다', () async {
    putRecord(records, '20261119-100000', 'aaaaaaaa', body: '비밀본문XYZ', caption: '비밀메모XYZ');
    await col.refresh();
    expect(log(), isNot(contains('XYZ')));
  });

  group('F-028 사진 묶음', () {
    Uint8List png(int n) => Uint8List.fromList(List.filled(n, 7));
    String photo(String at, String id, String? name, {String g = 'G1', int n = 3, String? caption, String kind = 'image',
            String ext = 'png', String mime = 'image/png', String device = 'phone', String input = 'share'}) =>
        putRecord(records, at, id, kind: kind, ext: ext, mime: mime, bytes: png(4), originalName: name, groupId: g,
            groupSize: n, caption: caption, device: device, input: input);

    test('사진 3장 묶음 + 단독 2건 → 전체 3건, 묶음은 대표 장 자리에 한 줄, 장 순서 = 파일 이름 자연 정렬', () async {
      final rep = photo('20261119-100001', 'aaaaaaaa', 'p2.png');
      final p10 = photo('20261119-100002', 'bbbbbbbb', 'p10.png');
      final p1 = photo('20261119-100003', 'cccccccc', 'p1.png');
      putRecord(records, '20261119-110000', 'dddddddd');
      putRecord(records, '20261119-090000', 'eeeeeeee');
      final s = await col.refresh();
      expect(statusLine(s), startsWith('전체 3건'));
      final g = s.items[1];
      expect(g.isGroup, isTrue);
      expect(g.base, rep);
      expect(g.time, '10:00');
      expect([for (final p in g.pages) p.base], [p1, rep, p10]);
      expect(g.preview, '사진 3장');
      expect(g.missingPages, 0);
      expect(g.otherBases.toSet(), {p10, p1});
      expect(s.raw.length, 5);
    });

    test('메모가 있으면 묶음 제목 자리는 메모', () async {
      photo('20261119-100001', 'aaaaaaaa', 'a.png', n: 2, caption: '책 두 쪽');
      photo('20261119-100002', 'bbbbbbbb', 'b.png', n: 2, caption: '책 두 쪽');
      expect((await col.refresh()).items.single.preview, '책 두 쪽');
    });

    test('대상 아님: png + pdf 묶음 → 2줄 / 기존판 pc_file png 2장 묶음 → 2줄', () async {
      photo('20261119-100001', 'aaaaaaaa', 'a.png', g: 'MIX', n: 2);
      photo('20261119-100002', 'bbbbbbbb', 'b.pdf', g: 'MIX', n: 2, kind: 'file', ext: 'pdf', mime: 'application/pdf');
      photo('20261119-100003', 'cccccccc', 'c.png', g: 'PC', n: 2, device: 'pc', input: 'pc_file');
      photo('20261119-100004', 'dddddddd', 'd.png', g: 'PC', n: 2, device: 'pc', input: 'pc_file');
      final s = await col.refresh();
      expect(s.items.length, 4);
      expect(s.items.any((i) => i.isGroup), isFalse);
    });

    test('일부만: group_size 3인데 2장 → 한 줄, 빠진 장 1', () async {
      photo('20261119-100001', 'aaaaaaaa', 'a.png');
      photo('20261119-100002', 'bbbbbbbb', 'b.png');
      photo('20261119-100003', 'cccccccc', 'c.png', n: 3)
          .let((b) => File('${records.path}/2026-11/$b.meta.json').deleteSync()); // 사이드카 없는 장
      final s = await col.refresh();
      expect(s.items.length, 1);
      expect(s.items.single.pages.length, 2);
      expect(s.items.single.groupTotal, 3);
      expect(s.items.single.missingPages, 1);
      expect(s.unreadable, 1);
    });

    test('검색: 2번째 장의 파일 이름에만·메모에만 있는 낱말 → 그 묶음 1건', () async {
      photo('20261119-100001', 'aaaaaaaa', 'a.png', n: 2);
      photo('20261119-100002', 'bbbbbbbb', '영수증.png', n: 2, caption: '점심값');
      final s = await col.refresh();
      expect(searchItems(s.items, '영수증').single.isGroup, isTrue);
      expect(searchItems(s.items, '점심값').length, 1);
    });

    test('옛 묶음(대표가 아닌 장에 ai 파일) → 장마다 한 줄', () async {
      photo('20261119-100001', 'aaaaaaaa', 'a.png', n: 2);
      final b = photo('20261119-100002', 'bbbbbbbb', 'b.png', n: 2);
      put('2026-11', '$b.ai-20261119-100100.json', '{"title": "한 장씩"}');
      expect((await col.refresh()).items.length, 2);
    });
  });

  group('F-018 목록 쪽', () {
    test('지운 뒤 마지막 목록·새로 고침에 그 건이 없다 / 지우기 전에 시작한 새로 고침이 끝나도 되살아나지 않는다', () async {
      final a = putRecord(records, '20261119-100000', 'aaaaaaaa');
      putRecord(records, '20261119-100001', 'bbbbbbbb');
      await col.refresh();
      // 새 건이 하나 더 생긴 뒤의 새로 고침을 그 건을 읽는 데서 멈춰 세운다 — a는 이미 '그대로인 것'으로 골라진 뒤다.
      putRecord(records, '20261119-100002', 'cccccccc');
      final gate = Completer<void>();
      store.gate = gate.future;
      final slow = col.refresh();
      for (var n = 0; n < 500 && !store.reads.last.contains('cccccccc'); n++) {
        await Future<void>.delayed(const Duration(milliseconds: 10)); // 폴더 나열(진짜 I/O)이 끝나 읽기에 걸릴 때까지
      }
      expect(store.reads.last, contains('cccccccc'));
      expect(await col.delete(a), 2);
      gate.complete();
      store.gate = null;
      expect((await slow).items.map((i) => i.base), isNot(contains(a)));
      expect(col.cached()!.items.length, 2);
      expect((await col.refresh()).items.length, 2);
    });

    test('묶음 지우기: 3장 → 파일 6개 삭제, 대표가 아닌 장 먼저·대표 원본이 맨 마지막, 다른 건 0', () async {
      String photo(String at, String id) => putRecord(records, at, id,
          kind: 'image', ext: 'png', mime: 'image/png', input: 'share', groupId: 'G', groupSize: 3, originalName: '$id.png');
      final rep = photo('20261119-100001', 'aaaaaaaa');
      photo('20261119-100002', 'bbbbbbbb');
      photo('20261119-100003', 'cccccccc');
      putRecord(records, '20261119-110000', 'dddddddd');
      final g = (await col.refresh()).items.firstWhere((i) => i.isGroup);
      expect(await col.delete(g.base, others: g.otherBases), 6);
      expect(store.deletes.length, 6);
      expect(store.deletes.last, 'records/2026-11/$rep.png');
      expect(store.deletes.take(4).any((p) => p.contains(rep)), isFalse);
      expect(namesIn(records, '2026-11').length, 2);
    });

    test('묶음 지우기 중간 실패 → 그 뒤 삭제 0, 대표 장 파일 전부 남고 목록에 묶음이 남는다', () async {
      String photo(String at, String id) => putRecord(records, at, id,
          kind: 'image', ext: 'png', mime: 'image/png', input: 'share', groupId: 'G', groupSize: 2, originalName: '$id.png');
      final rep = photo('20261119-100001', 'aaaaaaaa');
      final other = photo('20261119-100002', 'bbbbbbbb');
      final g = (await col.refresh()).items.single;
      store.failDelete = (p) => p.endsWith('$other.png');
      await expectLater(col.delete(g.base, others: g.otherBases), throwsA(anything));
      expect(store.deletes, ['records/2026-11/$other.meta.json']);
      expect(namesIn(records, '2026-11').where((n) => n.startsWith(rep)).length, 2);
      expect(col.cached()!.items.single.isGroup, isTrue);
    });
  });
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}
