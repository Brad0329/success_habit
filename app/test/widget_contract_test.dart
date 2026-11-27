// F-102 위젯 계약 — 같은 이름이 Dart(쓰는 쪽)와 Kotlin(읽는 쪽)에 따로 적혀 있다(CLAUDE.md '같은 규칙이 두 곳 이상').
// 파일 위치·Kotlin이 읽는 JSON 키·키별 값 타입·date 형식·채널 이름과 메서드 목록이 어긋나면 위젯이 조용히 빈 모양
// (또는 매일 '새 하루예요')이 된다 — 여기서 잡는다.
import 'dart:convert';
import 'dart:io';

import 'package:chaerok/app_paths.dart';
import 'package:chaerok/plans.dart';
import 'package:chaerok/widget_summary.dart';
import 'package:flutter_test/flutter_test.dart';

const _kt = 'android/app/src/main/kotlin/com/brad0329/chaerok/phone';

/// 요약 JSON에 나올 수 있는 키 전부(바깥 키 + do/dont 안 키).
Set<String> _keys(Map<String, Object?> m) => {
      for (final e in m.entries) ...[e.key, if (e.value is Map) ...(e.value! as Map).keys.cast<String>()],
    };

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chaerok_widget_contract'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('위젯이 읽는 파일 위치 = 앱이 쓰는 위치', () {
    final kt = File('$_kt/PlanWidget.kt').readAsStringSync();
    final dart = const AppPaths('/f').widgetSummary.path.substring('/f/'.length);
    expect(RegExp(r'File\(context\.filesDir, "([^"]+)"\)').firstMatch(kt)?.group(1), dart);
  });

  test('위젯(Kotlin)이 읽는 JSON 키는 모두 앱(Dart)이 쓰는 키다', () async {
    final s = PlanStore(tmp, now: () => DateTime(2026, 10, 8));
    await s.saveItems([(null, '운동', PlanKind.doIt), (null, '야식', PlanKind.dont)], DateTime(2026, 10, 8));
    final written = {
      ..._keys(widgetSummary(s, DateTime(2026, 10, 8))),
      ..._keys(widgetSummary(s, DateTime(2026, 10, 1))), // empty 모양
    };
    final kt = File('$_kt/PlanWidget.kt').readAsStringSync();
    final read = {for (final m in RegExp(r'\b(?:opt\w*|str)\("(\w+)"').allMatches(kt)) m.group(1)!};
    expect(read.length, greaterThanOrEqualTo(8), reason: '정규식이 비어 통과하지 않게');
    expect(read.difference(written), isEmpty, reason: 'Kotlin이 읽는데 Dart가 안 쓰는 키');
  });

  test('채널 이름·메서드 목록 — Dart(lib 전체)가 부르는 것 = MainActivity가 받는 것', () {
    // Phase 007 B2: 이름이 어긋나면 filesDir는 앱이 못 뜨고, refreshWidget은 MissingPluginException 로그만 남긴다.
    final dart = [for (final f in Directory('lib').listSync().whereType<File>()) f.readAsStringSync()].join('\n');
    final kt = File('$_kt/MainActivity.kt').readAsStringSync();
    final dartChannels = {for (final m in RegExp(r"MethodChannel\('([^']+)'\)").allMatches(dart)) m.group(1)!};
    final ktChannels = {for (final m in RegExp(r'MethodChannel\([^,]+,\s*"([^"]+)"\)').allMatches(kt)) m.group(1)!};
    expect(dartChannels, {'chaerok/app'});
    expect(ktChannels, dartChannels);
    final called = {for (final m in RegExp(r"invokeMethod<\w+>\('(\w+)'\)").allMatches(dart)) m.group(1)!};
    final handled = {for (final m in RegExp(r'"(\w+)" ->').allMatches(kt)) m.group(1)!};
    expect(called, {'filesDir', 'refreshWidget'}, reason: '정규식이 비어 통과하지 않게');
    expect(handled, called);
  });

  test('요약 date 형식 = 위젯 SimpleDateFormat 형식(한 자리 달·날 포함)', () {
    // Phase 007 B1: 어긋나면 isToday가 늘 거짓 — 위젯이 매일 '새 하루예요'를 띄운다.
    final kt = File('$_kt/PlanWidget.kt').readAsStringSync();
    final patterns = {for (final m in RegExp(r'SimpleDateFormat\("([^"]+)"').allMatches(kt)) m.group(1)!};
    expect(patterns, hasLength(1), reason: 'dayKey·parseDay가 같은 형식이어야 한다');
    final pattern = patterns.single;
    expect(RegExp(r'^(yyyy|MM|dd|-)+$').hasMatch(pattern), isTrue, reason: '이 테스트가 흉내 내는 글자만: $pattern');
    String javaFormat(DateTime d) => pattern
        .replaceAll('yyyy', d.year.toString().padLeft(4, '0'))
        .replaceAll('MM', d.month.toString().padLeft(2, '0'))
        .replaceAll('dd', d.day.toString().padLeft(2, '0'));
    for (final d in [DateTime(2026, 1, 5), DateTime(2026, 10, 8), DateTime(2026, 12, 31)]) {
      expect(dayKey(d), javaFormat(d));
    }
    final s = PlanStore(tmp, now: () => DateTime(2026, 1, 5));
    expect(widgetSummary(s, DateTime(2026, 1, 5, 23, 59))['date'], javaFormat(DateTime(2026, 1, 5)));
  });

  test('키별 값 타입 — Kotlin 읽기 함수가 기대하는 타입을 Dart가 쓴다(JSON 왕복 뒤)', () async {
    // Phase 007 B3: optInt는 소수를 조용히 자르고 optString은 숫자도 글로 바꾼다 — 타입이 어긋나도 오류가 안 난다.
    const expected = {'str': 'String', 'optString': 'String', 'optBoolean': 'bool', 'optJSONObject': 'Map', 'optInt': 'int'};
    final kt = File('$_kt/PlanWidget.kt').readAsStringSync();
    final reads = <String, String>{};
    for (final m in RegExp(r'\b(opt\w*|str)\("(\w+)"').allMatches(kt)) {
      final want = expected[m.group(1)];
      expect(want, isNotNull, reason: '모르는 읽기 함수 ${m.group(1)} — 이 표에 넣는다');
      expect(reads.putIfAbsent(m.group(2)!, () => want!), want, reason: '${m.group(2)}를 두 타입으로 읽는다');
    }

    // 값이 다 차는 날(DO·DON'T·🔥·어제 놓침·정체성)과 빈 날.
    final s = PlanStore(tmp, now: () => DateTime(2026, 10, 8));
    await s.saveItems([(null, '운동', PlanKind.doIt), (null, '야식', PlanKind.dont)], DateTime(2026, 10, 5));
    await s.saveIdentities(['나는 운동하는 사람이다']);
    final run = s.current.firstWhere((i) => i.title == '운동').id;
    for (final k in [5, 6, 8]) {
      await s.toggle(DateTime(2026, 10, k), run, DateTime(2026, 10, 8));
    }
    final samples = [
      for (final day in [DateTime(2026, 10, 8), DateTime(2026, 10, 1)])
        jsonDecode(jsonEncode(widgetSummary(s, day))) as Map<String, Object?>,
    ];
    String typeOf(Object v) => v is String ? 'String' : v is bool ? 'bool' : v is int ? 'int' : v is Map ? 'Map' : '${v.runtimeType}';
    final seen = <String>{};
    void check(Map<String, Object?> m) {
      for (final e in m.entries) {
        final want = reads[e.key];
        if (want == null || e.value == null) continue;
        expect(typeOf(e.value!), want, reason: '키 ${e.key}');
        seen.add(e.key);
        if (e.value is Map) check((e.value! as Map).cast<String, Object?>());
      }
    }

    samples.forEach(check);
    expect(seen, reads.keys.toSet(), reason: '값이 null이라 타입을 못 본 키가 없게 — 표본을 늘린다');
  });
}
