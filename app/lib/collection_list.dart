/// F-010 수집물 목록 — 폰의 모든 달 폴더를 읽어 날짜별 목록·글자 검색에 쓸 목록을 만든다. 화면 없는 순수 로직.
///
/// **읽기만 한다**: [RecordReader]만 받는다 — 예외는 F-018 [Collection.delete](사용자가 고른 한 건, `record_delete.dart`).
/// 디스크 캐시는 두지 않는다(기존판 캐시는 Drive 내려받기를 줄이려던 것 — 원본이 폰에 있다). 마지막으로 읽은 목록을
/// 메모리에 들고 있다가 두 번째부터는 새 수집물만 읽는다. 로그에는 수집물 본문·메모·검색어를 남기지 않는다 — 건수만.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'ai_result.dart';
import 'collection.dart';
import 'log.dart';
import 'phone_store.dart';
import 'photo_group.dart';
import 'record.dart' as rules; // 'record'는 CollectedItem 필드 이름과 겹친다
import 'record_delete.dart';

const _inputLabels = {
  'share': '공유',
  'paste': '붙여넣기',
  'voice': '녹음',
  'pc_text': 'PC 단축키',
  'pc_capture': 'PC 캡처',
  'pc_file': 'PC 보내기',
};

/// 목록의 수집물 하나 — 사이드카 + (텍스트·링크면) 원문 + 덧붙임 결과(있으면).
class CollectedItem {
  CollectedItem(this.record, this.meta, [this.text, this.ai, this.user])
      : pages = const [],
        groupTotal = null;

  /// F-028 사진 묶음 한 건 — 대표 장([rep])에 장 순서대로의 [pages](대표 포함)를 붙인 것. 캐시에는 장마다 따로 남는다.
  CollectedItem._group(CollectedItem rep, this.pages, this.groupTotal)
      : record = rep.record,
        meta = rep.meta,
        text = rep.text,
        ai = rep.ai,
        user = rep.user;

  final ListedRecord record;
  final Map<String, Object?> meta;

  /// F-028 묶음의 장(장 순서, 대표 포함) — 묶음이 아니면 빈 목록.
  final List<CollectedItem> pages;

  /// F-028 사이드카의 `group_size` — 다 모이지 않았으면 [pages] 수보다 크다.
  final int? groupTotal;

  bool get isGroup => pages.isNotEmpty;

  /// 폰에 없는 장 수("N장 중 M장").
  int get missingPages => isGroup ? (groupTotal ?? pages.length) - pages.length : 0;

  /// 지우기에 넘길 대표가 아닌 장들.
  List<String> get otherBases => [for (final p in pages) if (p.base != base) p.base];

  /// 텍스트·링크 원문(검색·전체 보기·복사용). 그 외 종류는 null.
  final String? text;

  /// 읽은 AI 결과·사용자 수정([ResultRef.data]가 null이면 파일이 깨졌던 것 — 다시 읽지 않는다).
  /// 결과 파일을 만드는 것은 Phase 004(F-011)부터다 — 여기서는 있는 파일을 SCHEMA 규칙대로 읽기만 한다.
  final ResultRef? ai;
  final ResultRef? user;

  Map<String, Object?>? get _ai => ai?.data;
  String? _aiStr(String k) => _ai?[k] is String && (_ai![k]! as String).isNotEmpty ? _ai![k]! as String : null;

  /// 사용자가 고친 제목이 AI보다 우선(SCHEMA — 항목마다 user 값이 있으면 그것). 없으면 null.
  String? get title {
    final t = user?.data?['title'];
    return t is String && t.isNotEmpty ? t : _aiStr('title');
  }

  String get base => record.base;
  String get originalPath => record.original!.path;
  String get kind => meta['kind'] as String? ?? '';
  String get mime => (meta['mime'] as String? ?? '').toLowerCase();
  String? get caption => _str('caption');
  String? get originalName => _str('original_name');
  String get input => meta['input'] as String? ?? '';
  int? get size => meta['size'] is int ? meta['size']! as int : null;

  bool get isText => kind == 'text' || kind == 'url';
  bool get isUrl => kind == 'url';
  bool get isVoice => rules.isVoiceMeta(meta);
  bool get isImage => !isText && mime.startsWith('image/');

  /// 파일 이름 날짜 `YYYYMMDD`(수집한 기기 현지 시각).
  String get date => base.substring(0, 8);

  /// 파일 이름 시각 `HH:MM`.
  String get time => '${base.substring(9, 11)}:${base.substring(11, 13)}';

  String get deviceLabel => meta['device'] == 'pc' ? 'PC' : '폰';
  String get inputLabel => _inputLabels[input] ?? input;

  String get kindLabel => switch (kind) {
        'url' => '링크',
        'text' => '텍스트',
        _ when isVoice => '녹음',
        _ when isImage => '이미지',
        _ => '파일',
      };

  /// 목록 한 줄 미리보기 — 텍스트는 원문 앞부분, 링크는 주소, 그 외는 메모·파일 이름.
  String get preview {
    if (isText) return (text ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (isGroup) return caption ?? '사진 ${pages.length}장';
    return caption ?? originalName ?? kindLabel;
  }

  /// 검색 대상: 원문 + 메모 + 파일 이름(출처는 넣지 않는다 — REQUIREMENTS F-010) + 제목.
  late final String _haystack = [
    text ?? '', caption ?? '', originalName ?? '', title ?? '',
    for (final p in pages) ...[p.caption ?? '', p.originalName ?? ''], // F-028 각 장의 메모·파일 이름
  ].join('\n').toLowerCase();

  String? _str(String k) {
    final v = meta[k];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// 같은 수집물, 결과만 바꾼 것(원본·사이드카는 다시 읽지 않는다).
  /// 묶음이면 장 목록을 그대로 둔다(항목 보기에서 고친 뒤 지우기가 대표만 지우지 않게).
  CollectedItem withResults(ListedRecord rec, ResultRef? ai, ResultRef? user) {
    final one = CollectedItem(rec, meta, text, ai, user);
    return isGroup ? CollectedItem._group(one, pages, groupTotal) : one;
  }
}

/// 읽은 결과 파일 하나 — 파일 이름(증분 판정용) + 내용(깨졌으면 null).
class ResultRef {
  const ResultRef(this.name, this.data);
  final String name;
  final Map<String, Object?>? data;
}

/// F-028 폰 공유 사진 묶음을 한 건으로 합친다 — 대표 장 자리(시각)에 한 줄, 장은 장 순서대로.
/// 옛 묶음(장마다 따로 분석된 것)·섞인 묶음은 장마다. 결과는 최신 먼저.
List<CollectedItem> groupPhotoItems(List<CollectedItem> raw) {
  final byGid = <String, List<CollectedItem>>{};
  for (final i in raw) {
    final g = i.meta['group_id'];
    if (!i.isGroup && g is String && g.isNotEmpty) (byGid[g] ??= []).add(i);
  }
  final merged = <String, CollectedItem>{}; // 대표 base → 합친 것
  final absorbed = <String>{};
  for (final list in byGid.values) {
    // 모든 장이 폰 공유 사진이어야 한 건이다 — 섞인 묶음(사진 + 문서)의 사진만 따로 묶지 않는다.
    if (!isPhotoGroup(list.map((i) => i.meta))) continue;
    final rep = representative(list.map((i) => i.base));
    final aiIds = {for (final i in list) if (i.ai != null) i.base: [i.ai!.data?['group_id'] as String?]};
    if (isOldGroup(rep, aiIds, {for (final i in list) if (i.user != null) i.base})) continue;
    final byBase = {for (final i in list) i.base: i};
    final order = pageOrder([for (final i in list) (i.base, i.originalName)]);
    merged[rep] = CollectedItem._group(byBase[rep]!, [for (final b in order) byBase[b]!], groupSize(byBase[rep]!.meta));
    absorbed.addAll(byBase.keys);
  }
  if (merged.isEmpty) return raw;
  return [
    for (final i in raw)
      if (merged[i.base] case final g?) g else if (!absorbed.contains(i.base)) i,
  ];
}

/// 한 번 읽은 목록. [items]는 최신 먼저, F-028 사진 묶음은 한 건([groupPhotoItems]). [raw]는 장마다(캐시에 저장하는 것).
class CollectionSnapshot {
  CollectionSnapshot(this.raw, {required this.unreadable, required this.failed, required this.at})
      : items = groupPhotoItems(raw);

  final List<CollectedItem> raw;
  final List<CollectedItem> items;

  /// 사이드카 없는 원본·원본 없는 사이드카·깨진 사이드카·규칙에 안 맞는 이름.
  final int unreadable;

  /// 이번 갱신에서 파일 읽기에 실패한 건수 — 목록에서 빠지고 다음 새로 고침 때 다시 읽는다.
  final int failed;

  /// 마지막으로 나무에서 갱신한 시각.
  final DateTime at;
}

/// 공백으로 나눈 단어가 모두 들어 있는 것(대소문자 무시, 부분 일치). 공백뿐이면 전체.
List<CollectedItem> searchItems(List<CollectedItem> items, String query) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return items;
  return [for (final i in items) if (words.every(i._haystack.contains)) i];
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 목록 위 상태 줄 — "전체 128건 · 11:02 갱신 · 읽지 못함 1건".
/// 검색 중이면 "검색 결과 N건 / 전체 M건". 조용히 빼지 않고 빠진 건수를 모두 붙인다.
String statusLine(CollectionSnapshot s, {int? matched, bool refreshFailed = false}) {
  final total = s.items.length;
  final parts = [
    if (matched != null) '검색 결과 $matched건 / 전체 $total건' else '전체 $total건',
    '${_two(s.at.hour)}:${_two(s.at.minute)} 갱신${refreshFailed ? ' · 갱신 실패' : ''}',
    if (s.unreadable > 0) '읽지 못함 ${s.unreadable}건',
    if (s.failed > 0) '${s.failed}건 못 읽음',
  ];
  return parts.join(' · ');
}

/// 목록 읽기 — 마지막 목록(메모리) + 나무 갱신. 갱신이 겹치면 진행 중인 것 하나를 같이 기다린다.
class Collection {
  Collection({required this.reader, this.deleter, this.now = DateTime.now});

  final RecordReader Function() reader;

  /// F-018 지우기 — null이면 지우기 버튼이 없다(테스트).
  final RecordDeleter Function()? deleter;
  final DateTime Function() now;
  Future<CollectionSnapshot>? _running;
  CollectionSnapshot? _last;

  /// 이번 실행에서 지운 건 — 지우기 전에 시작한 새로 고침이 옛 목록으로 되살리지 않게 뺀다.
  final _gone = <String>{};

  /// 마지막으로 읽은 목록(앱을 켠 뒤 아직 안 읽었으면 null) — 화면을 바로 그리려고.
  CollectionSnapshot? cached() => _last;

  /// 항목 보기 이미지·녹음 원본 — 폰 파일을 그대로 읽는다.
  Future<Uint8List> original(String path) => reader().read(path);

  /// F-018 [base] 건을 폰에서 완전 삭제하고 마지막 목록에서 뺀다. 지운 파일 수를 돌려준다.
  /// F-028 사진 묶음이면 [others] = 대표가 아닌 장들 — 그 장들을 먼저, 대표([base])를 맨 마지막에 지운다.
  /// 실패하면 [DeleteFailed] — 마지막 목록은 그대로(다음 새로 고침이 나무에 남은 대로 보인다).
  Future<int> delete(String base, {List<String> others = const []}) async {
    final bases = [...{...others}.where((b) => b != base), base]; // 겹친 장은 한 번만
    final n = await deleteRecords(reader(), deleter!(), bases);
    _gone.addAll(bases);
    final s = _last;
    if (s != null) {
      _last = CollectionSnapshot([for (final i in s.raw) if (!bases.contains(i.base)) i],
          unreadable: s.unreadable, failed: s.failed, at: s.at);
    }
    return n;
  }

  /// 나무에서 다시 읽는다. 폴더 나열이 실패하면 예외(화면은 마지막 목록 + "갱신 실패").
  /// [onProgress] = (읽은 수, 새로 읽을 전체 수) — 첫 읽기의 "N/M 읽는 중".
  Future<CollectionSnapshot> refresh({void Function(int done, int total)? onProgress}) =>
      _running ??= _refresh(onProgress).whenComplete(() => _running = null);

  Future<CollectionSnapshot> _refresh(void Function(int, int)? onProgress) async {
    final r = reader();
    _picked.clear(); // 고른 결과 파일은 이번 목록 기준
    final (listed, odd) = await listRecords(r, who: '목록');
    final items = <CollectedItem>[];
    final (todo, resultsOnly, orphans) = _triage(listed.values, items);
    var unreadable = odd + orphans;
    var failed = 0, done = 0, added = 0;
    final total = todo.length + resultsOnly.length;
    onProgress?.call(0, total);
    for (final e in todo) {
      try {
        items.add(await _read(r, e));
        added++;
      } on FormatException catch (err) {
        unreadable++;
        logWarn('목록: 깨진 사이드카 ${e.base}: ${err.message}');
      } on Object catch (err) {
        failed++;
        logWarn('목록: 파일 읽기 실패 ${e.base}: ${err.runtimeType}');
      }
      onProgress?.call(++done, total);
    }
    for (final (e, o) in resultsOnly) {
      final fresh = await _withNewResults(r, e, o);
      if (fresh == null) failed++;
      items.add(fresh ?? o); // 실패면 옛 결과로 보이고 다음 새로 고침 때 다시 읽는다(마지막 목록에 옛 이름이 남는다)
      onProgress?.call(++done, total);
    }
    items.removeWhere((x) => _gone.contains(x.base));
    items.sort((a, b) => b.base.compareTo(a.base));
    final snap = CollectionSnapshot(items, unreadable: unreadable, failed: failed, at: now());
    _last = snap;
    logInfo('목록 갱신: ${items.length}건(새로 읽음 $added), 읽지 못함 $unreadable, 못 읽음 $failed');
    return snap;
  }

  /// 이번에 나열한 건을 가른다 — 그대로인 것은 [keep]에 넣고, (새로 읽을 것, 결과 파일만 다시 읽을 것, 짝 없는 건수)를 돌려준다.
  (List<ListedRecord>, List<(ListedRecord, CollectedItem)>, int) _triage(
      Iterable<ListedRecord> listed, List<CollectedItem> keep) {
    final old = {for (final i in _last?.raw ?? const <CollectedItem>[]) i.base: i};
    final todo = <ListedRecord>[];
    final resultsOnly = <(ListedRecord, CollectedItem)>[];
    var orphans = 0;
    for (final e in listed) {
      if (e.original == null || e.meta == null) {
        orphans++; // 다른 엔진이 쓰는 중일 수도 — 다음 새로 고침 때 다시 본다
        _logOrphan(e);
        continue;
      }
      final o = old[e.base];
      final (la, lu) = _latest(e);
      if (o == null || o.record.original!.name != e.original!.name) {
        todo.add(e);
      } else if (o.ai?.name == la?.name && o.user?.name == lu?.name) {
        keep.add(o.withResults(e, o.ai, o.user));
      } else {
        resultsOnly.add((e, o)); // 결과 파일만 새로 생김 — 원본·사이드카는 다시 읽지 않는다
      }
    }
    return (todo, resultsOnly, orphans);
  }

  /// 결과 파일만 다시 읽은 것. 읽기 실패면 null(로그 1줄).
  Future<CollectedItem?> _withNewResults(RecordReader r, ListedRecord e, CollectedItem o) async {
    try {
      final (ai, user) = await _results(r, e);
      return o.withResults(e, ai, user);
    } on Object catch (err) {
      logWarn('목록: 결과 파일 읽기 실패 ${e.base}: ${err.runtimeType}');
      return null;
    }
  }

  /// 짝 없는 건의 이름 — 계속 남으면 무엇인지 찾을 수 있게(건수만으로는 찾기 어렵다 — 기존판 실사례 2026-11-18).
  void _logOrphan(ListedRecord e) {
    String has(StoreEntry? f) => f == null ? '없음' : '있음';
    final extra = e.aiFiles.length + e.userFiles.length + e.transcriptFiles.length;
    logWarn('목록: 짝 없는 수집물 ${e.base}(원본 ${has(e.original)} · 사이드카 ${has(e.meta)} · 덧붙임 $extra개)');
  }

  Future<CollectedItem> _read(RecordReader r, ListedRecord e) async {
    final meta = jsonDecode(utf8.decode(await r.read(e.meta!.path)));
    if (meta is! Map<String, Object?>) throw const FormatException('사이드카가 객체가 아님');
    // 화면이 문자열로 읽는 항목 — 타입이 틀리면 그릴 때 터지지 않게 여기서 '읽지 못함'으로 센다.
    for (final k in const ['kind', 'input', 'mime', 'caption', 'original_name', 'device']) {
      final v = meta[k];
      if (v != null && v is! String) throw FormatException('사이드카 $k가 문자열이 아님');
    }
    final kind = meta['kind'];
    final text = kind == 'text' || kind == 'url'
        ? utf8.decode(await r.read(e.original!.path), allowMalformed: true)
        : null;
    final (ai, user) = await _results(r, e);
    return CollectedItem(e, meta, text, ai, user);
  }

  /// 고른 결과 파일을 기억해 둔다 — 여럿일 때 로그가 한 번만 나가게.
  final _picked = <String, (StoreEntry?, StoreEntry?)>{};

  (StoreEntry?, StoreEntry?) _latest(ListedRecord e) => _picked[e.base] ??= (
        latestResult(e.aiFiles, base: e.base, what: 'AI 결과'),
        latestResult(e.userFiles, base: e.base, what: '사용자 수정'),
      );

  /// 가장 늦은 결과 파일 둘을 읽는다. 깨진 파일은 내용 null(로그 1줄), 읽기 실패는 예외.
  Future<(ResultRef?, ResultRef?)> _results(RecordReader r, ListedRecord e) async {
    Future<ResultRef?> one(StoreEntry? f, String what) async =>
        f == null ? null : ResultRef(f.name, parseResult(await r.read(f.path), base: e.base, what: what));
    final (la, lu) = _latest(e);
    return (await one(la, 'AI 결과'), await one(lu, '사용자 수정'));
  }
}
