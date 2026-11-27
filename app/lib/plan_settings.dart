/// F-016 설정 → 매일 계획 편집(목업 ③, 2026-11-08 "이대로"). 추가·이름 바꾸기·지우기·끌어서 순서 — 바꿀 때마다 바로 저장.
/// 바꾼 목록은 오늘부터 적용된다(지난 날은 그대로 — plans.dart). F-026 DO·DON'T 두 묶음, 순서는 묶음 안에서.
/// F-031 평일 계획 · 주말·휴일 계획 두 편집 화면. 주말 편집은 새 항목을 맨 위에 넣는다.
/// 보류된 평일 계획은 여기 보이지 않고 계획 화면 아래에 나오며, 길게 눌러 그날만 푼다(2026-11-22 사용자).
library;

import 'package:flutter/material.dart';

import 'app_menu.dart';
import 'item_edit.dart' show TextInputDialog;
import 'log.dart';
import 'plans.dart';

/// 설정 화면의 계획 줄 둘 — 평일 계획 · 주말·휴일 계획(F-031). 누르면 편집 화면.
class PlanSettingsTile extends StatefulWidget {
  const PlanSettingsTile({super.key, required this.store});
  final PlanStore store;

  @override
  State<PlanSettingsTile> createState() => _PlanSettingsTileState();
}

class _PlanSettingsTileState extends State<PlanSettingsTile> {
  static String _summary(List<PlanItem> items) {
    if (items.isEmpty) return '아직 없음';
    final kinds = "DO ${items.where((i) => i.kind == PlanKind.doIt).length} · DON'T ${items.where((i) => i.kind == PlanKind.dont).length}";
    return [kinds, items.map((i) => i.title).join(', ')].join(' · ');
  }

  Widget _tile(String title, IconData icon, String subtitle, bool weekend) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => PlanEditScreen(store: widget.store, weekend: weekend)));
          if (mounted) setState(() {});
        },
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        key: const ValueKey('identity-tile'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.person_outline),
        title: const Text('나는 이런 사람'),
        subtitle: Text(s.identities.isEmpty ? '선택 — 안 씀' : s.identities.join(' · '),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => IdentityEditScreen(store: s)));
          if (mounted) setState(() {});
        },
      ),
      _tile('평일 계획', Icons.event_available, _summary(s.weekdayItems), false),
      _tile('주말·휴일 계획', Icons.weekend_outlined, _summary(s.weekendItems), true),
    ]);
  }
}

/// F-039 '나는 이런 사람' 편집 — 칸 [maxIdentities]개 + 저장. 빈 칸은 버린다(칸을 비우고 저장 = 지우기). 안 써도 된다.
class IdentityEditScreen extends StatefulWidget {
  const IdentityEditScreen({super.key, required this.store});
  final PlanStore store;

  @override
  State<IdentityEditScreen> createState() => _IdentityEditScreenState();
}

class _IdentityEditScreenState extends State<IdentityEditScreen> {
  late final List<TextEditingController> _fields;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = widget.store.identities;
    _fields = [for (var k = 0; k < maxIdentities; k++) TextEditingController(text: k < now.length ? now[k] : '')];
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    String? error;
    try {
      error = await widget.store.saveIdentities([for (final c in _fields) c.text]);
    } on Object catch (e) {
      logError('정체성 문장 저장 실패', e);
      error = '저장하지 못했습니다';
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('나는 이런 사람'), actions: const [AppMenu()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('되고 싶은 사람을 한 문장으로 — 계획 화면 맨 위에 보입니다. 쓰지 않아도 됩니다.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        for (var k = 0; k < _fields.length; k++)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              key: ValueKey('identity-field-$k'),
              controller: _fields[k],
              maxLength: maxIdentityChars,
              onChanged: (_) => _error == null ? null : setState(() => _error = null),
              decoration: const InputDecoration(hintText: '나는 ○○한 사람이다', border: OutlineInputBorder()),
            ),
          ),
        if (_error != null)
          Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        const SizedBox(height: 12),
        FilledButton(key: const ValueKey('identity-save'), onPressed: _save, child: const Text('저장')),
      ]),
    );
  }
}

/// F-103 도움 동영상 링크 창(목업 ①). 저장 = 입력 글, 지우기 = 빈 글, 취소 = null.
/// 컨트롤러는 창이 다 닫힌 뒤에 버린다(`dialog_controller_guard_test`).
class VideoLinkDialog extends StatefulWidget {
  const VideoLinkDialog({super.key, required this.title, required this.initial});
  final String title;
  final String initial;

  @override
  State<VideoLinkDialog> createState() => _VideoLinkDialogState();
}

class _VideoLinkDialogState extends State<VideoLinkDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('도움 동영상 — ${widget.title}'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            key: const ValueKey('video-field'),
            controller: _c,
            autofocus: true,
            maxLength: maxVideoUrlChars,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.of(context).pop(v),
            decoration: const InputDecoration(
              hintText: 'https://youtu.be/…',
              helperText: '유튜브 링크만 · 비우면 링크 없음',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          if (widget.initial.isNotEmpty)
            TextButton(key: const ValueKey('video-clear'), onPressed: () => Navigator.of(context).pop(''), child: const Text('지우기')),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
          FilledButton(key: const ValueKey('video-save'), onPressed: () => Navigator.of(context).pop(_c.text), child: const Text('저장')),
        ],
      );
}

class PlanEditScreen extends StatefulWidget {
  const PlanEditScreen({super.key, required this.store, this.weekend = false, this.now = DateTime.now});
  final PlanStore store;

  /// F-031 true = 주말·휴일 계획 편집.
  final bool weekend;
  final DateTime Function() now;

  @override
  State<PlanEditScreen> createState() => _PlanEditScreenState();
}

class _PlanEditScreenState extends State<PlanEditScreen> {
  // F-026 묶음마다 추가 칸 하나.
  final _add = {for (final k in PlanKind.values) k: TextEditingController()};
  String? _error;

  PlanStore get s => widget.store;
  bool get _weekend => widget.weekend;

  @override
  void dispose() {
    for (final c in _add.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 바뀐 목록을 저장한다. 실패면 이유를 보이고 목록은 그대로.
  Future<bool> _save(List<PlanRow> rows) async {
    try {
      final now = widget.now();
      final error = await (_weekend ? s.saveWeekend(rows, now) : s.saveItems(rows, now));
      setState(() => _error = error);
      return error == null;
    } on Object catch (e) {
      logError('${_weekend ? '주말' : '평일'} 계획 저장 실패', e);
      setState(() => _error = '저장하지 못했습니다');
      return false;
    }
  }

  List<PlanItem> get _items => _weekend ? s.weekendItems : s.weekdayItems;

  /// 저장 순서 = DO 묶음 다음 DON'T 묶음(화면 순서와 같게).
  List<PlanRow> _rowsOf(PlanKind kind) => [for (final i in _items) if (i.kind == kind) (i.id, i.title, i.kind)];
  List<PlanRow> _join(PlanKind kind, List<PlanRow> part) =>
      [for (final k in PlanKind.values) ...(k == kind ? part : _rowsOf(k))];

  Future<void> _addItem(PlanKind kind) async {
    final t = _add[kind]!.text.trim();
    if (t.isEmpty) return;
    // F-031 주말 계획에 새로 넣은 것은 맨 위.
    final rows = _weekend ? [(null, t, kind), ..._rowsOf(kind)] : [..._rowsOf(kind), (null, t, kind)];
    if (await _save(_join(kind, rows))) _add[kind]!.clear();
  }

  Future<void> _rename(PlanKind kind, int k) async {
    final rows = _rowsOf(kind);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(title: '이름 바꾸기', initial: rows[k].$2, maxLength: maxPlanChars, okLabel: '바꾸기'),
    );
    if (name == null) return;
    rows[k] = (rows[k].$1, name, kind);
    await _save(_join(kind, rows));
  }

  /// F-103 DO 계획의 도움 동영상 링크 창 — 저장·지우기(빈 글로 저장)·취소.
  Future<void> _editVideo(String id, String title) async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => VideoLinkDialog(title: title, initial: s.videoOf(id) ?? ''),
    );
    if (url == null) return;
    try {
      final error = await s.saveVideo(id, url);
      setState(() => _error = error);
    } on Object catch (e) {
      logError('도움 동영상 저장 실패', e);
      setState(() => _error = '저장하지 못했습니다');
    }
  }

  void _reorder(PlanKind kind, int from, int to) {
    final rows = _rowsOf(kind);
    final r = rows.removeAt(from);
    rows.insert(to > from ? to - 1 : to, r);
    _save(_join(kind, rows));
    // saveItems는 파일 쓰기(await) 전에 목록을 바꿔 둔다 — 바로 다시 그려 놓은 자리로 되튀는 깜빡임을 막는다.
    setState(() {});
  }

  /// F-103 영상 아이콘 — 링크가 있으면 강조색, 없으면 흐리게(목업 ① 2026-11-27 "이대로").
  Widget _videoButton(ThemeData theme, String id, String title) {
    final has = s.videoOf(id) != null;
    return IconButton(
      key: ValueKey('plan-video-$id'),
      tooltip: '도움 동영상',
      icon: Icon(has ? Icons.movie : Icons.movie_outlined,
          color: has ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
      onPressed: () => _editVideo(id, title),
    );
  }

  /// 한 묶음 — 제목 · 끌어서 순서 · 추가 칸.
  List<Widget> _section(ThemeData theme, PlanKind kind) {
    final rows = _rowsOf(kind);
    final dont = kind == PlanKind.dont;
    final weekdayIds = {for (final i in s.weekdayItems) i.id};
    return [
      Text(dont ? "DON'T" : 'DO', style: theme.textTheme.titleSmall),
      Text(dont ? '안 하기 — 지킨 날 체크' : '하기 — 한 날 체크', style: theme.textTheme.bodySmall),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: (from, to) => _reorder(kind, from, to),
        children: [
          // 줄 아무 데나 길게 눌러 끌기, 왼쪽 손잡이는 바로 끌기(2026-11-10 사용자 "손으로 밀면 오르내리게").
          for (var k = 0; k < rows.length; k++)
            ReorderableDelayedDragStartListener(
              key: ValueKey(rows[k].$1),
              index: k,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ReorderableDragStartListener(index: k, child: const Icon(Icons.drag_indicator)),
                title: Text(rows[k].$2),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!dont) _videoButton(theme, rows[k].$1!, rows[k].$2),
                  IconButton(
                      tooltip: '이름 바꾸기', icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(kind, k)),
                  // F-031 주말 편집에서 편입한 평일 계획은 지우지 않고 보류로 되돌린다.
                  if (_weekend && weekdayIds.contains(rows[k].$1))
                    IconButton(
                      tooltip: '보류로 되돌리기',
                      icon: const Icon(Icons.pause_circle_outline),
                      onPressed: () => _save(_join(kind, rows..removeAt(k))),
                    )
                  else
                    IconButton(
                      tooltip: '지우기',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _save(_join(kind, rows..removeAt(k))),
                    ),
                ]),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            key: ValueKey('plan-add-${kind.json}'),
            controller: _add[kind],
            decoration: InputDecoration(
              hintText: dont ? '새 DON\'T (예: 야식 안 먹기)' : (_weekend ? '새 DO (예: 등산)' : '새 DO (예: 물 2L 마시기)'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _addItem(kind),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
            key: ValueKey('plan-add-button-${kind.json}'), onPressed: () => _addItem(kind), child: const Text('추가')),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: Text(_weekend ? '주말·휴일 계획' : '평일 계획'), actions: const [AppMenu()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (s.broken)
          Text('계획 파일을 읽지 못했습니다 — 저장을 막아 두었습니다',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
        if (_weekend) ...[
          Text('토·일과 계획 화면에서 휴일로 지정한 날에 씁니다. 여기 넣은 계획은 그날 맨 위에 보이고, 평일 계획은 그 아래에 보류로 보입니다(길게 누르면 그날만 활성화).',
              style: small),
          const SizedBox(height: 12),
        ],
        ..._section(theme, PlanKind.doIt),
        const Divider(height: 32),
        ..._section(theme, PlanKind.dont),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: small?.copyWith(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 12),
        Text('${s.current.length}개 · 평일·주말을 합쳐 최대 $maxPlanItems개', style: small),
        const SizedBox(height: 4),
        Text('바꾼 목록은 오늘부터 적용됩니다. 지난 날의 계획과 체크는 그대로 남습니다.', style: small),
      ]),
    );
  }
}
