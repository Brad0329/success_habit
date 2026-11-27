// Phase 007 A1: 계획 파일을 쓰는 public 함수는 성공하면 알린다 — 맨 밑 계획 화면과 홈 화면 위젯(WidgetSync)이
// 알림으로만 다시 그린다. 체크·보류·휴일이 빠져 위젯이 앱을 다시 열 때까지 안 바뀐 것이 3회째라 등록부로 건다.
// 소스 훑기가 `_write()`·`_save(`·`saveItems(`를 부르는 public 함수를 모아 등록부와 대조한다 — 새 저장 함수가 빠지면 실패.
// `saveReview`는 `reviews.json`만 쓴다(위젯 요약·달력 칸이 안 읽는다 — 평가 칸은 화면이 직접 그린다) — 훑기 대상 밖.
import 'dart:convert';
import 'dart:io';

import 'package:chaerok/plans.dart';
import 'package:flutter_test/flutter_test.dart';

// 10월 5~9일 = 월~금.
DateTime d(int day) => DateTime(2026, 10, day);

typedef _Case = ({Future<void> Function(PlanStore s, Directory dir)? setUp, Future<Object?> Function(PlanStore s) act});

String _idOf(PlanStore s, String title) => s.current.firstWhere((i) => i.title == title).id;

Future<void> _oneItem(PlanStore s, Directory _) async => s.saveList([(null, '운동')], d(8));

/// 나누기 전 옛 파일(F-031 이전 — `weekend` 키 없음).
void _oldFile(Directory dir) => File('${dir.path}/plans.json').writeAsStringSync(jsonEncode({
      'version': 1,
      'next_id': 2,
      'lists': [
        {'from': '2026-10-01', 'items': [{'id': 'p1', 'title': '운동', 'kind': 'do'}]},
      ],
      'done': {},
    }));

/// 나눈 칸이고 평일 DON'T가 주말 계획에 없는 파일(`dont_rest_from` 없음).
void _dontOffRestFile(Directory dir) => File('${dir.path}/plans.json').writeAsStringSync(jsonEncode({
      'version': 1,
      'next_id': 2,
      'lists': [
        {'from': '2026-10-01', 'items': [{'id': 'p1', 'title': '야식', 'kind': 'dont'}], 'weekend': []},
      ],
      'done': {},
    }));

final Map<String, _Case> _writers = {
  'saveList': (setUp: null, act: (s) => s.saveList([(null, '운동')], d(8))),
  'saveItems': (setUp: null, act: (s) => s.saveItems([(null, '운동', PlanKind.doIt)], d(8))),
  'saveWeekend': (setUp: _oneItem, act: (s) => s.saveWeekend([(null, '산책', PlanKind.doIt)], d(8))),
  'saveIdentities': (setUp: null, act: (s) => s.saveIdentities(['나는 운동하는 사람이다'])),
  'saveVideo': (setUp: _oneItem, act: (s) => s.saveVideo(_idOf(s, '운동'), 'https://youtu.be/abc')),
  'toggle': (setUp: _oneItem, act: (s) => s.toggle(d(8), _idOf(s, '운동'), d(8))),
  'toggleHold': (setUp: _oneItem, act: (s) => s.toggleHold(d(8), _idOf(s, '운동'), d(8))),
  'toggleHoliday': (setUp: _oneItem, act: (s) => s.toggleHoliday(d(8))),
  'adoptDontDefault': (setUp: _oneItem, act: (s) => s.adoptDontDefault(d(8))),
  'splitFromToday': (setUp: (_, dir) async => _oldFile(dir), act: (s) => s.splitFromToday(d(8))),
  'includeWeekdayDontsOnRest': (
    setUp: (_, dir) async => _dontOffRestFile(dir),
    act: (s) => s.includeWeekdayDontsOnRest(d(8)),
  ),
};

/// `plans.dart`의 public 멤버 중 계획 파일을 쓰는 것(본문에 `_write()`·`_save(`·`saveItems(`).
Set<String> _scanWriters() {
  final src = File('lib/plans.dart').readAsStringSync();
  final head = RegExp(r'^  (?:Future<[^>]*>|bool|void|String\?|Future<[^>]*\?>) (\w+)\(', multiLine: true);
  final heads = head.allMatches(src).toList();
  final out = <String>{};
  for (var k = 0; k < heads.length; k++) {
    final name = heads[k].group(1)!;
    if (name.startsWith('_')) continue;
    final body = src.substring(heads[k].end, k + 1 < heads.length ? heads[k + 1].start : src.length);
    if (body.contains('_write()') || body.contains('_save(') || body.contains('saveItems(')) out.add(name);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chaerok_notify'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('등록부 = 소스에서 계획 파일을 쓰는 public 함수 전부', () {
    final scanned = _scanWriters();
    expect(scanned, isNotEmpty);
    expect(scanned, _writers.keys.toSet());
  });

  for (final e in _writers.entries) {
    test('${e.key}: 파일을 쓰면 알린다', () async {
      final setUp = e.value.setUp;
      if (setUp != null) await setUp(PlanStore(tmp, now: () => d(8)), tmp);
      final s = PlanStore(tmp, now: () => d(8));
      final before = File('${tmp.path}/plans.json').existsSync() ? File('${tmp.path}/plans.json').readAsStringSync() : null;
      var notified = 0;
      s.addListener(() => notified++);
      await e.value.act(s);
      expect(File('${tmp.path}/plans.json').readAsStringSync(), isNot(before), reason: '쓰기가 일어난 경우여야 한다');
      expect(notified, greaterThanOrEqualTo(1));
    });
  }
}
