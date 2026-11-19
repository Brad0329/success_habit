/// F-028 폰 공유 사진 묶음 = 한 건 — 판정 규칙(순수 함수). 결정: REQUIREMENTS F-028 ④⑤ⓐⓑ, SCHEMA 2026-11-16.
///
/// 원본·사이드카는 장마다 그대로 있고, AI 결과(ai·user 파일)는 **대표 장**(base가 가장 이른 장)에만 둔다.
/// 분류(classify.dart)·목록(collection_list.dart)·지우기(record_delete.dart)가 같은 규칙을 이 파일에서 쓴다.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'log.dart';

// ---- 보낼 장 고르기·사본 줄이기 (REQUIREMENTS F-028 ⓓ-2, 2026-11-16 문서 확인) ----

/// 한 요청에 보낼 최대 장수 — Claude는 20장을 넘으면 장마다 3000px 제한이 붙는다(vision 문서). 넘는 장은 `over_limit`.
const maxGroupPages = 20;

/// 상한을 넘을 때 보낼 사본 — 긴 변(Claude 고해상도 2576px·Gemini high 안쪽, 글자 판독), JPEG 화질.
const shrinkLongEdge = 2048;
const shrinkQuality = 85;

/// 사진 한 장을 줄인 JPEG 사본(방향 정보는 픽셀에 반영 — 돌아간 글자를 막는다). 디코딩 못 하면 null(로그 1줄).
/// 원본은 건드리지 않는다 — AI에 보낼 사본만.
Uint8List? shrinkPhoto(Uint8List bytes, {String who = '사진'}) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object catch (e) {
    logWarn('$who: 사진을 읽지 못해 줄이지 못함 — ${e.runtimeType}');
    return null;
  }
  if (decoded == null) {
    logWarn('$who: 사진 형식을 읽지 못해 줄이지 못함');
    return null;
  }
  var o = img.bakeOrientation(decoded);
  if (math.max(o.width, o.height) > shrinkLongEdge) {
    final wide = o.width >= o.height;
    o = img.copyResize(o,
        width: wide ? shrinkLongEdge : null, height: wide ? null : shrinkLongEdge, interpolation: img.Interpolation.average);
  }
  return img.encodeJpg(o, quality: shrinkQuality);
}

/// 한 장 — 장 순서대로 받는다. [bytes]는 보낼 수 있는 형식이라 내려받은 원본(아니면 null).
class GroupPage {
  GroupPage(this.base, this.mime, this.bytes, {this.name});
  final String base, mime;
  final String? name;
  final Uint8List? bytes;
}

/// 보낼 장(사본이면 JPEG)과 빠진 장(이유: `image_type`·`image_size`·`over_limit`).
class GroupPick {
  GroupPick(this.sent, this.skipped, {required this.shrunk});
  final List<(GroupPage, Uint8List, String)> sent; // (장, 보낼 바이트, MIME)
  final List<(String, String)> skipped; // (base, 이유)

  /// 사본을 줄여 보낸 장 수.
  final int shrunk;
}

/// ⓓ-2 규칙: ① 보낼 수 있는 형식만, 앞에서 [maxPages]장까지 ② 원본 합계가 [budget] 안이고 장마다 [maxImage] 이하면 원본 그대로
/// ③ 아니면 디코딩되는 장을 [shrink]로 줄인 사본(못 줄이면 원본이 [maxImage] 이하일 때만 원본) ④ 그래도 합계를 넘으면 뒤 장부터 `over_limit`.
GroupPick pickPages(List<GroupPage> pages,
    {required Set<String> mimes,
    required int budget,
    required int maxImage,
    int maxPages = maxGroupPages,
    Uint8List? Function(Uint8List bytes, String base) shrink = _shrink}) {
  final skipped = <(String, String)>[];
  final ok = <GroupPage>[];
  for (final p in pages) {
    if (!mimes.contains(p.mime)) {
      skipped.add((p.base, 'image_type'));
    } else if (ok.length >= maxPages) {
      skipped.add((p.base, 'over_limit')); // 부르는 쪽은 상한 뒤 장을 내려받지 않는다(bytes null)
    } else if (p.bytes == null) {
      skipped.add((p.base, 'image_type'));
    } else {
      ok.add(p);
    }
  }
  final total = ok.fold<int>(0, (s, p) => s + p.bytes!.length);
  final fits = total <= budget && ok.every((p) => p.bytes!.length <= maxImage);
  final sent = <(GroupPage, Uint8List, String)>[];
  var used = 0, shrunk = 0;
  var full = false;
  for (final p in ok) {
    var data = p.bytes!;
    var mime = p.mime;
    if (!fits) {
      final s = shrink(data, p.base);
      if (s != null && s.length < data.length) {
        data = s;
        mime = 'image/jpeg';
        shrunk++;
      } else if (data.length > maxImage) {
        skipped.add((p.base, 'image_size'));
        continue;
      }
    }
    // 한 장이 넘치면 그 뒤 장도 모두 뺀다 — 중간 장이 빠진 채 뒷장만 가면 이어지는 글이 끊긴다.
    if (full || used + data.length > budget) {
      full = true;
      skipped.add((p.base, 'over_limit'));
      continue;
    }
    used += data.length;
    sent.add((p, data, mime));
  }
  return GroupPick(sent, skipped, shrunk: shrunk);
}

Uint8List? _shrink(Uint8List bytes, String base) => shrinkPhoto(bytes, who: '묶음 $base');

/// 한 번의 폰 공유로 함께 들어온 사진인가(④) — 묶음 표시가 있고 폰 공유('채록'·'채록 + 메모')이며 이미지.
/// 묶음의 **모든** 장이 이것이어야 한 건으로 본다([isPhotoGroup]).
bool isGroupPhoto(Map<String, Object?> meta) =>
    meta['group_id'] is String &&
    (meta['group_id']! as String).isNotEmpty &&
    meta['device'] == 'phone' &&
    meta['input'] == 'share' &&
    meta['kind'] == 'image';

/// 같은 [groupId]로 찾은 장들이 새 방식 묶음이 될 수 있는가 — 모든 장이 폰 공유 사진(섞인 묶음은 지금처럼 한 건씩).
bool isPhotoGroup(Iterable<Map<String, Object?>> metas) => metas.isNotEmpty && metas.every(isGroupPhoto);

/// 사이드카의 묶음 건수 — 없거나 이상하면 null.
int? groupSize(Map<String, Object?> meta) => meta['group_size'] is int ? meta['group_size']! as int : null;

/// ⓐ 대표 장 = base(파일 이름 = 수집 시각 + ID 앞 8자)가 가장 이른 장.
String representative(Iterable<String> bases) => bases.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);

/// ⑤ 장 순서 — 원래 파일 이름(`original_name`)을 숫자는 크기로 견주어 정렬(`p2` < `p10`), 이름 없는 장은 뒤로·그 안은 base 순.
/// [pages]는 (base, original_name) 짝.
List<String> pageOrder(Iterable<(String, String?)> pages) {
  final list = pages.toList()
    ..sort((a, b) {
      final na = a.$2, nb = b.$2;
      if (na == null || na.isEmpty) return (nb == null || nb.isEmpty) ? a.$1.compareTo(b.$1) : 1;
      if (nb == null || nb.isEmpty) return -1;
      final c = naturalCompare(na, nb);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final p in list) p.$1];
}

final _chunk = RegExp(r'\d+|\D+');
final _digits = RegExp(r'^\d+$');
final _leadingZeros = RegExp(r'^0+(?=\d)');

/// 숫자 덩어리는 수로, 나머지는 대소문자 무시 글자로 견준다.
int naturalCompare(String a, String b) {
  final xa = _chunk.allMatches(a).map((m) => m.group(0)!).toList();
  final xb = _chunk.allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < xa.length && i < xb.length; i++) {
    final pa = xa[i], pb = xb[i];
    final int c;
    if (_digits.hasMatch(pa) && _digits.hasMatch(pb)) {
      // 수로 바꾸지 않는다(긴 숫자는 int를 넘는다) — 앞 0을 떼고 자리 수, 그다음 글자로.
      final ta = pa.replaceFirst(_leadingZeros, ''), tb = pb.replaceFirst(_leadingZeros, '');
      c = ta.length != tb.length ? ta.length.compareTo(tb.length) : ta.compareTo(tb);
    } else {
      c = pa.toLowerCase().compareTo(pb.toLowerCase());
    }
    if (c != 0) return c;
  }
  return xa.length.compareTo(xb.length);
}

/// ⓑ 옛 묶음 — 장마다 따로 분석된 묶음은 지금처럼 한 장씩 둔다(사용자 결정 ③).
/// [aiGroupIds] = 장 base → 그 장의 ai 파일들에 적힌 `group_id`(없으면 null) 목록,
/// [userBases] = user 파일이 있는 장 base.
bool isOldGroup(String rep, Map<String, List<String?>> aiGroupIds, Set<String> userBases) {
  for (final MapEntry(key: base, value: ids) in aiGroupIds.entries) {
    if (ids.any((g) => g == null)) return true; // 묶음 표시 없는 ai 파일 = 한 장씩 분석된 것
    if (base != rep && ids.isNotEmpty) return true; // 대표가 아닌 장의 ai 파일
  }
  return userBases.any((b) => b != rep);
}

/// ⓒ 다 모였나 — Drive에 원본·사이드카가 다 있는 장 수가 사이드카의 `group_size` 이상.
bool groupComplete(int found, int? size) => size != null && found >= size;

/// 멤버 후보를 찾는 시각 폭(구현 가정 — 공유 한 번은 몇 초 안에 만들어진다. 보관 뒤 재전송은 시각이 보관 때 그대로).
const groupWindow = Duration(minutes: 10);

/// base 앞 15자(`YYYYMMDD-HHMMSS`)의 시각. 이름 규칙이 아니면 null.
DateTime? baseTime(String base) {
  if (base.length < 15) return null;
  final s = base.substring(0, 15);
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})$').firstMatch(s);
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  return DateTime(g(1), g(2), g(3), g(4), g(5), g(6));
}

/// [base] 근처([groupWindow] 안)의 후보 base — 멤버 찾기에서 사이드카를 받을 대상(달 경계도 넘는다 — 전체 목록에서 고른다).
List<String> nearBases(String base, Iterable<String> all) {
  final t = baseTime(base);
  if (t == null) return [base];
  return [
    for (final b in all)
      if (baseTime(b) case final u? when u.difference(t).abs() <= groupWindow) b,
  ];
}
