// 저장 규칙 고정(record.dart) — 파일 이름·확장자·종류 판정. 기존판 형식을 그대로 읽으려면 이 값들이 변하면 안 된다.
// F-028 묶음 판정(photo_group.dart)의 순수 함수도 여기서 건다.
import 'dart:typed_data';

import 'package:chaerok/photo_group.dart';
import 'package:chaerok/record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('종류: 앞뒤 공백을 뺀 전체가 http(s) 주소 하나면 url, 문장 속 링크는 text, 공백뿐이면 EmptyTextError', () {
    expect(classifyText('  https://example.com/a?b=1\n'), 'url');
    expect(classifyText('HTTP://EXAMPLE.COM'), 'url');
    expect(classifyText('이 글 https://example.com 참고'), 'text');
    expect(classifyText('https://a.com https://b.com'), 'text');
    expect(() => classifyText(' \n\t　﻿'), throwsA(isA<EmptyTextError>()));
  });

  test('이름: base = YYYYMMDD-HHMMSS_<ID 앞 8자>(수집 시각의 현지 시각), 달 폴더 = YYYY-MM', () {
    const at = '2026-11-19T14:05:31+09:00';
    expect(baseName(at, '0a1b2c3d-1111-4222-8333-444444444444'), '20261119-140531_0a1b2c3d');
    expect(fileNames(at, '0a1b2c3d-1111-4222-8333-444444444444', 'png'),
        ('20261119-140531_0a1b2c3d.png', '20261119-140531_0a1b2c3d.meta.json'));
    expect(monthFolder(at), '2026-11');
  });

  test('확장자: 텍스트·링크는 txt, 파일은 원래 확장자(대소문자 그대로), 없으면 MIME 표, 표에 없으면 bin', () {
    expect(extensionFor('text', 'a.md', 'text/markdown'), 'txt');
    expect(extensionFor('image', 'IMG_1.JPG', 'image/jpeg'), 'JPG');
    expect(extensionFor('file', 'archive.tar.gz', null), 'gz');
    expect(extensionFor('image', null, 'image/png'), 'png');
    expect(extensionFor('file', '이름만', 'audio/mp4; codecs=x'), 'm4a');
    expect(extensionFor('file', '.hidden', 'application/zip'), 'bin');
    expect(extensionFor('file', 'x.', null), 'bin');
  });

  test('확장자(SCHEMA 2026-11-19): 영문·숫자 1~10자가 아니면 원래 확장자를 쓰지 않고 MIME 표로 간다', () {
    expect(extensionFor('file', 'a.abcdefghij', null), 'abcdefghij'); // 10자 — 그대로
    expect(extensionFor('file', 'a.abcdefghijk', 'application/pdf'), 'pdf'); // 11자
    expect(extensionFor('file', 'evil./../../x', 'image/png'), 'png');
    expect(extensionFor('file', r'evil.a\b', null), 'bin');
    expect(extensionFor('file', '보고서.v2 최종', null), 'bin');
    expect(extensionFor('file', '사진.한글', 'image/jpeg'), 'jpg');
  });

  test('사이드카: 묶음은 group_id·group_size가 함께, 2건 이상 / 모르는 input은 거부', () {
    Map<String, Object?> build({String input = 'share', String? g, int? n}) => buildSidecar(
        recordId: 'i', collectedAt: 'c', input: input, kind: 'image', source: '', device: 'phone',
        originalName: '', mime: 'image/png', data: Uint8List(3), groupId: g, groupSize: n);
    expect(build()['source'], isNull); // 빈 문자열 → null
    expect(build(g: 'G', n: 2)['group_size'], 2);
    expect(() => build(g: 'G'), throwsArgumentError);
    expect(() => build(g: 'G', n: 1), throwsArgumentError);
    expect(() => build(input: 'fax'), throwsArgumentError);
    expect(build(input: 'pc_file')['input'], 'pc_file'); // 기존판 값도 받아들인다
  });

  group('F-028 묶음 판정', () {
    Map<String, Object?> meta({String device = 'phone', String input = 'share', String kind = 'image', String? g = 'G'}) =>
        {'device': device, 'input': input, 'kind': kind, 'group_id': g};

    test('대상 = 폰 공유 이미지이고 group_id가 있는 것만', () {
      expect(isGroupPhoto(meta()), isTrue);
      expect(isGroupPhoto(meta(g: null)), isFalse);
      expect(isGroupPhoto(meta(kind: 'file')), isFalse);
      expect(isGroupPhoto(meta(device: 'pc', input: 'pc_file')), isFalse);
      expect(isPhotoGroup([meta(), meta(kind: 'file')]), isFalse);
    });

    test('대표 = base가 가장 이른 장 / 장 순서 = 파일 이름 자연 정렬, 이름 없는 장은 뒤로·그 안은 base 순', () {
      expect(representative(['20261119-100002_b', '20261119-100001_c', '20261119-100003_a']), '20261119-100001_c');
      expect(pageOrder([('b1', 'p2.jpg'), ('b2', 'p10.jpg'), ('b3', 'p1.jpg')]), ['b3', 'b1', 'b2']);
      expect(pageOrder([('b2', null), ('b1', null), ('b3', 'a.jpg')]), ['b3', 'b1', 'b2']);
    });

    test('옛 묶음 = 묶음 표시 없는 ai 파일이 있거나 대표가 아닌 장에 결과 파일이 있다', () {
      expect(isOldGroup('r', {}, {}), isFalse);
      expect(isOldGroup('r', {'r': ['G']}, {'r'}), isFalse);
      expect(isOldGroup('r', {'r': [null]}, {}), isTrue);
      expect(isOldGroup('r', {'x': ['G']}, {}), isTrue);
      expect(isOldGroup('r', {}, {'x'}), isTrue);
    });
  });
}
