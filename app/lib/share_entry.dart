/// 공유 메뉴 진입점(ShareActivity.kt의 Dart 쪽) — **공유 엔진**. 화면을 그리지 않는다: 받아서 폰에 저장하고 알린 뒤 닫는다.
///
/// 순서: Kotlin이 content:// 파일을 앱 폴더로 복사(Activity가 끝나면 읽기 권한이 사라진다) → 여기서 수집물로 만들어
/// 수집물 나무에 바로 저장 → 결과 알림 → 닫기. 확인 화면은 없다(F-002).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_paths.dart';
import 'change_signal.dart';
import 'log.dart';
import 'notify.dart';
import 'phone_store.dart';
import 'sender.dart';
import 'share.dart';

const _ch = MethodChannel('chaerok/share');

Future<void> runShare() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink()); // 투명 — 아무것도 그리지 않는다
  String? inbox;
  try {
    final files = Directory((await _ch.invokeMethod<String>('filesDir'))!);
    initLog(files);
    await initNotifications();
    final raw = (await _ch.invokeMapMethod<Object?, Object?>('takeShare'))!;
    inbox = raw['inbox'] as String?;
    final paths = AppPaths(files.path);
    await collectShare(ShareInput.fromMap(raw), PhoneStore(paths.records),
        notify: showNotification, changed: ChangeSignal(paths.changed));
  } on Object catch (e, st) {
    logError('공유 받기 실패', e, st);
    await _notifyFailure();
  } finally {
    _removeInboxLogged(inbox);
    await _ch.invokeMethod<void>('finish');
  }
}

/// 실패 알림 — 알림이 또 던져도 삼키고 로그만(던지게 두면 투명 화면이 닫히지 않는다). 알림 초기화가 실패한 경우가 바로 그 상황이다.
Future<void> _notifyFailure() async {
  try {
    await showNotification('저장 실패', '공유를 받지 못했습니다 — 다시 공유하세요', id: noticeId);
  } on Object catch (e, st) {
    logError('공유 실패 알림도 못 띄움', e, st);
  }
}

void _removeInboxLogged(String? inbox) {
  try {
    removeInbox(inbox);
  } on Object catch (e, st) {
    // 사본이 남을 뿐 수집물은 이미 나무에 있다 — 닫기는 계속한다.
    logError('공유 사본 폴더 지우기 실패', e, st);
  }
}

/// 복사해 둔 공유 파일 폴더를 지운다. 저장할 것은 이미 수집물 나무로 옮겨졌다.
void removeInbox(String? inbox) {
  if (inbox == null) return;
  final d = Directory(inbox);
  if (d.existsSync()) d.deleteSync(recursive: true);
}

/// 받은 것을 수집물로 만들어 폰에 저장하고 결과를 알린다. 용량 초과·빈 내용은 안내 알림으로.
/// F-029 1건이라도 저장했으면 [changed]에 신호를 쓴다(열린 목록이 새로 고친다).
Future<void> collectShare(
  ShareInput input,
  PhoneStore store, {
  required Notify notify,
  ChangeSignal? changed,
  DateTime Function() now = DateTime.now,
}) async {
  final result = buildShare(input, (p) => File(p).readAsBytesSync());
  final done = <NewRecord>[];
  var failed = false;
  final items = result.items.iterator;
  while (true) {
    try {
      if (!items.moveNext()) break; // 여기서 그 건의 파일을 읽는다 — 읽기 실패도 아래에서 되돌린다
      final (item, data) = items.current;
      store.save(item, data);
      done.add(item);
      logInfo('공유 수집: ${item.id} ${item.sidecar['kind']} source=${item.sidecar['source']}');
    } on Object catch (e, st) {
      if (e is! SaveFailed) logError('공유받은 파일 읽기 실패', e, st);
      // 원인은 PhoneStore.save가 로그에 남겼다. 일부만 남기지 않는다(사용자 결정 2026-11-19) —
      // 사이드카의 group_size가 이미 정해져 있어, 일부만 남으면 묶음이 영영 'N장 중 M장'이다.
      failed = true;
      logWarn('공유 저장 실패 — 이번 공유로 쓴 ${done.length}건을 되돌린다(전체 ${result.count}건)');
      done.forEach(store.undo);
      done.clear();
      break;
    }
  }
  final saved = done.length;
  if (saved > 0) changed?.mark(now());
  if (result.tooBig.isNotEmpty) {
    logWarn('용량 초과로 저장 안 함: ${result.tooBig.length}개');
    await notify('용량 초과(상한 100MB)', '${result.tooBig.join(', ')} — 저장하지 않았습니다', id: noticeId);
  }
  if (result.empty) {
    logWarn('공유받은 내용이 비어 있음');
    await notify('보낼 내용 없음', '공유받은 내용이 비어 있습니다', id: noticeId);
  }
  if (failed) {
    await notify('저장 실패', '공유를 받지 못했습니다 — 다시 공유하세요');
  } else if (saved > 0) {
    await notify('채록 저장됨', '$saved건 저장됨');
  }
}
