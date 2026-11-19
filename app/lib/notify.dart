/// 공유 결과 알림(F-002) — 공유 엔진은 화면이 없어 결과를 알림으로만 알린다: 성공 '채록 저장됨', 실패 '저장 실패'.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'log.dart';

typedef Notify = Future<void> Function(String title, String body, {int id});

/// 알림 자리. 같은 자리의 새 알림은 앞 알림을 바꾼다.
/// 저장 결과는 한 자리(최신 결과만 의미 있다), 공유를 받을 때의 안내(용량 초과·빈 내용·받기 실패)는
/// 다른 자리 — 같은 자리면 곧이어 오는 '저장됨'이 '용량 초과'를 덮어 동영상이 빠진 걸 모르게 된다.
const resultId = 1;
const noticeId = 2;

final _plugin = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  await _plugin.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('ic_launcher_foreground')),
  );
}

Future<void> showNotification(String title, String body, {int id = resultId}) async {
  try {
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'result', '저장 결과',
          channelDescription: '채록 저장됨 / 저장 실패',
          importance: Importance.defaultImportance,
        ),
      ),
    );
  } on Object catch (e, st) {
    // 알림이 꺼져 있으면 여기로 온다 — 앱을 열면 화면 위 띠가 알림이 꺼졌다고 알린다. 저장 결과 자체는 로그에 있다.
    logError('알림 표시 실패: $title', e, st);
  }
}
