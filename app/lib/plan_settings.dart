/// F-016 설정 → 매일 계획 편집(목업 ③, 2026-11-08 "이대로"). 추가·이름 바꾸기·지우기·끌어서 순서 — 바꿀 때마다 바로 저장.
/// 바꾼 목록은 오늘부터 적용된다(지난 날은 그대로 — plans.dart). F-026 DO·DON'T 두 묶음, 순서는 묶음 안에서.
/// F-031 평일 계획 · 주말·휴일 계획 두 편집 화면. 주말 편집은 새 항목을 맨 위에 넣고, 묶음 아래에 보류된 평일 계획('풀기' = 편입).
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
  static String _summary(List<PlanItem> items, {int held = 0}) {
    if (items.isEmpty && held == 0) return '아직 없음';
    final kinds = "DO ${items.where((i) => i.kind == PlanKind.doIt).length} · DON'T ${items.where((i) => i.kind == PlanKind.dont).length}";
    return [kinds, if (held > 0) '보류 $held', if (items.isNotEmpty) items.map((i) => i.title).join(', ')].join(' · ');
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
      _tile('평일 계획', Icons.event_available, _summary(s.weekdayItems), false),
      _tile('주말·휴일 계획', Icons.weekend_outlined, _summary(s.weekendItems, held: s.weekendHeldItems.length), true),
    ]);
  }
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

  void _reorder(PlanKind kind, int from, int to) {
    final rows = _rowsOf(kind);
    final r = rows.removeAt(from);
    rows.insert(to > from ? to - 1 : to, r);
    _save(_join(kind, rows));
    // saveItems는 파일 쓰기(await) 전에 목록을 바꿔 둔다 — 바로 다시 그려 놓은 자리로 되튀는 깜빡임을 막는다.
    setState(() {});
  }

  /// F-031 보류된 평일 계획을 주말 계획 맨 아래로 편입.
  Future<void> _release(PlanItem it) =>
      _save(_join(it.kind, [..._rowsOf(it.kind), (it.id, it.title, it.kind)]));

  /// 한 묶음 — 제목 · 끌어서 순서 · 추가 칸(F-031 주말은 보류된 평일 계획 줄도).
  List<Widget> _section(ThemeData theme, PlanKind kind) {
    final rows = _rowsOf(kind);
    final dont = kind == PlanKind.dont;
    final weekdayIds = {for (final i in s.weekdayItems) i.id};
    final held = _weekend ? [for (final i in s.weekendHeldItems) if (i.kind == kind) i] : const <PlanItem>[];
    final dim = theme.colorScheme.outline;
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
      for (final it in held)
        ListTile(
          key: ValueKey('plan-held-${it.id}'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.pause_circle_outline, color: dim),
          title: Text(it.title, style: TextStyle(color: dim)),
          subtitle: Text('평일 계획 · 보류', style: theme.textTheme.labelSmall?.copyWith(color: dim)),
          trailing: TextButton(
              key: ValueKey('plan-release-${it.id}'), onPressed: () => _release(it), child: const Text('풀기')),
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
          Text('토·일과 계획 화면에서 휴일로 지정한 날에 씁니다. 평일 계획은 보류로 보이고, \'풀기\'로 주말 계획에 넣을 수 있습니다.',
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
