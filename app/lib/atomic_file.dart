/// 임시 파일에 끝까지 쓰고(flush) 바꿔치기 — 쓰다가 앱이 죽어도 원래 파일이 남거나 새 파일이 통째로 있다.
/// D1(debt-audit 2026-11-15): 같은 세 줄이 8곳에 따로 있었다. 쓰는 주체(화면·백그라운드)는 부르는 쪽이라
/// `file_writers_test` 등록부는 이 함수를 부르는 곳을 센다(이 파일은 센 수에서 뺀다).
library;

import 'dart:io';

File _tmp(File f) => File('${f.path}.tmp');

/// 글 또는 바이트([List<int>])를 [f]에 바꿔치기로 쓴다.
void writeAtomicSync(File f, Object data) {
  final tmp = _tmp(f);
  if (data is String) {
    tmp.writeAsStringSync(data, flush: true);
  } else {
    tmp.writeAsBytesSync(data as List<int>, flush: true);
  }
  tmp.renameSync(f.path);
}

/// [writeAtomicSync]의 비동기판(글만).
Future<void> writeAtomic(File f, String data) async {
  final tmp = _tmp(f);
  await tmp.writeAsString(data, flush: true);
  await tmp.rename(f.path);
}
