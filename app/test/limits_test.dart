// 상한 경계 — 상한마다 "딱 상한이면 들어가고, 상한+1이면 빠진다" 한 쌍을 실제로 상한을 적용하는 함수로 건다.
//
// 왜 한 파일인가(기존판 debt-audit R3): 상한 테스트가 넉넉한 값(15MB 넣고 14MB 상한 확인 등)만 써서 상한을
// 바꿔도 통과한 일이 세 번 있었다. 문서로는 막지 못해 아래 '등록부' 테스트가 lib/의 상한 상수 선언을 훑어,
// 경계 테스트도 제외 이유도 없는 새 상한이 생기면 실패한다.
import 'dart:io';
import 'dart:typed_data';

import 'package:chaerok/log.dart';
import 'package:flutter_test/flutter_test.dart';

/// 경계 테스트가 있는 상한 — '파일:이름' → 테스트 위치.
const boundaryTested = {
  'log.dart:_maxBytes': 'limits_test 로그 회전',
  'plans.dart:maxPlanItems': 'plans_test 검증 — 31개 거부 / 30개 저장',
  'plans.dart:maxPlanChars': 'plans_test 검증 — 41자 거부 / 40자 저장',
  'plans.dart:maxReviewChars': 'plans_test 하루 평가 — 1001자 거부 / 1000자 저장',
  'plans.dart:maxIdentities': 'plans_test F-039 — 4개 거부 / 3개 저장',
  'plans.dart:maxIdentityChars': 'plans_test F-039 — 41자 거부 / 40자 저장',
  'plans.dart:maxVideoUrlChars': 'plans_test F-103 — 301자 거부 / 300자 저장',
  'plan_stats.dart:maxTrendMonths': 'plan_stats_test F-043 — 3달이면 전부 / 4달이면 최근 3달 + 전체 4달',
};

/// 경계 테스트를 두지 않는 것 — 이유와 함께.
const excludedLimits = <String, String>{};

/// lib/에서 상한처럼 생긴 선언을 '파일:이름'으로 모은다.
Set<String> scanLimitNames() {
  final patterns = [
    RegExp(r'const\s+(\w*(?:[Mm]ax|[Ll]imit)\w*)\s*='), // const maxX = / const voiceLimit =
    RegExp(r'this\.(max\w+)\s*=\s*\d'), // 생성자 기본값 this.maxX = 30
    RegExp(r'\b(max\w*(?:Bytes|Chars|Items|Count)\w*):\s*\d'), // 이름 인자 maxBinaryBytes: 14000000
  ];
  final found = <String>{};
  final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final src = f.readAsStringSync();
    for (final p in patterns) {
      for (final m in p.allMatches(src)) {
        found.add('$name:${m.group(1)}');
      }
    }
  }
  return found;
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chaerok_limits');
    initLog(tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('등록부', () {
    test('lib/의 상한 선언은 모두 경계 테스트가 있거나 제외 이유가 있다 / 등록부에 없어진 이름이 남지 않는다', () {
      final found = scanLimitNames();
      // 정규식이 좁아져 아무것도 못 찾으면 아래 비교가 공집합끼리 통과한다 — 건수를 건다(조용한 절단 금지).
      expect(found.length, greaterThanOrEqualTo(4), reason: '$found');
      final known = {...boundaryTested.keys, ...excludedLimits.keys};
      expect(found.difference(known), isEmpty, reason: '경계 테스트(at/at+1)를 넣고 boundaryTested에 올리거나, 이유와 함께 excludedLimits에');
      expect(known.difference(found), isEmpty, reason: '등록부에 lib/에 없는 이름이 있다');
    });
  });

  group('로그', () {
    test('로그 회전: 1,048,576바이트면 그대로, 1,048,577바이트면 chaerok.log.1로 넘김', () {
      final dir = Directory('${tmp.path}/rot')..createSync();
      final f = File('${dir.path}/chaerok.log');
      f.writeAsBytesSync(Uint8List(1048576));
      initLog(dir);
      expect(File('${f.path}.1').existsSync(), isFalse);
      f.writeAsBytesSync(Uint8List(1048577));
      initLog(dir);
      expect(File('${f.path}.1').lengthSync(), 1048577);
      initLog(tmp); // 다른 테스트의 로그 위치를 되돌린다
    });
  });
}
