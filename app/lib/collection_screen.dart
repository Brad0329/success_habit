/// F-010 수집물 목록·항목 보기 화면 — 모양은 기존판과 같다(REQUIREMENTS '화면 방향').
///
/// 날짜별 목록 + 글자 검색, 항목을 누르면 전체 보기(텍스트 전문·이미지 크게·녹음 재생, 그 외 파일은 이름·크기).
/// 분류 칩·AI 결과 칸·'이것으로 대화하기'·유튜브·문서 글은 그 기능을 옮기는 Phase(004·005)에서 이 화면에 붙인다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_menu.dart';
import 'change_signal.dart';
import 'collection_list.dart';
import 'log.dart';
import 'record.dart' as record;
import 'record_delete.dart' show DeleteFailed;
import 'weekday.dart';

/// 목록 화면들이 쓰는 것 — 앱 시작 때 한 번 만든다. 테스트는 가짜를 넣는다.
class CollectionDeps {
  CollectionDeps({
    required this.collection,
    required this.openUrl,
    required this.openBytes,
    this.changed,
    this.now = DateTime.now,
  });

  /// F-029 저장 신호 — 목록이 열려 있는 동안 [watchEvery]마다 보고 바뀌었으면 새로 고친다. null이면 자동 갱신 없음(테스트).
  final ChangeSignal? changed;
  static const watchEvery = Duration(seconds: 3);

  final Collection collection;

  /// 브라우저로 주소 열기(채널 `openUrl`).
  final Future<void> Function(String url) openUrl;

  /// 폰 파일을 폰 기본 앱으로 열기(채널 `openBytes`) — 녹음 재생.
  final Future<void> Function(Uint8List data, String mime, String name) openBytes;

  final DateTime Function() now;
}

/// 날짜 머리줄 — "오늘 · 11월 3일 (화)", "어제 · …", 올해가 아니면 연도를 붙인다.
String dateHeader(String ymd, DateTime now) {
  final d = DateTime(int.parse(ymd.substring(0, 4)), int.parse(ymd.substring(4, 6)), int.parse(ymd.substring(6, 8)));
  final label = '${d.year != now.year ? '${d.year}년 ' : ''}${d.month}월 ${d.day}일 (${weekdayKo(d)})';
  final days = DateTime(now.year, now.month, now.day).difference(d).inDays;
  return switch (days) { 0 => '오늘 · $label', 1 => '어제 · $label', _ => label };
}

String formatSize(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

IconData kindIcon(CollectedItem i) => switch (i.kindLabel) {
      '텍스트' => Icons.notes,
      '링크' => Icons.link,
      '이미지' => Icons.image_outlined,
      '녹음' => Icons.mic_none,
      _ => Icons.insert_drive_file_outlined,
    };

/// F-028 묶음 장수 — "사진 N장", 다 모이지 않았으면 "N장 중 M장".
String groupPagesLabel(CollectedItem i) =>
    i.missingPages > 0 ? '${i.groupTotal}장 중 ${i.pages.length}장' : '사진 ${i.pages.length}장';

/// F-018 확인 창 — true면 지우기로 했다. 되돌릴 수 없다는 것을 적는다(휴지통 없음).
Future<bool> askDelete(BuildContext context, CollectedItem i) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('이 건을 지울까요?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(i.title ?? i.preview, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (i.isGroup) Text(groupPagesLabel(i)),
          const SizedBox(height: 12),
          Text(i.isGroup
              ? '폰에서 사진 ${i.pages.length}장과 딸린 파일(메타 정보·분류 결과 등)을 모두 지웁니다. '
                  '휴지통에 남지 않아 되돌릴 수 없습니다.'
              : '폰에서 이 건의 원본과 딸린 파일(메타 정보·분류 결과 등)을 모두 지웁니다. '
                  '휴지통에 남지 않아 되돌릴 수 없습니다.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('지우기', style: TextStyle(color: Theme.of(c).colorScheme.error)),
          ),
        ],
      ),
    ) ??
    false;

/// F-018 지운다 — 성공이면 null, 실패면 화면 문구(원인은 로그).
Future<String?> runDelete(CollectionDeps d, CollectedItem i) async {
  try {
    await d.collection.delete(i.base, others: i.otherBases); // F-028 묶음이면 모든 장(대표 맨 마지막)
    return null;
  } on DeleteFailed catch (e) {
    return e.userMessage; // record_delete.dart가 이미 로그를 남겼다
  } on Object catch (e, st) {
    logError('지우기 실패(파일 찾기) ${i.base}', e, st);
    return '지우지 못했습니다 — 다시 지우세요';
  }
}

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, required this.deps});
  final CollectionDeps deps;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  CollectionSnapshot? _snap;
  String _query = '';
  bool _refreshing = false;
  bool _refreshFailed = false;
  (int, int)? _progress;
  bool _deleting = false;
  Timer? _watch;

  CollectionDeps get d => widget.deps;

  /// F-029 신호가 바뀌었으면 새로 고친다. 새로 고침·지우기 중이면 이번엔 보지 않는다(신호는 다음 번에 그대로 보인다).
  void _tick() {
    final s = d.changed;
    if (!mounted || s == null || _refreshing || _deleting) return;
    if (!s.changed()) return;
    logInfo('목록: 저장 신호 — 새로 고침');
    _refresh();
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  /// F-018 길게 누름 → 확인 → 지우기. 성공하면 화면에서 바로 뺀다.
  Future<void> _delete(CollectedItem i) async {
    if (_deleting || !await askDelete(context, i)) return;
    setState(() => _deleting = true);
    final err = await runDelete(d, i);
    if (!mounted) return;
    final s = _snap;
    setState(() {
      _deleting = false;
      if (err == null && s != null) {
        final gone = {i.base, ...i.otherBases};
        _snap = CollectionSnapshot([for (final x in s.raw) if (!gone.contains(x.base)) x],
            unreadable: s.unreadable, failed: s.failed, at: s.at);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? '지웠습니다')));
  }

  @override
  void initState() {
    super.initState();
    _snap = d.collection.cached();
    d.changed?.start(); // 들어오며 새로 고치니 지금 신호는 기준만
    if (d.changed != null) _watch = Timer.periodic(CollectionDeps.watchEvery, (_) => _tick());
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _progress = null;
    });
    try {
      final s = await d.collection.refresh(onProgress: (done, total) {
        if (mounted) setState(() => _progress = (done, total));
      });
      if (mounted) {
        setState(() {
          _snap = s;
          _refreshFailed = false;
        });
      }
    } on Object catch (e, st) {
      logError('목록 갱신 실패', e, st);
      if (mounted) setState(() => _refreshFailed = true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String get _progressText {
    final p = _progress;
    return _refreshing && p != null && p.$2 > 0 ? ' · ${p.$1}/${p.$2} 읽는 중' : '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = _snap;
    return Scaffold(
      appBar: AppBar(title: const Text('목록'), actions: [
        IconButton(tooltip: '새로 고침', icon: const Icon(Icons.refresh), onPressed: _refreshing ? null : _refresh),
        const AppMenu(current: AppMenuItem.list),
      ]),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '검색',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        if (snap == null)
          Expanded(child: _empty(theme))
        else
          ..._list(theme, snap),
      ]),
    );
  }

  Widget _empty(ThemeData theme) => Center(
        child: _refreshing
            ? Text('읽는 중…${_progressText.replaceFirst(' · ', ' ')}')
            : Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('목록을 읽지 못했습니다 — 다시 시도'),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _refresh, child: const Text('다시 시도')),
              ]),
      );

  List<Widget> _list(ThemeData theme, CollectionSnapshot snap) {
    final searching = _query.trim().isNotEmpty;
    final shown = searchItems(snap.items, _query);
    final rows = <Object>[]; // String = 날짜 머리줄, CollectedItem = 한 줄
    for (final i in shown) {
      if (rows.isEmpty || (rows.last is CollectedItem && (rows.last as CollectedItem).date != i.date)) {
        rows.add(i.date);
      }
      rows.add(i);
    }
    final status = statusLine(snap, matched: searching ? shown.length : null, refreshFailed: _refreshFailed);
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('$status$_progressText', style: theme.textTheme.bodySmall),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: rows.isEmpty
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(searching ? "'${_query.trim()}' 결과 없음" : '아직 수집물이 없습니다', textAlign: TextAlign.center),
                  ),
                ])
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (c, n) {
                    final r = rows[n];
                    return r is String ? _header(theme, r) : _row(theme, r as CollectedItem);
                  },
                ),
        ),
      ),
    ];
  }

  Widget _header(ThemeData theme, String ymd) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 16, 4),
        child: Text(dateHeader(ymd, d.now()),
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
      );

  /// 목록 한 줄 — 디자인 B: 떠 있는 둥근 카드 한 장, 종류 아이콘은 옅은 원 안에.
  Widget _row(ThemeData theme, CollectedItem i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: _tile(theme, i)),
      );

  Widget _tile(ThemeData theme, CollectedItem i) {
    final cs = theme.colorScheme;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: cs.primaryContainer,
        child: Icon(kindIcon(i), size: 18, color: cs.primary),
      ),
      title: Text(i.title ?? i.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([i.time, i.deviceLabel, if (i.isGroup) groupPagesLabel(i), if (i.isText && i.caption != null) '메모 있음']
          .join(' · ')),
      onTap: () async {
        final changed = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
          builder: (_) => CollectionItemScreen(item: i, deps: d),
        ));
        if (changed != true || !mounted) return;
        // F-018 지웠으면 캐시에서 이미 빠졌다
        setState(() => _snap = d.collection.cached() ?? _snap);
        await _refresh();
      },
      onLongPress: d.collection.deleter == null || _deleting ? null : () => _delete(i),
    );
  }
}

class CollectionItemScreen extends StatefulWidget {
  const CollectionItemScreen({super.key, required this.item, required this.deps});
  final CollectedItem item;
  final CollectionDeps deps;

  @override
  State<CollectionItemScreen> createState() => _CollectionItemScreenState();
}

class _CollectionItemScreenState extends State<CollectionItemScreen> {
  /// 보이는 장 — F-028 묶음이면 장 순서대로 모든 장, 아니면 그 건 하나. [_images]도 같은 순서.
  late final List<CollectedItem> _shown = i.isGroup ? i.pages : [i];
  late final List<Future<Uint8List>?> _images = List.filled(_shown.length, null);
  String? _error;
  bool _busy = false;

  CollectedItem get i => widget.item;
  CollectionDeps get d => widget.deps;

  @override
  void initState() {
    super.initState();
    if (i.isImage) {
      for (var k = 0; k < _shown.length; k++) {
        _loadImage(k);
      }
    }
  }

  /// 실패는 여기서 한 번만 로그(화면은 다시 그릴 때마다 실패 문구만 보인다).
  void _loadImage(int k) => _images[k] = d.collection.original(_shown[k].originalPath).catchError((Object e) {
        logWarn('목록 항목: 이미지 읽기 실패 ${_shown[k].base}: ${e.runtimeType}');
        throw e;
      });

  /// 버튼 동작 공통 — 겹쳐 누름을 막고, 실패는 로그 + 화면 한 줄.
  Future<void> _guard(String what, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on PlatformException catch (e) {
      // 메시지에 열려던 주소(수집물 본문)가 섞일 수 있어 코드만 남긴다.
      logError('목록 항목: $what 실패 — 채널 오류 ${e.code}');
      if (mounted) setState(() => _error = '$what 못 했습니다 — 다시 시도하세요');
    } on Object catch (e, st) {
      logError('목록 항목: $what 실패', e, st);
      if (mounted) setState(() => _error = '$what 못 했습니다 — 다시 시도하세요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// F-018 확인 → 지우기 → 목록으로(pop true = 목록이 다시 그린다).
  Future<void> _delete() async {
    if (_busy || !await askDelete(context, i)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await runDelete(d, i);
    if (!mounted) return;
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지웠습니다')));
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: i.text ?? ''));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('복사했습니다')));
  }

  Future<void> _play() async {
    final data = await d.collection.original(i.originalPath);
    await d.openBytes(data, i.mime, '${i.base}.${record.extensionFor(i.kind, i.originalName, i.mime)}');
  }

  bool get _httpUrl => i.isUrl && RegExp(r'^https?://', caseSensitive: false).hasMatch((i.text ?? '').trim());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = '${int.parse(i.date.substring(4, 6))}월 ${int.parse(i.date.substring(6, 8))}일 ${i.time}';
    return Scaffold(
      appBar: AppBar(title: Text(when), actions: const [AppMenu()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text([i.kindLabel, i.deviceLabel, i.inputLabel].join(' · '), style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        if (i.caption != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText('메모: ${i.caption}'),
          ),
        _body(theme),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const Divider(height: 32),
        if (_httpUrl)
          _action(Icons.open_in_browser, '브라우저로 열기', () => _guard('브라우저로 열기', () => d.openUrl(i.text!.trim()))),
        if (i.isText) _action(Icons.copy, '복사', () => _guard('복사', _copy)),
        if (d.collection.deleter != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text('삭제', style: TextStyle(color: theme.colorScheme.error)),
            onTap: _busy ? null : _delete,
          ),
      ]),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) =>
      ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(label), onTap: _busy ? null : onTap);

  Widget _body(ThemeData theme) {
    final sizeLine = [i.originalName, if (i.size != null) formatSize(i.size!)].whereType<String>().join(' · ');
    if (i.isText) return SelectableText(i.text ?? '');
    if (i.isImage) {
      if (!i.isGroup) return _pageImage(theme, 0);
      // F-028 장을 세로로 이어 보기
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var k = 0; k < _shown.length; k++) ...[if (k > 0) const SizedBox(height: 16), _pageImage(theme, k)],
      ]);
    }
    if (i.isVoice) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
          onPressed: _busy ? null : () => _guard('재생', _play),
          icon: const Icon(Icons.play_arrow),
          label: Text(_busy ? '여는 중…' : '재생'),
        ),
        const SizedBox(height: 4),
        Text(['녹음', if (i.size != null) formatSize(i.size!), '폰 기본 재생 앱으로 열림'].join(' · '),
            style: theme.textTheme.bodySmall),
      ]);
    }
    return Text(sizeLine.isEmpty ? '파일' : sizeLine);
  }

  void _retryImage(int k) => setState(() => _loadImage(k));

  /// 이미지 한 장 — 눌러서 확대. 묶음이면 아래 줄이 "k / N · 파일 이름 · 눌러서 확대".
  Widget _pageImage(ThemeData theme, int k) {
    final p = _shown[k];
    final caption = i.isGroup
        ? ['${k + 1} / ${_shown.length}', if (p.originalName != null) p.originalName!, '눌러서 확대']
        : ['이미지', if (p.size != null) formatSize(p.size!), '눌러서 확대'];
    return FutureBuilder<Uint8List>(
      future: _images[k],
      builder: (c, s) {
        if (s.hasError) {
          return Row(children: [
            Expanded(child: Text(i.isGroup ? '${k + 1}장째 이미지를 못 읽음' : '이미지를 못 읽음')),
            TextButton(onPressed: () => _retryImage(k), child: const Text('다시 시도')),
          ]);
        }
        if (!s.hasData) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ZoomImage(s.data!))),
            child: Image.memory(s.data!, fit: BoxFit.contain, errorBuilder: (_, e, _) {
              logWarn('목록 항목: 이미지를 그리지 못함 ${p.base}: ${e.runtimeType}');
              return const Text('이미지를 열지 못함');
            }),
          ),
          const SizedBox(height: 4),
          Text(caption.join(' · '), style: theme.textTheme.bodySmall),
        ]);
      },
    );
  }
}

class _ZoomImage extends StatelessWidget {
  const _ZoomImage(this.data);
  final Uint8List data;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(actions: const [AppMenu()]),
        body: InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(data))),
      );
}
