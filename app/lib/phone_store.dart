/// F-035 폰 안 저장 — 수집물 나무(`records/YYYY-MM/`)를 읽고·쓰고·지우는 유일한 곳. 형식의 결정은 docs/SCHEMA.md.
///
/// 기존판의 Drive 경계(읽기·쓰기·지우기 인터페이스) 자리에 들어간다. 읽기만 하는 쪽(목록)은 [RecordReader]만,
/// 지우기는 [RecordDeleter]만 받는다 — 쓰기·지우기는 타입에 없어 부를 수 없다.
/// 파일은 한 번 쓰면 고치지 않는다(SCHEMA 설계 원칙 4): 같은 이름이 있으면 쓰기를 거부한다.
library;

import 'dart:io';
import 'dart:typed_data';

import 'atomic_file.dart';
import 'log.dart';
import 'record.dart' as record;
import 'sender.dart';

/// 나무 안 파일 하나. [path] = files 폴더 기준 상대 경로 `records/YYYY-MM/<이름>` — 수집물 파일을 가리키는 유일한 방법
/// (SCHEMA '수집물을 가리키는 방법').
class StoreEntry {
  const StoreEntry(this.path, this.name);
  final String path;
  final String name;
}

/// 읽기 전용.
abstract class RecordReader {
  /// `records/` 바로 아래 폴더 이름 전부(달 폴더가 아닌 이름도 그대로 — 거르는 것은 읽는 쪽).
  Future<List<String>> months();

  /// 그 달 폴더의 파일 전부(하위 폴더 제외). 폴더가 없으면 빈 목록.
  Future<List<StoreEntry>> files(String month);

  Future<Uint8List> read(String path);
}

/// 지우기(F-018) — 사용자가 목록에서 고르고 확인했을 때만 부른다.
abstract class RecordDeleter {
  /// 파일 하나를 지운다. 이미 없으면 false.
  Future<bool> delete(String path);
}

/// 수집물 저장 실패 — 반쪽 파일은 이미 지웠다. [userMessage]는 화면·알림에 그대로 쓴다(원인은 로그에만).
class SaveFailed implements Exception {
  SaveFailed(this.base, this.cause);
  final String base;
  final Object cause;

  String get userMessage => '저장하지 못했습니다';

  @override
  String toString() => 'SaveFailed($base, ${cause.runtimeType})';
}

const recordsFolder = 'records';

final _monthRe = RegExp(r'^\d{4}-\d{2}$');
final _pathRe = RegExp('^$recordsFolder/(\\d{4}-\\d{2})/([^/\\\\]+)\$');

/// 파일 이름으로 쓸 수 있나 — 경로 조각(`/`·`\`·제어 문자·`.`·`..`)이 섞이면 안 된다.
/// 원본 확장자는 공유해 온 앱이 준 파일 이름에서 나온다(밖에서 들어오는 입력).
bool isSafeFileName(String name) =>
    name.isNotEmpty && name != '.' && name != '..' && !name.contains(RegExp(r'[/\\\x00-\x1f]'));

class PhoneStore implements RecordReader, RecordDeleter {
  /// [root] = `AppPaths.records`. [write]는 테스트가 쓰기 오류를 일으키는 자리.
  PhoneStore(this.root, {void Function(File f, Object data)? write}) : _write = write ?? _atomic;

  static void _atomic(File f, Object data) => writeAtomicSync(f, data);

  final Directory root;
  final void Function(File f, Object data) _write;

  File _file(String path) {
    final m = _pathRe.firstMatch(path);
    if (m == null || !isSafeFileName(m.group(2)!)) throw ArgumentError.value(path, 'path', '수집물 나무 안 경로가 아님');
    return File('${root.path}/${m.group(1)}/${m.group(2)}');
  }

  @override
  Future<List<String>> months() async {
    if (!await root.exists()) return const [];
    return [
      await for (final e in root.list())
        if (e is Directory) e.uri.pathSegments.where((s) => s.isNotEmpty).last,
    ];
  }

  @override
  Future<List<StoreEntry>> files(String month) async {
    if (!_monthRe.hasMatch(month)) throw ArgumentError.value(month, 'month', '달 폴더 이름이 아님');
    final dir = Directory('${root.path}/$month');
    if (!await dir.exists()) return const [];
    return [
      await for (final e in dir.list())
        if (e is File) _entry(month, e.uri.pathSegments.last),
    ];
  }

  StoreEntry _entry(String month, String name) => StoreEntry('$recordsFolder/$month/$name', name);

  @override
  Future<Uint8List> read(String path) => _file(path).readAsBytes();

  @override
  Future<bool> delete(String path) async {
    final f = _file(path);
    if (!await f.exists()) return false;
    await f.delete();
    return true;
  }

  /// 수집물 한 건을 쓴다 — **원본 먼저, 사이드카 나중**(사이드카가 있어야 수집물이다, SCHEMA '쓰기 순서와 미완성 판정').
  /// 실패하면 이미 쓴 반쪽 파일을 지우고 [SaveFailed]. 같은 이름이 이미 있으면 건드리지 않고 [SaveFailed].
  StoreEntry save(NewRecord item, Uint8List data) {
    final File orig, meta;
    final String month;
    try {
      if (!isSafeFileName(item.originalName) || !isSafeFileName(item.metaName)) {
        throw const FormatException('파일 이름에 경로 조각이 섞임');
      }
      month = record.monthFolder(item.sidecar['collected_at'] as String);
      final dir = Directory('${root.path}/$month')..createSync(recursive: true);
      orig = File('${dir.path}/${item.originalName}');
      meta = File('${dir.path}/${item.metaName}');
      if (orig.existsSync() || meta.existsSync()) throw StateError('같은 이름의 수집물이 이미 있음');
    } on Object catch (e, st) {
      // 아직 아무것도 쓰지 않았다 — 지울 것이 없다(이미 있던 파일은 남의 것이라 건드리지 않는다).
      logError('저장 실패(쓰기 전) ${item.base}', e, st);
      throw SaveFailed(item.base, e);
    }
    try {
      _write(orig, data);
      _write(meta, sidecarBytes(item.sidecar));
    } on Object catch (e, st) {
      logError('저장 실패 ${item.base} — 반쪽 파일을 지운다', e, st);
      for (final f in [meta, File('${meta.path}.tmp'), orig, File('${orig.path}.tmp')]) {
        _removeHalf(f);
      }
      throw SaveFailed(item.base, e);
    }
    return _entry(month, item.originalName);
  }

  /// 방금 [save]한 건을 되돌린다 — 한 번의 공유에서 일부가 실패하면 저장된 것도 모두 되돌린다(F-002).
  /// 사이드카를 먼저 지운다(중간에 멈춰도 수집물로 보이지 않게). 지우기 실패는 로그만.
  void undo(NewRecord item) {
    final dir = '${root.path}/${record.monthFolder(item.sidecar['collected_at'] as String)}';
    _removeHalf(File('$dir/${item.metaName}'));
    _removeHalf(File('$dir/${item.originalName}'));
  }

  void _removeHalf(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } on Object catch (e) {
      // 지우지 못한 반쪽은 사이드카가 없어 수집물로 보이지 않고 '읽지 못함'으로 세어진다.
      logError('반쪽 파일 지우기 실패(${f.uri.pathSegments.last.length}자 이름)', e);
    }
  }
}
