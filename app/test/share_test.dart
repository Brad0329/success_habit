// F-002 공유 메뉴로 받기 — 수용 기준(docs/requirements/수집.md). 공유 엔진이 폰에 바로 저장하고 알림으로 결과를 알린다.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chaerok/atomic_file.dart';
import 'package:chaerok/change_signal.dart';
import 'package:chaerok/collection_list.dart';
import 'package:chaerok/log.dart';
import 'package:chaerok/phone_store.dart';
import 'package:chaerok/record.dart' as record;
import 'package:chaerok/share.dart';
import 'package:chaerok/share_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp, records, inbox;
  late PhoneStore store;
  late ChangeSignal signal;
  final notes = <(String, String, int)>[];
  Future<void> notify(String title, String body, {int id = 1}) async => notes.add((title, body, id));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chaerok_share');
    records = Directory('${tmp.path}/records');
    inbox = Directory('${tmp.path}/share_inbox/u')..createSync(recursive: true);
    initLog(tmp);
    store = PhoneStore(records);
    signal = ChangeSignal(File('${tmp.path}/changed.txt'))..start();
    notes.clear();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String log() => File('${tmp.path}/chaerok.log').readAsStringSync();
  SharedFile file(String name, List<int> bytes, {String? mime, String? as}) {
    final f = File('${inbox.path}/$name')..writeAsBytesSync(bytes);
    return SharedFile(path: f.path, name: as ?? name, mime: mime);
  }

  Future<List<Map<String, Object?>>> metas() async {
    final out = <Map<String, Object?>>[];
    if (!records.existsSync()) return out;
    for (final f in records.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.meta.json'))) {
      out.add((jsonDecode(f.readAsStringSync()) as Map).cast());
    }
    return out..sort((a, b) => (a['original_name'] as String? ?? '').compareTo(b['original_name'] as String? ?? ''));
  }

  Future<void> share(ShareInput input, {PhoneStore? to}) =>
      collectShare(input, to ?? store, notify: notify, changed: signal);

  test('텍스트만 공유 → 수집물 1건(.txt, input share, 링크면 url), 알림 "채록 저장됨 / 1건 저장됨", 신호 바뀜', () async {
    await share(const ShareInput(text: 'https://example.com/x', source: 'com.android.chrome'));
    final m = (await metas()).single;
    expect([m['input'], m['kind'], m['device'], m['source'], m['caption']], ['share', 'url', 'phone', 'com.android.chrome', null]);
    expect(notes, [('채록 저장됨', '1건 저장됨', 1)]);
    expect(signal.changed(), isTrue);
    final names = [for (final f in records.listSync(recursive: true).whereType<File>()) f.uri.pathSegments.last];
    expect(names.where((n) => n.endsWith('.txt') && !n.endsWith('.meta.json')).length, 1);
    expect(names.length, 2);
  });

  test('공유해 온 앱을 안드로이드가 알려 주지 않으면 source는 null', () async {
    await share(const ShareInput(text: '출처 모름'));
    final m = (await metas()).single;
    expect(m.containsKey('source'), isTrue);
    expect(m['source'], isNull);
  });

  test('파일은 하나씩 읽어 저장한다 — 두 번째 파일을 읽기 전에 첫 건이 이미 나무에 있다', () async {
    final a = file('a.png', [1], mime: 'image/png'), b = file('b.png', [2], mime: 'image/png');
    final seenAtRead = <int>[];
    final r = buildShare(ShareInput(files: [a, b]), (p) {
      seenAtRead.add(records.existsSync() ? records.listSync(recursive: true).whereType<File>().length : 0);
      return File(p).readAsBytesSync();
    });
    expect(seenAtRead, isEmpty); // 만들 때는 아무것도 읽지 않는다
    expect(r.count, 2);
    for (final (item, data) in r.items) {
      store.save(item, data);
    }
    expect(seenAtRead, [0, 2]);
  });

  test('3개 중 2번째 사본을 읽지 못하면(파일 없음) 저장한 것을 되돌린다: 파일 0개, 알림 "저장 실패"', () async {
    final files = [
      file('p1.png', [1], mime: 'image/png'),
      SharedFile(path: '${inbox.path}/없는파일', name: 'p2.png', mime: 'image/png'),
      file('p3.png', [3], mime: 'image/png'),
    ];
    await share(ShareInput(files: files));
    expect(records.existsSync() ? records.listSync(recursive: true).whereType<File>().toList() : [], isEmpty);
    expect(notes, [('저장 실패', '공유를 받지 못했습니다 — 다시 공유하세요', 1)]);
    expect(signal.changed(), isFalse);
  });

  test('파일 1개 → 1건, 원본 MD5 = 받은 파일, 이름·종류·MIME / MIME을 못 받으면 octet-stream·file / 묶음 표시 없음', () async {
    final bytes = List.generate(5000, (i) => i % 251);
    await share(ShareInput(files: [file('a.jpg', bytes, mime: 'image/jpeg')]));
    final m = (await metas()).single;
    expect(m['md5'], record.md5Hex(Uint8List.fromList(bytes)));
    expect([m['original_name'], m['kind'], m['mime'], m['group_id'], m['group_size']], ['a.jpg', 'image', 'image/jpeg', null, null]);
    final orig = records.listSync(recursive: true).whereType<File>().firstWhere((f) => f.path.endsWith('.jpg'));
    expect(orig.readAsBytesSync(), bytes);

    final r = buildShare(ShareInput(files: [file('noname', [1, 2], as: '')]), (p) => File(p).readAsBytesSync());
    expect([r.items.single.$1.sidecar['mime'], r.items.single.$1.sidecar['kind'], r.items.single.$1.sidecar['original_name']],
        ['application/octet-stream', 'file', null]);
  });

  test('파일 3개 + 텍스트 → 3건, 같은 group_id·group_size 3, 텍스트는 각 caption(텍스트 수집물은 따로 없음)', () async {
    await share(ShareInput(text: '책 두 쪽', files: [
      file('p1.png', [1], mime: 'image/png'),
      file('p2.png', [2], mime: 'image/png'),
      file('p3.png', [3], mime: 'image/png'),
    ]));
    final ms = await metas();
    expect(ms.length, 3);
    expect(ms.map((m) => m['group_id']).toSet().length, 1);
    expect(ms.first['group_id'], isNotNull);
    expect(ms.map((m) => m['group_size']).toSet(), {3});
    expect(ms.map((m) => m['caption']).toSet(), {'책 두 쪽'});
    expect(notes, [('채록 저장됨', '3건 저장됨', 1)]);
    final snap = await Collection(reader: () => store).refresh();
    expect(snap.items.single.pages.length, 3); // F-028 목록 한 줄
  });

  test('공백뿐인 함께 온 텍스트는 caption null', () async {
    await share(ShareInput(text: ' \n ', files: [file('a.png', [1], mime: 'image/png')]));
    expect((await metas()).single['caption'], isNull);
  });

  test('100MB 초과로 빠진 파일은 저장하지 않고 알림, 나머지는 저장 — group_size는 저장하는 건수', () async {
    await share(ShareInput(files: [
      file('a.png', [1], mime: 'image/png'),
      const SharedFile(path: null, name: '큰영상.mp4', mime: 'video/mp4', tooBig: true),
      file('b.png', [2], mime: 'image/png'),
    ]));
    final ms = await metas();
    expect(ms.length, 2);
    expect(ms.map((m) => m['group_size']).toSet(), {2});
    expect(notes, [('용량 초과(상한 100MB)', '큰영상.mp4 — 저장하지 않았습니다', 2), ('채록 저장됨', '2건 저장됨', 1)]);
  });

  test('받은 것이 없거나 공백뿐인 텍스트 → 저장 0건, 알림 "보낼 내용 없음", 신호 안 바뀜', () async {
    await share(const ShareInput(text: '  \n'));
    await share(const ShareInput());
    expect(await metas(), isEmpty);
    expect(notes, [('보낼 내용 없음', '공유받은 내용이 비어 있습니다', 2), ('보낼 내용 없음', '공유받은 내용이 비어 있습니다', 2)]);
    expect(signal.changed(), isFalse);
  });

  test('3개 중 2번째 저장 실패 → 이번 공유로 쓴 것을 전부 되돌린다: 파일 0개, 알림 "저장 실패", 신호 안 바뀜, 로그', () async {
    var originals = 0;
    final failing = PhoneStore(records, write: (f, d) {
      if (!f.path.endsWith('.meta.json') && ++originals == 2) throw const FileSystemException('디스크 가득(테스트)');
      writeAtomicSync(f, d);
    });
    await share(ShareInput(text: '비밀메모XYZ', files: [
      file('p1.png', [1], mime: 'image/png'),
      file('p2.png', [2], mime: 'image/png'),
      file('p3.png', [3], mime: 'image/png'),
    ]), to: failing);
    expect(records.listSync(recursive: true).whereType<File>(), isEmpty);
    expect(notes, [('저장 실패', '공유를 받지 못했습니다 — 다시 공유하세요', 1)]);
    expect(signal.changed(), isFalse);
    expect(log(), contains('되돌린다'));
    expect(log(), isNot(contains('XYZ')));
    expect((await Collection(reader: () => store).refresh()).items, isEmpty);
  });

  test('사본 폴더 지우기: 있으면 통째로, 없거나 null이면 아무 일 없음', () {
    file('a', [1]);
    removeInbox(inbox.path);
    expect(inbox.existsSync(), isFalse);
    removeInbox(inbox.path);
    removeInbox(null);
  });

  test('로그에 공유받은 글이 0번 나온다(ID·종류·출처만)', () async {
    await share(const ShareInput(text: '비밀본문XYZ', source: 'com.kakao.talk'));
    expect(log(), contains('source=com.kakao.talk'));
    expect(log(), isNot(contains('XYZ')));
  });
}
