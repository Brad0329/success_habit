// F-035 폰 안 저장 — 수용 기준(docs/REQUIREMENTS.md F-035)을 실제 임시 폴더에 파일을 써서 건다.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chaerok/atomic_file.dart';
import 'package:chaerok/collection.dart';
import 'package:chaerok/collection_list.dart';
import 'package:chaerok/log.dart';
import 'package:chaerok/phone_store.dart';
import 'package:chaerok/record.dart' as record;
import 'package:chaerok/record_delete.dart';
import 'package:chaerok/sender.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late Directory tmp, records;
  late PhoneStore store;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chaerok_store');
    records = Directory('${tmp.path}/records');
    initLog(tmp);
    store = PhoneStore(records);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String log() => File('${tmp.path}/chaerok.log').readAsStringSync();
  List<File> allFiles() => records.existsSync() ? records.listSync(recursive: true).whereType<File>().toList() : [];

  test('글 한 건 저장 → records/YYYY-MM/에 원본 .txt와 사이드카 두 파일, 사이드카 md5·size가 원본과 같다', () {
    final (item, data) = preparePaste('니체의 문장');
    final entry = store.save(item, data);
    final month = record.monthFolder(item.sidecar['collected_at']! as String);
    expect(namesIn(records, month), ['${item.base}.meta.json', '${item.base}.txt']);
    expect(entry.path, 'records/$month/${item.base}.txt');
    final orig = File('${records.path}/$month/${item.base}.txt').readAsBytesSync();
    final meta = jsonDecode(File('${records.path}/$month/${item.base}.meta.json').readAsStringSync()) as Map;
    expect(utf8.decode(orig), '니체의 문장');
    expect(meta['md5'], record.md5Hex(orig));
    expect(meta['size'], orig.length);
  });

  test('사이드카는 14항목을 모두 갖고(없는 값은 null), device는 phone, schema_version은 1', () {
    final (item, data) = preparePaste('글');
    store.save(item, data);
    final month = record.monthFolder(item.sidecar['collected_at']! as String);
    final meta = jsonDecode(File('${records.path}/$month/${item.metaName}').readAsStringSync()) as Map;
    expect(meta.keys.toList(), record.sidecarKeys);
    expect(meta.length, 14);
    expect(meta['device'], 'phone');
    expect(meta['schema_version'], 1);
    expect(meta['input'], 'paste');
    for (final k in ['source', 'original_name', 'caption', 'group_id', 'group_size']) {
      expect(meta.containsKey(k) && meta[k] == null, isTrue, reason: k);
    }
  });

  test('저장 직후 목록 읽기가 그 건을 1건으로 돌려준다', () async {
    final (item, data) = preparePaste('방금 저장');
    store.save(item, data);
    final snap = await Collection(reader: () => store).refresh();
    expect(snap.items.map((i) => i.base), [item.base]);
    expect(snap.items.single.text, '방금 저장');
    expect(snap.unreadable, 0);
  });

  test('원본만 있고 사이드카가 없는 파일은 목록에 나오지 않고 읽지 못함 1건', () async {
    putRecord(records, '20261119-100000', 'aaaaaaaa');
    putRecord(records, '20261119-100001', 'bbbbbbbb', sidecar: false);
    final snap = await Collection(reader: () => store).refresh();
    expect(snap.items.length, 1);
    expect(snap.unreadable, 1);
  });

  test('같은 초에 두 건을 저장해도 base가 겹치지 않고 두 건 모두 남는다', () async {
    final a = preparePaste('하나'), b = preparePaste('둘');
    store.save(a.$1, a.$2);
    store.save(b.$1, b.$2);
    expect(a.$1.base, isNot(b.$1.base));
    expect(allFiles().length, 4);
    expect((await Collection(reader: () => store).refresh()).items.length, 2);
  });

  test('같은 이름이 이미 있으면 쓰기를 거부하고 있던 파일은 그대로다', () {
    final (item, data) = preparePaste('먼저');
    store.save(item, data);
    final before = {for (final f in allFiles()) f.path: f.readAsStringSync()};
    expect(() => store.save(item, Uint8List.fromList(utf8.encode('덮어쓰기'))), throwsA(isA<SaveFailed>()));
    expect({for (final f in allFiles()) f.path: f.readAsStringSync()}, before);
  });

  for (final failAt in ['txt', 'meta.json']) {
    test('저장 중 실패($failAt 쓰기 오류) → 반쪽 파일이 남지 않고 로그에 남고 SaveFailed', () async {
      final failing = PhoneStore(records, write: (f, d) {
        if (f.path.endsWith(failAt)) {
          File('${f.path}.tmp').writeAsStringSync('쓰다 만 것'); // 임시 파일까지 쓰다 죽은 모양
          throw const FileSystemException('디스크 가득(테스트)');
        }
        writeAtomicSync(f, d);
      });
      final (item, data) = preparePaste('실패할 글');
      expect(() => failing.save(item, data), throwsA(isA<SaveFailed>().having((e) => e.userMessage, '문구', '저장하지 못했습니다')));
      expect(allFiles(), isEmpty);
      expect(log(), contains('저장 실패 ${item.base}'));
      expect(log(), isNot(contains('실패할 글')));
      final snap = await Collection(reader: () => store).refresh();
      expect(snap.items, isEmpty);
      expect(snap.unreadable, 0);
    });
  }

  test('기존판 형식(input pc_text, device pc)의 파일을 폴더에 넣으면 목록이 그대로 읽는다', () async {
    putRecord(records, '20261030-133700', '0a1b2c3d', input: 'pc_text', device: 'pc', body: 'PC에서 보낸 글', source: '메모장');
    final item = (await Collection(reader: () => store).refresh()).items.single;
    expect(item.text, 'PC에서 보낸 글');
    expect(item.deviceLabel, 'PC');
    expect(item.inputLabel, 'PC 단축키');
  });

  test('한 건을 지우면 그 건의 <base>. 파일이 0개가 되고 다른 건의 파일 수는 변하지 않는다', () async {
    final a = putRecord(records, '20261119-100000', 'aaaaaaaa');
    final b = putRecord(records, '20261119-100001', 'bbbbbbbb');
    expect(await deleteRecord(store, store, a), 2);
    final names = namesIn(records, '2026-11');
    expect(names.where((n) => n.startsWith('$a.')), isEmpty);
    expect(names.where((n) => n.startsWith('$b.')).length, 2);
  });

  test('공유 엔진과 화면이 번갈아 저장해도(저장소 객체 둘) 두 쪽 건이 모두 완전하게 남는다', () async {
    final ui = PhoneStore(records), share = PhoneStore(records);
    for (var k = 0; k < 5; k++) {
      final a = preparePaste('화면 $k'), b = preparePaste('공유 $k');
      ui.save(a.$1, a.$2);
      share.save(b.$1, b.$2);
    }
    final snap = await Collection(reader: () => store).refresh();
    expect(snap.items.length, 10);
    expect(snap.unreadable, 0);
  });

  group('경로', () {
    test('나무 밖 경로·달 폴더가 아닌 이름은 읽기·지우기·나열을 거부한다', () {
      putRecord(records, '20261119-100000', 'aaaaaaaa');
      File('${tmp.path}/secret.txt').writeAsStringSync('밖');
      for (final p in ['records/2026-11/../../secret.txt', '../secret.txt', 'records/2026-11/a/b', 'settings/key', 'records/기타/x.txt']) {
        expect(() => store.read(p), throwsArgumentError, reason: p);
        expect(() => store.delete(p), throwsArgumentError, reason: p);
      }
      expect(() => store.files('../settings'), throwsArgumentError);
      expect(File('${tmp.path}/secret.txt').existsSync(), isTrue);
    });

    test('파일 이름에 경로 조각이 섞인 수집물은 저장하지 않는다', () {
      final (item, data) = preparePaste('글');
      final bad = NewRecord(item.sidecar, '${item.base}.x/../../evil', item.metaName);
      expect(() => store.save(bad, data), throwsA(isA<SaveFailed>()));
      expect(tmp.listSync(recursive: true).whereType<File>().where((f) => f.path.contains('evil')), isEmpty);
      expect(allFiles(), isEmpty);
    });

    test('읽는 이름 규칙이 쓰는 이름 규칙과 맞는다(D7) — 저장한 base·달 폴더를 읽는 쪽이 알아본다', () {
      final (item, _) = preparePaste('글');
      expect(isRecordBase(item.base), isTrue);
      expect(isMonthFolder(record.monthFolder(item.sidecar['collected_at']! as String)), isTrue);
      expect(monthOfBase(item.base), record.monthFolder(item.sidecar['collected_at']! as String));
    });
  });
}
