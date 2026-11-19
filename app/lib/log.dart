/// 앱 로그 — 디버그 콘솔(adb logcat)과 앱 폴더의 파일 둘 다에 쓴다(Silent failure 금지).
///
/// 파일: <앱 files 폴더>/chaerok.log. 1MB를 넘으면 chaerok.log.1로 한 번 밀어 둔다(오래된 것 하나만 남김).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

const _maxBytes = 1024 * 1024;

File? _file;

/// 앱 시작 때 한 번. 부르기 전의 로그는 콘솔에만 간다.
void initLog(Directory dir) {
  final f = File('${dir.path}/chaerok.log');
  try {
    if (f.existsSync() && f.lengthSync() > _maxBytes) {
      f.renameSync('${f.path}.1');
    }
  } on FileSystemException catch (e) {
    debugPrint('[chaerok] 로그 파일 밀어 두기 실패(계속 씀): $e');
  }
  _file = f;
}

void _write(String level, String msg) {
  final line = '${DateTime.now().toIso8601String()} $level $msg';
  debugPrint('[chaerok] $line');
  final f = _file;
  if (f == null) return;
  try {
    f.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } on FileSystemException catch (e) {
    // 로그 파일을 못 쓰는 것 때문에 수집을 멈추지 않는다 — 콘솔에는 남는다.
    debugPrint('[chaerok] 로그 파일 쓰기 실패: $e');
  }
}

void logInfo(String msg) => _write('INFO', msg);
void logWarn(String msg) => _write('WARN', msg);
void logError(String msg, [Object? error, StackTrace? st]) =>
    _write('ERROR', '$msg${error == null ? '' : ' — $error'}${st == null ? '' : '\n$st'}');
