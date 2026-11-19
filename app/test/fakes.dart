// 테스트 공용 가짜 — 기기 채널(Device)·녹음기와, 실제 임시 폴더에 기존판 형식의 수집물 파일을 놓는 도우미.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chaerok/change_signal.dart';
import 'package:chaerok/collection_list.dart';
import 'package:chaerok/collection_screen.dart';
import 'package:chaerok/phone_store.dart';
import 'package:chaerok/platform.dart';
import 'package:chaerok/record.dart' as record;
import 'package:chaerok/voice.dart';

class FakeDevice {
  FakeDevice(this.files);
  final Directory files;
  String? clipboard;
  bool focused = true;
  bool notifications = true;
  bool clearFails = false;
  int cleared = 0, appSettings = 0, notifSettings = 0;
  final opened = <String>[];
  final openedBytes = <(int, String, String)>[]; // (바이트 수, mime, 이름)
  final focus = StreamController<void>.broadcast();

  Device get device => Device(
        filesDir: () async => files.path,
        hasWindowFocus: () async => focused,
        readClipboard: () async => clipboard,
        clearClipboard: () async {
          if (clearFails) throw StateError('지우기 실패');
          cleared++;
          clipboard = null;
        },
        notificationsEnabled: () async => notifications,
        requestNotificationPermission: () async {},
        openNotificationSettings: () async => notifSettings++,
        windowFocus: focus.stream,
        openAppSettings: () async => appSettings++,
        openUrl: (u) async => opened.add(u),
        openBytes: (d, m, n) async => openedBytes.add((d.length, m, n)),
      );
}

class FakeRecorder implements Recorder {
  FakeRecorder({this.permitted = true, this.bytes = 2048});
  bool permitted;

  /// 멈출 때 녹음 파일에 쓰는 바이트 수(0이면 빈 파일, 음수면 파일을 만들지 않는다).
  int bytes;
  String? path;
  int starts = 0, stops = 0;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<void> start(String p) async {
    starts++;
    path = p;
  }

  @override
  Future<String?> stop() async {
    stops++;
    if (bytes >= 0) File(path!).writeAsBytesSync(Uint8List(bytes));
    return path;
  }
}

/// 목록 화면 의존성 — 채널 호출은 [dev]가 받아 적는다.
CollectionDeps fakeListDeps(PhoneStore store, FakeDevice dev,
        {RecordReader? reader, RecordDeleter? deleter, ChangeSignal? changed, DateTime Function()? now}) =>
    CollectionDeps(
      collection: Collection(reader: () => reader ?? store, deleter: () => deleter ?? store, now: now ?? DateTime.now),
      openUrl: dev.device.openUrl!,
      openBytes: dev.device.openBytes!,
      changed: changed,
      now: now ?? DateTime.now,
    );

/// `records/` 아래에 수집물 한 건(원본 + 사이드카)을 직접 놓는다 — 기존판 형식(`device: pc` 등)도 만들 수 있다.
/// [at] = `YYYYMMDD-HHMMSS`, [id8] = 8자 16진. 돌려주는 값 = base.
String putRecord(
  Directory records,
  String at,
  String id8, {
  String kind = 'text',
  String body = '본문',
  Uint8List? bytes,
  String ext = 'txt',
  String input = 'paste',
  String device = 'phone',
  String mime = 'text/plain',
  String? caption,
  String? originalName,
  String? source,
  String? groupId,
  int? groupSize,
  bool original = true,
  bool sidecar = true,
}) {
  final base = '${at}_$id8';
  final dir = Directory('${records.path}/${at.substring(0, 4)}-${at.substring(4, 6)}')..createSync(recursive: true);
  final data = bytes ?? Uint8List.fromList(utf8.encode(body));
  if (original) File('${dir.path}/$base.$ext').writeAsBytesSync(data);
  if (sidecar) {
    final iso = '${at.substring(0, 4)}-${at.substring(4, 6)}-${at.substring(6, 8)}'
        'T${at.substring(9, 11)}:${at.substring(11, 13)}:${at.substring(13, 15)}+09:00';
    File('${dir.path}/$base.meta.json').writeAsStringSync(jsonEncode({
      'schema_version': 1,
      'id': '$id8-0000-4000-8000-000000000000',
      'collected_at': iso,
      'input': input,
      'kind': kind,
      'source': source,
      'device': device,
      'original_name': originalName,
      'mime': mime,
      'size': data.length,
      'md5': record.md5Hex(data),
      'caption': caption,
      'group_id': groupId,
      'group_size': groupSize,
    }));
  }
  return base;
}

/// 달 폴더 안 파일 이름(정렬).
List<String> namesIn(Directory records, String month) {
  final d = Directory('${records.path}/$month');
  if (!d.existsSync()) return const [];
  return [for (final f in d.listSync().whereType<File>()) f.uri.pathSegments.last]..sort();
}

/// 읽기·지우기 호출을 세고, 고른 경로에서 실패시키는 저장소.
class CountingStore implements RecordReader, RecordDeleter {
  CountingStore(this.inner);
  final PhoneStore inner;
  int listings = 0;
  final reads = <String>[];
  final deletes = <String>[];
  bool Function(String path)? failRead;
  bool Function(String path)? failDelete;

  @override
  Future<List<String>> months() {
    listings++;
    return inner.months();
  }

  @override
  Future<List<StoreEntry>> files(String month) => inner.files(month);

  /// 걸어 두면 읽기가 이것이 끝날 때까지 기다린다 — 새로 고침을 중간에 멈춰 세울 때.
  Future<void>? gate;

  @override
  Future<Uint8List> read(String path) async {
    reads.add(path);
    if (gate != null) await gate;
    if (failRead?.call(path) ?? false) throw const FileSystemException('읽기 오류(테스트)');
    return inner.read(path);
  }

  @override
  Future<bool> delete(String path) {
    if (failDelete?.call(path) ?? false) throw const FileSystemException('지우기 오류(테스트)');
    deletes.add(path);
    return inner.delete(path);
  }
}
