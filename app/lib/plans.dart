/// F-016 계획관리 — 매일 계획 목록과 날짜별 체크. 폰 `files/plans/plans.json`에 둔다.
///
/// 목록을 바꾸면 '오늘부터' 적용된다 — 목록 이력을 적용 시작 날짜(`from`)별로 보관하고,
/// 어느 날의 목록 = from이 그날 이하인 것 중 마지막. 그래서 지난 날의 목록·체크는 그대로 남는다(REQUIREMENTS F-016 ②).
/// 항목은 id로 구분한다 — 이름을 바꿔도 같은 항목이라 체크가 유지된다.
/// F-025 보류(`held`, 날짜 → id) = 그날 할 수 없는 항목 — 집계의 전체 수에서 빠지고 체크할 수 없다.
/// F-026 항목마다 종류(`kind`: do·dont). 키가 없는 옛 항목은 DO.
/// F-026 바뀜(2026-11-24): `dont_default_from` 이후 DON'T는 기본 지킴 — 누르면 `missed`(어김). 그 전 날은 옛 규칙(체크 = 지킴).
/// F-031 평일·주말(휴일) 나누기 — 이력 칸의 `weekend`(주말에 하는 id, 주말 순서)가 있으면 나눈 칸.
/// 쉬는 날(토·일·`holidays`) 목록 = 주말 계획 + 그 밖의 평일 계획(기본 보류 — `released`로 그날만 풀 수 있다),
/// 평일 목록 = `weekday`가 true인 항목. `weekend`가 없는 옛 칸은 모든 날 같은 목록(지난 날 그대로).
/// 로그에는 계획 이름을 남기지 않는다 — 건수만.
/// F-024 하루 평가는 같은 폴더의 `reviews.json`(날짜 → 글). 로그에는 글자 수만.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'atomic_file.dart';
import 'log.dart';

const maxPlanItems = 30;
const maxPlanChars = 40;
const maxReviewChars = 1000; // F-024 하루 평가
const maxIdentities = 3; // F-039 정체성 문장
const maxIdentityChars = 40;

/// F-026 계획 종류 — DO(하기) · DON'T(안 하기). DON'T의 체크 = 지켰다.
enum PlanKind {
  doIt('do'),
  dont('dont');

  const PlanKind(this.json);
  final String json;

  /// 파일의 값 → 종류. 키가 없는 옛 항목(null)은 DO, 모르는 값은 FormatException(깨진 파일로 본다).
  static PlanKind parse(Object? v) => switch (v) {
        null || 'do' => PlanKind.doIt,
        'dont' => PlanKind.dont,
        _ => throw FormatException('모르는 계획 종류: $v'),
      };
}

class PlanItem {
  const PlanItem(this.id, this.title, [this.kind = PlanKind.doIt, this.weekday = true]);
  final String id;
  final String title;
  final PlanKind kind;

  /// F-031 평일 계획인가 — false = 주말에만 넣은 항목(평일엔 안 보임).
  final bool weekday;

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'kind': kind.json, if (!weekday) 'weekday': false};

  @override
  bool operator ==(Object other) =>
      other is PlanItem && other.id == id && other.title == title && other.kind == kind && other.weekday == weekday;

  @override
  int get hashCode => Object.hash(id, title, kind, weekday);
}

class _Version {
  _Version(this.from, this.items, this.weekend);
  final String from;
  List<PlanItem> items;

  /// F-031 쉬는 날에 하는 항목 id(주말 순서). null = 나누기 전 칸(모든 날 같은 목록).
  List<String>? weekend;
}

/// F-031 편집 화면의 한 줄 — (id, 이름, 종류). id가 null이면 새 항목.
typedef PlanRow = (String?, String, PlanKind);

/// F-031 토·일인가(휴일 지정과 별개).
bool isWeekend(DateTime d) => d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

/// 폰 현지 날짜 → `yyyy-mm-dd`.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// 이름 비교 열쇠 — 띄어쓰기·대소문자 무시. 같은 이름 금지(F-016)와 통계 검색(F-044)이 같이 쓴다.
String planNameKey(String s) => _norm(s);

/// 저장할 수 있으면 null, 아니면 화면에 보일 이유.
String? validatePlanTitles(List<String> titles) {
  if (titles.length > maxPlanItems) return '계획은 $maxPlanItems개까지';
  final seen = <String>{};
  for (final t in titles) {
    if (t.isEmpty) return '빈 이름은 넣을 수 없습니다';
    if (t.length > maxPlanChars) return '이름은 $maxPlanChars자까지';
    if (!seen.add(_norm(t))) return '같은 이름이 있습니다';
  }
  return null;
}

/// F-039 저장할 수 있으면 null, 아니면 화면에 보일 이유. [texts]는 이미 앞뒤 공백을 지우고 빈 것을 뺀 목록.
String? validateIdentities(List<String> texts) {
  if (texts.length > maxIdentities) return '문장은 $maxIdentities개까지';
  final seen = <String>{};
  for (final t in texts) {
    if (t.length > maxIdentityChars) return '문장은 $maxIdentityChars자까지';
    if (!seen.add(_norm(t))) return '같은 문장이 있습니다';
  }
  return null;
}

/// 계획 파일을 쓰면 알린다 — 맨 밑에 떠 있는 계획 화면이 설정에서 바꾼 목록을 다시 그리고(2026-11-24),
/// 홈 화면 위젯 요약(WidgetSync)이 체크·보류·휴일을 바로 다시 쓰게(Phase 007 A1). 등록부 = plan_store_notify_test.
class PlanStore extends ChangeNotifier {
  PlanStore(this.dir, {this.now = DateTime.now}) {
    _load();
  }

  /// `files/plans/`.
  final Directory dir;

  /// 오늘을 아는 시계 — F-026 바뀜: DON'T 기본 지킴은 오늘까지만(미래는 표시 없음).
  final DateTime Function() now;

  /// F-026 바뀜(2026-11-24) DON'T 기본 지킴 시작 날짜 — 이날부터 DON'T는 `_missed`에 없으면 지킴. null = 아직 옛 규칙.
  String? _dontFrom;
  final _missed = <String, Set<String>>{}; // 날짜 → 어긴 DON'T id(새 규칙 날만)

  File get _file => File('${dir.path}/plans.json');

  final _versions = <_Version>[];
  final _done = <String, Set<String>>{};
  final _held = <String, Set<String>>{}; // F-025 보류 — 날짜 → 항목 id
  final _released = <String, Set<String>>{}; // F-031 쉬는 날 그날만 푼 평일 계획 — 날짜 → 항목 id
  final _holidays = <String>{}; // F-031 휴일로 지정한 평일
  final _identities = <String>[]; // F-039 정체성 문장(지금 값만, 0개면 파일에 키 없음)
  var _nextId = 1;

  /// 평일 DON'T를 주말 계획에 자동으로 넣기 시작한 날(SCHEMA 2026-11-24). null = 아직(옛 파일).
  String? _dontRestFrom;

  /// 파일이 깨졌으면 true — 저장·체크를 모두 거부한다(덮어써서 기록을 잃지 않게).
  bool broken = false;

  void _load() {
    if (!_file.existsSync()) return;
    try {
      final j = jsonDecode(_file.readAsStringSync());
      if (j is! Map) throw const FormatException('객체가 아님');
      for (final v in j['lists'] as List) {
        final m = v as Map;
        final weekend = m['weekend'] as List?; // F-031: 없으면 나누기 전 칸
        _versions.add(_Version(
          m['from'] as String,
          [
            for (final it in m['items'] as List)
              PlanItem((it as Map)['id'] as String, it['title'] as String, PlanKind.parse(it['kind']),
                  (it['weekday'] as bool?) ?? true),
          ],
          weekend == null ? null : [for (final id in weekend) id as String],
        ));
      }
      (j['done'] as Map).forEach((k, v) => _done[k as String] = {for (final id in v as List) id as String});
      // F-025: `held`가 없는 옛 파일 = 보류 0건. F-031 `released`·`holidays`도 없으면 0건.
      ((j['held'] as Map?) ?? const {})
          .forEach((k, v) => _held[k as String] = {for (final id in v as List) id as String});
      ((j['released'] as Map?) ?? const {})
          .forEach((k, v) => _released[k as String] = {for (final id in v as List) id as String});
      _holidays.addAll([for (final k in (j['holidays'] as List?) ?? const []) k as String]);
      // F-026 바뀜: 키가 없는 옛 파일 = 모든 날 옛 규칙(체크한 DON'T만 지킴).
      _dontFrom = j['dont_default_from'] as String?;
      ((j['missed'] as Map?) ?? const {})
          .forEach((k, v) => _missed[k as String] = {for (final id in v as List) id as String});
      // F-039: 키가 없는 옛 파일 = 0개. 문자열 목록이 아니면 캐스트가 던져 깨진 파일로 본다.
      _identities.addAll([for (final t in (j['identities'] as List?) ?? const []) t as String]);
      _nextId = j['next_id'] as int;
      _dontRestFrom = j['dont_rest_from'] as String?;
    } on Object catch (e) {
      logError('계획 파일을 읽지 못함 — 저장·체크를 막는다(파일은 그대로 둠)', e);
      _versions.clear();
      _done.clear();
      _held.clear();
      _released.clear();
      _holidays.clear();
      _dontFrom = null;
      _missed.clear();
      _identities.clear();
      broken = true;
    }
  }

  /// 지금(가장 마지막) 목록 — 평일·주말 항목 전부. 아직 없으면 빈 목록.
  List<PlanItem> get current => _versions.isEmpty ? const [] : List.unmodifiable(_versions.last.items);

  /// F-031 지금 평일 계획(평일 순서).
  List<PlanItem> get weekdayItems => [for (final i in current) if (i.weekday) i];

  /// F-031 지금 주말 계획(주말 순서) — 주말에만 넣은 항목 + 편입한 평일 계획.
  List<PlanItem> get weekendItems => _versions.isEmpty ? const [] : _weekendOf(_versions.last);

  List<PlanItem> _weekendOf(_Version v) {
    final byId = {for (final i in v.items) i.id: i};
    return [for (final id in v.weekend ?? const <String>[]) if (byId[id] != null) byId[id]!];
  }

  List<PlanItem> _defaultHeldOf(_Version v) {
    final on = {...?v.weekend};
    return [for (final i in v.items) if (i.weekday && !on.contains(i.id)) i];
  }

  _Version? _versionOn(DateTime day) {
    final k = dayKey(day);
    for (final v in _versions.reversed) {
      if (v.from.compareTo(k) <= 0) return v;
    }
    return null;
  }

  /// F-031 쉬는 날인가 — 토·일이거나 휴일로 지정한 날.
  bool isRestDay(DateTime day) => isWeekend(day) || _holidays.contains(dayKey(day));

  /// F-031 휴일로 지정한 평일인가.
  bool isHoliday(DateTime day) => _holidays.contains(dayKey(day));

  /// F-031 그날을 휴일로 지정·해제할 수 있나 — 평일(월~금)이고 그날 목록이 나뉜 칸일 때만.
  bool canSetHoliday(DateTime day) => !broken && !isWeekend(day) && _versionOn(day)?.weekend != null;

  /// 그날의 목록. 첫 목록을 넣기 전 날짜면 null("계획 없음").
  /// F-031 나눈 칸이면 평일 = 평일 계획, 쉬는 날 = 주말 계획 + 그 밖의 평일 계획(뒤쪽, 기본 보류).
  List<PlanItem>? itemsOn(DateTime day) {
    final v = _versionOn(day);
    if (v == null) return null;
    if (v.weekend == null) return List.unmodifiable(v.items);
    if (!isRestDay(day)) return List.unmodifiable([for (final i in v.items) if (i.weekday) i]);
    return List.unmodifiable([..._weekendOf(v), ..._defaultHeldOf(v)]);
  }

  /// F-031 그날 기본 보류인 항목 id(쉬는 날의 주말 계획 밖 평일 계획).
  Set<String> _defaultHeldOn(DateTime day) {
    final v = _versionOn(day);
    if (v == null || v.weekend == null || !isRestDay(day)) return const {};
    return {for (final i in _defaultHeldOf(v)) i.id};
  }

  /// 그날 체크한 항목 id(그날 목록에 있고 보류가 아닌 것만).
  /// F-026 바뀜: 기본 지킴 날(시작 이후·오늘까지)의 DON'T는 어기지 않았으면 체크된 것으로 친다.
  Set<String> doneOn(DateTime day) {
    final done = {..._onList(day, _done)};
    if (_dontDefaultOn(day)) {
      final missed = _missed[dayKey(day)] ?? const <String>{};
      for (final i in itemsOn(day)!) {
        if (i.kind != PlanKind.dont) continue;
        if (missed.contains(i.id)) {
          done.remove(i.id);
        } else {
          done.add(i.id);
        }
      }
    }
    return done.difference(heldOn(day));
  }

  /// F-026 바뀜: 그날이 DON'T 기본 지킴 날인가 — 시작 날짜 이후이고 오늘 이전, 계획 있는 날.
  bool _dontDefaultOn(DateTime day) {
    final from = _dontFrom;
    if (from == null || itemsOn(day) == null) return false;
    final k = dayKey(day);
    return k.compareTo(from) >= 0 && k.compareTo(dayKey(now())) <= 0;
  }

  /// F-042 그날이 DON'T 기본 지킴 날인가 — 그날 안 지킴이면 놓침이 확정된다(오늘이라도).
  bool dontDefaultOn(DateTime day) => _dontDefaultOn(day);

  /// F-042 첫 목록이 시작하는 날. 목록이 없거나 깨진 파일이면 null.
  DateTime? get firstDay => _versions.isEmpty ? null : DateTime.parse(_versions.first.from);

  /// F-026 바뀜 기본 지킴으로 세는 DON'T인가(새 규칙 날의 DON'T — 미래 포함, 체크는 미래에 막혀 있다).
  bool _isDefaultDont(DateTime day, String id) {
    final from = _dontFrom;
    if (from == null || dayKey(day).compareTo(from) < 0) return false;
    return itemsOn(day)?.any((i) => i.id == id && i.kind == PlanKind.dont) ?? false;
  }

  /// F-026 바뀜: 옛 파일이면 오늘부터 DON'T 기본 지킴을 켠다(지난 날은 옛 규칙 그대로). 앱을 켤 때 한 번.
  /// 이미 켰거나 깨진 파일이면 쓰기 0. 목록이 아직 없으면 메모리에만 두고 첫 저장이 함께 쓴다. 쓰기 실패는 되돌리고 다시 던진다.
  Future<void> adoptDontDefault(DateTime today) async {
    if (broken || _dontFrom != null) return;
    _dontFrom = dayKey(today);
    if (_versions.isEmpty) return;
    try {
      await _write();
    } on Object {
      _dontFrom = null;
      rethrow;
    }
    logInfo("DON'T 기본 지킴 시작: $_dontFrom");
    notifyListeners(); // 파일을 쓰는 public 함수는 모두 알린다(plan_store_notify_test 등록부)
  }

  /// F-025 그날 보류한 항목 id(그날 목록에 있는 것만). F-031 기본 보류 중 그날 푼 것은 뺀다.
  Set<String> heldOn(DateTime day) {
    final released = _released[dayKey(day)] ?? const <String>{};
    return _onList(day, _held).union(_defaultHeldOn(day).difference(released));
  }

  /// F-037 쉬는 날 기본 보류로 남아 있는 평일 계획 id(그날 푼 것은 뺀다) — 통계는 이것을 해야 한 날·보류 어느 쪽에도 안 센다.
  Set<String> restHeldOn(DateTime day) =>
      _defaultHeldOn(day).difference(_released[dayKey(day)] ?? const <String>{});

  Set<String> _onList(DateTime day, Map<String, Set<String>> byDay) {
    final items = itemsOn(day);
    if (items == null) return const {};
    final ids = {for (final i in items) i.id};
    return (byDay[dayKey(day)] ?? const <String>{}).intersection(ids);
  }

  /// 달력 칸 집계 (한 수, 전체 — 보류는 뺀다). 계획 없는 날은 null. [kind]를 주면 그 종류만(F-026).
  (int, int)? summary(DateTime day, {PlanKind? kind}) {
    final all = itemsOn(day);
    if (all == null) return null;
    final ids = {for (final i in all) if (kind == null || i.kind == kind) i.id};
    final held = heldOn(day).intersection(ids).length;
    return (doneOn(day).intersection(ids).length, ids.length - held);
  }

  /// 종류를 모르는 평일 계획 저장 — 있던 항목은 지금 종류 그대로, 새 항목은 DO. 나머지는 [saveItems].
  Future<String?> saveList(List<(String?, String)> rows, DateTime today) {
    final kinds = {for (final i in current) i.id: i.kind};
    return saveItems([for (final r in rows) (r.$1, r.$2, kinds[r.$1] ?? PlanKind.doIt)], today);
  }

  /// 오늘부터 적용할 **평일 계획**을 저장한다. [rows] = (id, 이름, 종류) 순서대로 — id가 null이면 새 항목.
  /// F-031 주말에만 넣은 항목·주말 순서는 그대로 두고, 여기서 지운 평일 계획은 주말에서도 없어진다.
  /// 실패면 이유(파일은 그대로), 성공·변화 없음이면 null.
  Future<String?> saveItems(List<PlanRow> rows, DateTime today) {
    final all = <(String?, String, PlanKind, bool)>[
      for (final r in rows) (r.$1, r.$2, r.$3, true),
      for (final i in current) if (!i.weekday) (i.id, i.title, i.kind, false),
    ];
    final index = {for (var k = 0; k < all.length; k++) if (all[k].$1 != null) all[k].$1!: k};
    final old = _versions.isEmpty ? const <String>[] : (_versions.last.weekend ?? const <String>[]);
    // 새로 넣은 평일 DON'T는 주말 계획에도(맨 뒤) — 주말·휴일에 보류되지 않는다(2026-11-24 사용자).
    final newDonts = [for (var k = 0; k < rows.length; k++) if (rows[k].$1 == null && rows[k].$3 == PlanKind.dont) k];
    return _save(all, [for (final id in old) if (index[id] != null) index[id]!, ...newDonts], today);
  }

  /// F-031 오늘부터 적용할 **주말 계획**을 저장한다. [rows] = 주말 순서대로 — 평일 계획의 id면 편입, 아니면 주말에만.
  /// 평일 계획은 그대로 두고(여기 없으면 주말에 보류), 이름은 여기서 바꾼 것을 따른다. 여기 없는 주말 전용 항목은 지운다.
  Future<String?> saveWeekend(List<PlanRow> rows, DateTime today) {
    final renamed = {for (final r in rows) if (r.$1 != null) r.$1!: r.$2};
    final all = <(String?, String, PlanKind, bool)>[
      for (final i in weekdayItems) (i.id, renamed[i.id] ?? i.title, i.kind, true),
    ];
    final weekdayIndex = {for (var k = 0; k < all.length; k++) all[k].$1!: k};
    final order = <int>[];
    for (final r in rows) {
      final k = weekdayIndex[r.$1];
      if (k != null) {
        order.add(k);
      } else {
        all.add((r.$1, r.$2, r.$3, false));
        order.add(all.length - 1);
      }
    }
    return _save(all, order, today);
  }

  /// [rows] = (id, 이름, 종류, 평일인가), [weekendIdx] = 주말 순서(rows 위치). 오늘부터 적용할 칸을 쓴다.
  Future<String?> _save(List<(String?, String, PlanKind, bool)> rows, List<int> weekendIdx, DateTime today) async {
    if (broken) return '계획 파일을 읽지 못해 저장할 수 없습니다';
    final titles = [for (final r in rows) r.$2.trim()];
    final error = validatePlanTitles(titles);
    if (error != null) return error;
    var next = _nextId;
    final items = [
      for (var k = 0; k < rows.length; k++) PlanItem(rows[k].$1 ?? 'p${next++}', titles[k], rows[k].$3, rows[k].$4),
    ];
    final weekend = [for (final k in weekendIdx) items[k].id];
    final last = _versions.isEmpty ? null : _versions.last;
    if (last?.weekend != null && _listEquals(items, last!.items) && _idsEqual(weekend, last.weekend!)) return null;
    final k = dayKey(today);
    final prevNext = _nextId;
    final prevDontRest = _dontRestFrom;
    _dontRestFrom ??= k; // 새 코드가 쓴 파일 = 평일 DON'T가 주말에 들어가는 규칙을 따른다(SCHEMA 2026-11-24)
    final added = last == null || last.from != k;
    final oldItems = last?.items;
    final oldWeekend = last?.weekend;
    if (added) {
      _versions.add(_Version(k, items, weekend));
    } else {
      last.items = items;
      last.weekend = weekend;
    }
    _nextId = next;
    try {
      await _write();
    } on Object {
      // 되돌리고 다시 던진다 — 화면이 실패를 알린다(로그는 _write가 남김).
      if (added) {
        _versions.removeLast();
      } else {
        last.items = oldItems!;
        last.weekend = oldWeekend;
      }
      _nextId = prevNext;
      _dontRestFrom = prevDontRest;
      rethrow;
    }
    logInfo('계획 저장: 평일 ${items.where((i) => i.weekday).length}개 · 주말 ${weekend.length}개(적용 $k)');
    notifyListeners();
    return null;
  }

  /// F-031 나누기 전 목록이면 오늘부터 나눈 칸을 만든다 — 지금 목록 = 평일 계획, 주말 계획 = 빈 목록(평일 계획 전부 보류).
  /// 앱을 켤 때 한 번. 이미 나눴거나 목록이 없거나 깨진 파일이면 쓰기 0. 쓰기 실패는 되돌리고 다시 던진다.
  Future<void> splitFromToday(DateTime today) async {
    if (broken || _versions.isEmpty || _versions.last.weekend != null) return;
    final last = _versions.last;
    final k = dayKey(today);
    final added = last.from != k;
    if (added) {
      _versions.add(_Version(k, [for (final i in last.items) PlanItem(i.id, i.title, i.kind)], []));
    } else {
      last.weekend = [];
    }
    try {
      await _write();
    } on Object {
      if (added) {
        _versions.removeLast();
      } else {
        last.weekend = null;
      }
      rethrow;
    }
    logInfo('계획을 평일·주말로 나눔: 평일 ${last.items.length}개(적용 $k)');
    notifyListeners();
  }

  /// 평일 DON'T를 주말·휴일에도 보류 없이 — 주말 계획에 없는 평일 DON'T를 주말 순서 맨 뒤(DON'T 묶음 맨 아래)에 넣은
  /// 칸을 오늘부터 쓴다(2026-11-24 사용자, SCHEMA `dont_rest_from`). 앱을 켤 때 [splitFromToday] 다음에 한 번.
  /// 이미 넣었거나(표시 있음) 나눈 칸이 아니거나 넣을 것이 없거나 깨진 파일이면 쓰기 0. 쓰기 실패는 다시 던진다.
  Future<void> includeWeekdayDontsOnRest(DateTime today) async {
    if (broken || _dontRestFrom != null || _versions.isEmpty || _versions.last.weekend == null) return;
    final v = _versions.last;
    final on = v.weekend!.toSet();
    final missing = [for (final i in v.items) if (i.weekday && i.kind == PlanKind.dont && !on.contains(i.id)) i.id];
    if (missing.isEmpty) return; // 표시는 다음 저장(_save)이 쓴다 — 그 뒤 새 DON'T는 저장 때 들어간다
    final rows = [for (final i in v.items) (i.id, i.title, i.kind, i.weekday)];
    final index = {for (var k = 0; k < rows.length; k++) rows[k].$1: k};
    final order = [for (final id in [...v.weekend!, ...missing]) if (index[id] != null) index[id]!];
    final error = await _save(rows, order, today);
    if (error != null) {
      logError("평일 DON'T 주말 편입 못 함", error);
      return;
    }
    logInfo("평일 DON'T ${missing.length}개를 주말 계획에 넣음(적용 ${dayKey(today)})");
  }

  /// F-031 그날을 휴일로 지정·해제한다. [canSetHoliday]가 아니면 false(쓰기 0). 지정하면 true를 돌려준 뒤 그날은 쉬는 날.
  Future<bool> toggleHoliday(DateTime day) async {
    if (!canSetHoliday(day)) return false;
    final k = dayKey(day);
    final on = !_holidays.remove(k);
    if (on) _holidays.add(k);
    try {
      await _write();
    } on Object {
      if (on) {
        _holidays.remove(k);
      } else {
        _holidays.add(k);
      }
      rethrow;
    }
    logInfo('휴일 ${on ? '지정' : '해제'}: $k');
    notifyListeners(); // 홈 화면 위젯이 알림으로 다시 쓴다(Phase 007 A1)
    return true;
  }

  /// 체크·보류를 바꿀 수 있는 날·항목인가 — 깨진 파일·미래 날짜·계획 없는 날·목록에 없는 항목이면 false.
  bool _canMark(DateTime day, String id, DateTime today) {
    if (broken) return false;
    if (dayKey(day).compareTo(dayKey(today)) > 0) return false;
    final items = itemsOn(day);
    return items != null && items.any((i) => i.id == id);
  }

  /// F-025 보류를 켜고 끈다. 켜면 그날 체크는 풀린다. 거부 조건은 [toggle]과 같다(쓰기 0).
  /// F-031 쉬는 날의 기본 보류 항목은 그날만 풀기(`released`) ↔ 다시 보류.
  Future<bool> toggleHold(DateTime day, String id, DateTime today) async {
    if (!_canMark(day, id, today)) return false;
    final k = dayKey(day);
    final byDefault = _defaultHeldOn(day).contains(id);
    final held = (byDefault ? _released : _held).putIfAbsent(k, () => <String>{});
    final done = _done.putIfAbsent(k, () => <String>{});
    // 기본 보류 항목은 `released`에 있으면 풀린 상태 — 빼면 다시 보류(on).
    final removed = held.remove(id);
    final on = byDefault ? removed : !removed;
    final wasDone = on && done.remove(id);
    // F-026 바뀜: 어긴 DON'T를 보류하면 어김도 풀린다 — 보류를 풀면 다시 기본 지킴.
    final missed = _missed[k];
    final wasMissed = on && (missed?.remove(id) ?? false);
    if (!removed) held.add(id);
    try {
      await _write();
    } on Object {
      // 되돌리고 다시 던진다 — 화면이 실패를 알린다(로그는 _write가 남김).
      if (removed) {
        held.add(id);
      } else {
        held.remove(id);
      }
      if (wasDone) done.add(id);
      if (wasMissed) missed!.add(id);
      rethrow;
    }
    notifyListeners(); // 홈 화면 위젯이 알림으로 다시 쓴다(Phase 007 A1)
    return true;
  }

  /// 체크를 켜고 끈다. 미래 날짜·계획 없는 날·목록에 없는 항목·보류한 항목·깨진 파일이면 false(쓰기 0).
  Future<bool> toggle(DateTime day, String id, DateTime today) async {
    if (!_canMark(day, id, today)) return false;
    final k = dayKey(day);
    if (heldOn(day).contains(id)) return false;
    // F-026 바뀜: 기본 지킴 DON'T는 누르면 '어김'(missed)을 켜고 끈다.
    final set = (_isDefaultDont(day, id) ? _missed : _done).putIfAbsent(k, () => <String>{});
    final on = !set.remove(id);
    if (on) set.add(id);
    try {
      await _write();
    } on Object {
      if (on) {
        set.remove(id);
      } else {
        set.add(id);
      }
      rethrow;
    }
    notifyListeners(); // 홈 화면 위젯이 알림으로 다시 쓴다(Phase 007 A1)
    return true;
  }

  /// F-039 정체성 문장(보이는 순서). 안 쓰면 빈 목록 — 정상 상태.
  List<String> get identities => List.unmodifiable(_identities);

  /// F-039 정체성 문장을 통째로 바꾼다. 앞뒤 공백을 지우고 빈 칸은 버린다.
  /// 실패면 이유(파일은 그대로), 성공·변화 없음이면 null. 쓰기 실패는 되돌리고 다시 던진다.
  Future<String?> saveIdentities(List<String> texts) async {
    if (broken) return '계획 파일을 읽지 못해 저장할 수 없습니다';
    final next = [for (final t in texts) if (t.trim().isNotEmpty) t.trim()];
    final error = validateIdentities(next);
    if (error != null) return error;
    if (_idsEqual(next, _identities)) return null;
    final old = List.of(_identities);
    _identities
      ..clear()
      ..addAll(next);
    try {
      await _write();
    } on Object {
      _identities
        ..clear()
        ..addAll(old);
      rethrow;
    }
    logInfo('정체성 문장 저장: ${next.length}개');
    notifyListeners(); // 맨 밑 계획 화면이 설정에서 바꾼 문장을 바로 그리게(목록 저장과 같이)
    return null;
  }

  // ---- F-024 하루 평가 — 계획과 따로 `reviews.json`(계획 파일 형식은 그대로) ----------------
  File get _reviewFile => File('${dir.path}/reviews.json');
  final _reviews = <String, String>{};
  var _reviewsLoaded = false;

  /// 평가 파일이 깨졌으면 true — 평가 저장만 거부한다(계획 체크는 그대로).
  bool reviewsBroken = false;

  void _loadReviews() {
    if (_reviewsLoaded) return;
    _reviewsLoaded = true;
    if (!_reviewFile.existsSync()) return;
    try {
      final j = jsonDecode(_reviewFile.readAsStringSync());
      if (j is! Map) throw const FormatException('객체가 아님');
      (j['reviews'] as Map).forEach((k, v) => _reviews[k as String] = v as String);
    } on Object catch (e) {
      logError('하루 평가 파일을 읽지 못함 — 평가 저장을 막는다(파일은 그대로 둠)', e);
      _reviews.clear();
      reviewsBroken = true;
    }
  }

  /// 그날의 평가. 없으면 null.
  String? reviewOn(DateTime day) {
    _loadReviews();
    return _reviews[dayKey(day)];
  }

  /// 그날 평가를 저장한다(공백뿐이면 지운다). 미래·깨진 파일·[maxReviewChars] 초과면 false(쓰기 0).
  /// 같은 글이면 쓰지 않고 true. 쓰기 실패는 되돌리고 다시 던진다.
  Future<bool> saveReview(DateTime day, String text, DateTime today) async {
    _loadReviews();
    if (reviewsBroken) return false;
    if (dayKey(day).compareTo(dayKey(today)) > 0) return false;
    if (text.length > maxReviewChars) return false;
    final k = dayKey(day);
    final value = text.trim().isEmpty ? null : text;
    final old = _reviews[k];
    if (old == value) return true;
    if (value == null) {
      _reviews.remove(k);
    } else {
      _reviews[k] = value;
    }
    try {
      await _atomicWrite(_reviewFile, {'version': 1, 'reviews': Map.of(_reviews)});
    } on Object {
      if (old == null) {
        _reviews.remove(k);
      } else {
        _reviews[k] = old;
      }
      rethrow;
    }
    logInfo('하루 평가 저장: $k ${value?.length ?? 0}자');
    return true;
  }

  Future<void> _write() => _atomicWrite(_file, {
        'version': 1,
        'next_id': _nextId,
        'lists': [
          for (final v in _versions)
            {'from': v.from, 'items': [for (final i in v.items) i.toJson()], if (v.weekend != null) 'weekend': v.weekend},
        ],
        'done': {
          for (final e in _done.entries)
            if (e.value.isNotEmpty) e.key: e.value.toList()..sort(),
        },
        'held': {
          for (final e in _held.entries)
            if (e.value.isNotEmpty) e.key: e.value.toList()..sort(),
        },
        'released': {
          for (final e in _released.entries)
            if (e.value.isNotEmpty) e.key: e.value.toList()..sort(),
        },
        'holidays': _holidays.toList()..sort(),
        if (_dontRestFrom != null) 'dont_rest_from': _dontRestFrom,
        if (_dontFrom != null) 'dont_default_from': _dontFrom,
        'missed': {
          for (final e in _missed.entries)
            if (e.value.isNotEmpty) e.key: e.value.toList()..sort(),
        },
        if (_identities.isNotEmpty) 'identities': List.of(_identities),
      });

  /// 임시 파일에 쓰고 바꿔치기 — 계획·평가 파일이 같이 쓴다(쓰기 지점 하나, file_writers_test).
  Future<void> _atomicWrite(File file, Map<String, Object?> j) async {
    try {
      dir.createSync(recursive: true);
      await writeAtomic(file, jsonEncode(j));
    } on Object catch (e, st) {
      logError('계획 파일 저장 실패(${file.uri.pathSegments.last})', e, st);
      rethrow;
    }
  }
}

bool _idsEqual(List<String> a, List<String> b) => a.length == b.length && a.join('\n') == b.join('\n');

bool _listEquals(List<PlanItem> a, List<PlanItem> b) {
  if (a.length != b.length) return false;
  for (var k = 0; k < a.length; k++) {
    if (a[k] != b[k]) return false;
  }
  return true;
}
