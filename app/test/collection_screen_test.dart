// F-010 항목 보기 · F-018 확인 창 · F-029 열린 목록의 자동 갱신 — 눈으로 안 보이는 동작(복사 결과·채널 호출·삭제 건수·폴더 읽기 횟수).
// 모양은 사용자 실테스트.
import 'dart:io';

import 'package:chaerok/change_signal.dart';
import 'package:chaerok/collection_screen.dart';
import 'package:chaerok/log.dart';
import 'package:chaerok/phone_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'io_settle.dart';

void main() {
  late Directory tmp, records;
  late FakeDevice dev;
  late CountingStore store;
  late ChangeSignal signal;
  String? clipboard;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chaerok_screen');
    records = Directory('${tmp.path}/records');
    initLog(tmp);
    dev = FakeDevice(tmp);
    store = CountingStore(PhoneStore(records));
    signal = ChangeSignal(File('${tmp.path}/changed.txt'));
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.setData') clipboard = (c.arguments as Map)['text'] as String?;
      return null;
    });
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> open(WidgetTester t, {bool watch = false}) async {
    await t.pumpWidget(MaterialApp(
      home: CollectionScreen(
          deps: fakeListDeps(store.inner, dev,
              reader: store, deleter: store, changed: watch ? signal : null, now: () => DateTime(2026, 11, 19, 12))),
    ));
    await settleUntil(t, find.textContaining('전체 '));
  }

  Future<void> tapItem(WidgetTester t, String text) async {
    await t.tap(find.text(text));
    await t.pumpAndSettle();
    await settleIo(t);
  }

  testWidgets('텍스트 항목: 원문 전체가 보이고 복사 → 클립보드 = 원문 전체 / 브라우저로 열기는 없다', (t) async {
    putRecord(records, '20261119-100000', 'aaaaaaaa', body: '니체의 문장 전체');
    await open(t);
    await tapItem(t, '니체의 문장 전체');
    expect(find.text('브라우저로 열기'), findsNothing);
    await t.tap(find.text('복사'));
    await t.pumpAndSettle();
    expect(clipboard, '니체의 문장 전체');
  });

  testWidgets('링크 항목: 브라우저로 열기 → 그 주소로 열기 채널 호출 1회', (t) async {
    putRecord(records, '20261119-100000', 'aaaaaaaa', kind: 'url', body: ' https://example.com/a \n');
    await open(t);
    await tapItem(t, 'https://example.com/a');
    await t.tap(find.text('브라우저로 열기'));
    await t.pumpAndSettle();
    expect(dev.opened, ['https://example.com/a']);
  });

  testWidgets('녹음 항목: 재생 → 폰 기본 앱 열기 1회(MIME = 사이드카 mime), 복사는 없다 / 그 외 파일은 이름 · 크기만', (t) async {
    putRecord(records, '20261119-100000', 'aaaaaaaa',
        kind: 'file', input: 'voice', ext: 'm4a', mime: 'audio/mp4', bytes: Uint8List(3000));
    putRecord(records, '20261119-090000', 'bbbbbbbb',
        kind: 'file', input: 'share', ext: 'zip', mime: 'application/zip', bytes: Uint8List(2048), originalName: '자료.zip');
    await open(t);
    await tapItem(t, '녹음');
    expect(find.text('복사'), findsNothing);
    await t.tap(find.text('재생'));
    await t.pump();
    await settleUntil(t, find.text('재생')); // 여는 동안은 '여는 중…'
    expect(dev.openedBytes, [(3000, 'audio/mp4', '20261119-100000_aaaaaaaa.m4a')]);
    await t.pageBack();
    await t.pumpAndSettle();
    await tapItem(t, '자료.zip');
    expect(find.text('자료.zip · 2.0 KB'), findsOneWidget);
    expect(find.text('재생'), findsNothing);
  });

  testWidgets('이미지 항목: 폰 파일을 1번 읽어 보인다 / 원본이 사라졌으면 "이미지를 못 읽음" + 다시 시도', (t) async {
    final b = putRecord(records, '20261119-100000', 'aaaaaaaa',
        kind: 'image', input: 'share', ext: 'png', mime: 'image/png', bytes: Uint8List(8), originalName: '사진.png');
    await open(t);
    store.reads.clear();
    File('${records.path}/2026-11/$b.png').deleteSync();
    await t.tap(find.text('사진.png')); // 읽는 동안 돌아가는 표시가 있어 pumpAndSettle로 기다릴 수 없다
    await t.pump();
    await settleUntil(t, find.text('이미지를 못 읽음'));
    expect(store.reads, ['records/2026-11/$b.png']);
    expect(find.text('이미지를 못 읽음'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('목록·항목 보기에 "Drive"·"이것으로 대화하기"·"보내지 못한 것"이 없다', (t) async {
    putRecord(records, '20261119-100000', 'aaaaaaaa', body: '글');
    await open(t);
    for (final w in ['Drive', '보내지 못한 것']) {
      expect(find.textContaining(w), findsNothing, reason: w);
    }
    await tapItem(t, '글');
    for (final w in ['Drive', '이것으로 대화하기', '카테고리']) {
      expect(find.textContaining(w), findsNothing, reason: w);
    }
  });

  testWidgets('F-018 길게 누름 → 확인 창 취소면 삭제 0건 / 지우기면 그 건 파일 0개·"지웠습니다"·줄이 사라진다', (t) async {
    final b = putRecord(records, '20261119-100000', 'aaaaaaaa', body: '지울 글');
    putRecord(records, '20261119-090000', 'bbbbbbbb', body: '남을 글');
    await open(t);
    await t.longPress(find.text('지울 글'));
    await t.pumpAndSettle();
    expect(find.textContaining('되돌릴 수 없습니다'), findsOneWidget);
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(store.deletes, isEmpty);

    await t.longPress(find.text('지울 글'));
    await t.pumpAndSettle();
    await t.tap(find.text('지우기'));
    await settleUntil(t, find.text('지웠습니다'));
    expect(namesIn(records, '2026-11').where((n) => n.startsWith(b)), isEmpty);
    expect(namesIn(records, '2026-11').length, 2);
    expect(find.text('지울 글'), findsNothing);
    expect(find.text('남을 글'), findsOneWidget);
  });

  testWidgets('F-018 항목 보기의 삭제: 취소면 0건 / 지우기면 목록으로 돌아오고 줄이 없다', (t) async {
    putRecord(records, '20261119-100000', 'aaaaaaaa', body: '지울 글');
    await open(t);
    await tapItem(t, '지울 글');
    await t.tap(find.text('삭제'));
    await t.pumpAndSettle();
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(store.deletes, isEmpty);
    await t.tap(find.text('삭제'));
    await t.pumpAndSettle();
    await t.tap(find.text('지우기'));
    await settleUntil(t, find.text('아직 수집물이 없습니다'));
    expect(namesIn(records, '2026-11'), isEmpty);
  });

  testWidgets('F-029 목록을 열어 둔 동안: 신호가 안 바뀌면 3초 틱에 폴더 읽기 0번, 바뀌면 1번 더 읽고 새 줄이 보인다 / 닫으면 감시가 멈춘다', (t) async {
    putRecord(records, '20261119-100000', 'aaaaaaaa', body: '처음 글');
    await open(t, watch: true);
    final before = store.listings;
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(seconds: 3));
    expect(store.listings, before);

    putRecord(records, '20261119-110000', 'bbbbbbbb', body: '공유로 온 글');
    signal.mark(DateTime(2026, 11, 19, 11));
    await t.pump(const Duration(seconds: 3));
    await settleUntil(t, find.text('공유로 온 글'));
    expect(store.listings, before + 1);

    await t.pumpWidget(const SizedBox());
    signal.mark(DateTime(2026, 11, 19, 11, 30));
    await t.pump(const Duration(seconds: 3));
    expect(store.listings, before + 1);
  });
}
