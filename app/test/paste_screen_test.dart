// F-003 붙여넣기 · F-007 녹음 · F-017 비우기 — 눈으로 안 보이는 동작(저장 결과·건수·상태 문구·신호)을 건다. 모양은 사용자 실테스트.
import 'dart:convert';
import 'dart:io';

import 'package:chaerok/atomic_file.dart';
import 'package:chaerok/change_signal.dart';
import 'package:chaerok/log.dart';
import 'package:chaerok/paste_screen.dart';
import 'package:chaerok/phone_store.dart';
import 'package:chaerok/record.dart' as record;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late Directory tmp, records;
  late FakeDevice dev;
  late PhoneStore store;
  late ChangeSignal signal;
  late DateTime clock;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chaerok_paste');
    records = Directory('${tmp.path}/records');
    initLog(tmp);
    dev = FakeDevice(tmp);
    store = PhoneStore(records);
    signal = ChangeSignal(File('${tmp.path}/changed.txt'))..start();
    clock = DateTime(2026, 11, 19, 14, 5);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String log() => File('${tmp.path}/chaerok.log').readAsStringSync();
  List<File> files(String suffix) => records.existsSync()
      ? records.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith(suffix)).toList()
      : [];
  Map<String, Object?> meta() => (jsonDecode(files('.meta.json').single.readAsStringSync()) as Map).cast();

  Future<void> open(WidgetTester t, {PhoneStore? to, FakeRecorder? rec, Duration? limit}) async {
    await t.pumpWidget(MaterialApp(
      home: PasteScreen(
        store: to ?? store,
        device: dev.device,
        now: () => clock,
        changed: signal,
        sentClipFile: File('${tmp.path}/sent_clip.md5'),
        recorder: rec,
        voiceLimit: limit ?? const Duration(minutes: 60),
      ),
    ));
    await t.pumpAndSettle();
  }

  Future<void> send(WidgetTester t) async {
    await t.tap(find.text('보내기'));
    await t.pumpAndSettle();
  }

  String field(WidgetTester t) => t.widget<TextField>(find.byType(TextField)).controller!.text;

  group('F-003 붙여넣기', () {
    testWidgets('포커스를 얻으면 클립보드 글이 칸에 채워지고 "클립보드에서 채움"', (t) async {
      dev.clipboard = '복사한 글';
      await open(t);
      expect(field(t), '복사한 글');
      expect(find.text('클립보드에서 채움'), findsOneWidget);
      dev.clipboard = '돌아와서 새로 복사';
      dev.focus.add(null);
      await t.pumpAndSettle();
      expect(field(t), '돌아와서 새로 복사');
    });

    testWidgets('보내기 → 고친 내용 그대로 수집물 1건(input paste·device phone·source null), 칸이 비고 "저장됨 · 14:05", 신호 바뀜', (t) async {
      dev.clipboard = '원래 글';
      await open(t);
      await t.enterText(find.byType(TextField), '  고친 글\n');
      await send(t);
      expect(utf8.decode(files('.txt').single.readAsBytesSync()), '  고친 글\n'); // 앞뒤 공백을 고치지 않는다
      final m = meta();
      expect([m['input'], m['device'], m['source'], m['kind']], ['paste', 'phone', null, 'text']);
      expect(field(t), '');
      expect(find.text('저장됨 · 14:05'), findsOneWidget);
      expect(signal.changed(), isTrue);
    });

    testWidgets('링크 하나면 kind url', (t) async {
      await open(t);
      await t.enterText(find.byType(TextField), ' https://example.com/a ');
      await send(t);
      expect(meta()['kind'], 'url');
    });

    testWidgets('빈 칸(공백뿐 포함) 보내기 → 저장 0건, "빈 칸은 보내지 않습니다"', (t) async {
      await open(t);
      await send(t);
      await t.enterText(find.byType(TextField), ' \n\t');
      await send(t);
      expect(files(''), isEmpty);
      expect(find.text('빈 칸은 보내지 않습니다'), findsOneWidget);
      expect(signal.changed(), isFalse);
    });

    testWidgets('저장 실패 → 실패 문구, 칸의 글은 그대로, records에 파일 0개, 로그 1줄 / 다시 보내면 새 1건', (t) async {
      var fail = true;
      final flaky = PhoneStore(records, write: (f, d) {
        if (fail) throw const FileSystemException('디스크 가득(테스트)');
        writeAtomicSync(f, d);
      });
      await open(t, to: flaky);
      await t.enterText(find.byType(TextField), '비밀글XYZ');
      await send(t);
      expect(find.text('저장하지 못했습니다 — 칸의 내용은 그대로 있습니다'), findsOneWidget);
      expect(field(t), '비밀글XYZ');
      expect(files(''), isEmpty);
      expect('저장 실패'.allMatches(log()).length, 1);
      expect(log(), isNot(contains('XYZ')));
      expect(signal.changed(), isFalse);
      fail = false;
      await send(t);
      expect(files('.txt').length, 1);
      expect(field(t), '');
    });

    testWidgets('한 번 채운 클립보드는 지우거나 보낸 뒤 앱을 다시 켜도 자동으로 다시 채우지 않는다 / 다시 채우기 버튼으로는 채운다', (t) async {
      dev.clipboard = '한 번만';
      await open(t);
      await t.enterText(find.byType(TextField), '');
      // 기억 파일에는 MD5만 남는다(글 자체는 남기지 않는다)
      expect(File('${tmp.path}/sent_clip.md5').readAsStringSync(), record.md5Hex(utf8.encode('한 번만')));
      dev.focus.add(null);
      await t.pumpAndSettle();
      expect(field(t), '');
      await t.pumpWidget(const SizedBox()); // 앱을 껐다
      await open(t);
      expect(field(t), '');
      await t.tap(find.byTooltip('클립보드에서 다시 채우기'));
      await t.pumpAndSettle();
      expect(field(t), '한 번만');
    });

    testWidgets('화면에 "보내지 못한 것"·"재전송"·"전송 실패"·"보관 중"이 나오지 않고, 로그에 칸의 글이 없다', (t) async {
      dev.clipboard = '클립비밀XYZ';
      await open(t);
      await send(t);
      for (final w in ['보내지 못한 것', '재전송', '전송 실패', '보관 중']) {
        expect(find.textContaining(w), findsNothing, reason: w);
      }
      expect(log(), isNot(contains('XYZ')));
    });

    testWidgets('알림이 꺼져 있으면 띠가 보이고 누르면 알림 설정, 켜고 돌아오면 사라진다', (t) async {
      dev.notifications = false;
      await open(t);
      final banner = find.text('알림이 꺼져 있어 공유 결과를 못 봅니다 · 설정');
      expect(banner, findsOneWidget);
      await t.tap(banner);
      expect(dev.notifSettings, 1);
      dev.notifications = true;
      dev.focus.add(null);
      await t.pumpAndSettle();
      expect(banner, findsNothing);
    });
  });

  group('F-017 비우기', () {
    testWidgets('비우기 → 칸·클립보드 비움, "칸과 클립보드를 비움", 돌아와도 다시 안 채움', (t) async {
      dev.clipboard = '지울 글';
      await open(t);
      await t.tap(find.byTooltip('비우기(칸·클립보드)'));
      await t.pumpAndSettle();
      expect(field(t), '');
      expect(dev.cleared, 1);
      expect(find.text('칸과 클립보드를 비움'), findsOneWidget);
      dev.focus.add(null);
      await t.pumpAndSettle();
      expect(field(t), '');
    });

    testWidgets('클립보드 지우기 실패 → 칸은 비우고 "칸은 비웠지만 클립보드는 지우지 못했습니다"', (t) async {
      dev.clipboard = '지울 글';
      dev.clearFails = true;
      await open(t);
      await t.tap(find.byTooltip('비우기(칸·클립보드)'));
      await t.pumpAndSettle();
      expect(field(t), '');
      expect(find.text('칸은 비웠지만 클립보드는 지우지 못했습니다'), findsOneWidget);
    });

    testWidgets('녹음 중에는 비우기 버튼이 꺼져 있다', (t) async {
      final rec = FakeRecorder();
      await open(t, rec: rec);
      await t.tap(find.byIcon(Icons.mic_none));
      await t.pump();
      expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.backspace_outlined)).onPressed, isNull);
      clock = clock.add(const Duration(seconds: 2));
      await t.tap(find.text('완료 · 저장'));
      await t.pumpAndSettle();
    });
  });

  group('F-007 녹음', () {
    Future<FakeRecorder> start(WidgetTester t, {FakeRecorder? rec, Duration? limit, PhoneStore? to}) async {
      final r = rec ?? FakeRecorder();
      await open(t, rec: r, limit: limit, to: to);
      await t.tap(find.byIcon(Icons.mic_none));
      await t.pump();
      return r;
    }

    Future<void> stop(WidgetTester t) async {
      await t.tap(find.text('완료 · 저장'));
      await t.pumpAndSettle();
    }

    testWidgets('녹음 → 완료 · 저장 → 수집물 1건(.m4a·audio/mp4·input voice·kind file·이름 null), 상태 줄, 임시 파일 없음, 신호 바뀜', (t) async {
      final rec = await start(t);
      expect(find.textContaining('녹음 중 · 최대 60:00'), findsOneWidget);
      clock = clock.add(const Duration(seconds: 65));
      await stop(t);
      expect(files('.m4a').single.lengthSync(), 2048);
      final m = meta();
      expect([m['input'], m['kind'], m['mime'], m['original_name'], m['device']], ['voice', 'file', 'audio/mp4', null, 'phone']);
      expect(find.text('저장됨 · 녹음 01:05 · 14:06'), findsOneWidget);
      expect(File(rec.path!).existsSync(), isFalse);
      expect(signal.changed(), isTrue);
    });

    for (final (state, saved) in [(AppLifecycleState.inactive, 0), (AppLifecycleState.hidden, 1), (AppLifecycleState.paused, 1)]) {
      testWidgets('녹음 중 ${state.name} → 저장 $saved건(알림창 내리기는 멈추지 않는다)', (t) async {
        await start(t);
        clock = clock.add(const Duration(seconds: 5));
        // 안드로이드가 거치는 순서대로: resumed → inactive → hidden → paused, 돌아올 때는 거꾸로.
        const down = [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused];
        final path = down.sublist(0, down.indexOf(state) + 1);
        for (final s in path) {
          t.binding.handleAppLifecycleStateChanged(s);
        }
        await t.pumpAndSettle();
        expect(files('.m4a').length, saved);
        for (final s in [...path.reversed.skip(1), AppLifecycleState.resumed]) {
          t.binding.handleAppLifecycleStateChanged(s);
        }
        await t.pumpAndSettle();
        if (saved == 0) {
          await stop(t);
        } else {
          expect(find.text('저장됨 · 녹음 00:05 · 14:05'), findsOneWidget); // 돌아오면 보인다
        }
      });
    }

    testWidgets('상한: 59분 59초에는 녹음 중, 60분 00초에 자동으로 멈추고 저장 1건', (t) async {
      await start(t);
      clock = clock.add(const Duration(minutes: 59, seconds: 59));
      await t.pump(const Duration(seconds: 1));
      expect(files('.m4a'), isEmpty);
      expect(find.text('완료 · 저장'), findsOneWidget);
      clock = clock.add(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(files('.m4a').length, 1);
      expect(find.text('저장됨 · 녹음 60:00 · 15:05'), findsOneWidget);
    });

    testWidgets('1초 미만: 999ms는 저장 0건 "너무 짧아 저장하지 않음" / 1,000ms는 1건', (t) async {
      final rec = await start(t);
      clock = clock.add(const Duration(milliseconds: 999));
      await stop(t);
      expect(files('.m4a'), isEmpty);
      expect(find.text('너무 짧아 저장하지 않음'), findsOneWidget);
      expect(File(rec.path!).existsSync(), isFalse);
      await t.tap(find.byIcon(Icons.mic_none));
      await t.pump();
      clock = clock.add(const Duration(milliseconds: 1000));
      await stop(t);
      expect(files('.m4a').length, 1);
    });

    testWidgets('마이크 권한 거부 → 녹음 안 함, 문구 + 설정(앱 정보 화면)', (t) async {
      final rec = await start(t, rec: FakeRecorder(permitted: false));
      expect(rec.starts, 0);
      expect(find.text('마이크 권한이 꺼져 있어 녹음할 수 없습니다'), findsOneWidget);
      await t.tap(find.text('설정'));
      await t.pumpAndSettle();
      expect(dev.appSettings, 1);
    });

    testWidgets('녹음 파일이 0바이트 → "녹음 파일을 만들지 못했습니다", 저장 0건', (t) async {
      await start(t, rec: FakeRecorder(bytes: 0));
      clock = clock.add(const Duration(seconds: 3));
      await stop(t);
      expect(files(''), isEmpty);
      expect(find.text('녹음 파일을 만들지 못했습니다'), findsOneWidget);
    });

    testWidgets('저장 실패 → "녹음을 저장하지 못했습니다", records에 파일 0개, 임시 녹음 파일은 남는다', (t) async {
      final failing = PhoneStore(records, write: (f, d) => throw const FileSystemException('디스크 가득(테스트)'));
      final rec = await start(t, to: failing);
      clock = clock.add(const Duration(seconds: 3));
      await stop(t);
      expect(files(''), isEmpty);
      expect(find.text('녹음을 저장하지 못했습니다'), findsOneWidget);
      expect(File(rec.path!).existsSync(), isTrue);
      expect(signal.changed(), isFalse);
    });

    testWidgets('화면이 사라질 때 녹음 중이었으면 그때까지의 것이 저장된다', (t) async {
      await start(t);
      clock = clock.add(const Duration(seconds: 4));
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(files('.m4a').length, 1);
    });
  });
}
