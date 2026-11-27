/// F-037 계획 통계 화면 — 기간(빠른 선택·직접)을 골라 항목마다 "성공 / 해야 한 날 · 비율" + 막대(목업 '막대 목록', 2026-11-24).
/// DO·DON'T 묶음, 맨 위에 묶음별 합계, 지금 목록에 없는 항목은 아래 '지운 항목'. 읽기만 한다.
/// F-043 맨 아래 '연속 · 달별 추이' — 항목마다 기간 안 최장 연속 + 오늘 기준 최근 3달 비율 막대 + 지난달 대비 ▲▼(목업 2026-11-26 "이대로").
library;

import 'package:flutter/material.dart';

import 'plan_screen.dart';
import 'plan_stats.dart';
import 'plan_streak.dart';
import 'plans.dart';

/// 물음표를 누르면 뜨는 설명 풍선(2026-11-24 사용자) — 세는 규칙은 plan_stats.dart 머리말과 같다.
const _help = '통계는 이렇게 셉니다\n'
    '• 해야 한 날 = 그날 목록에 있고 보류가 아닌 날\n'
    '• 성공 = 그중 체크한 날 (DON\'T는 지킨 날)\n'
    '• 비율 = 성공 ÷ 해야 한 날\n'
    '• 보류 N일 = 그날 길게 눌러 보류한 날 — 해야 한 날에서 뺍니다\n'
    '• 주말·휴일에 자동으로 보류되는 평일 계획은 세지 않습니다 (그날 풀면 셉니다)\n'
    '• 오늘까지 셉니다 — 오늘 아직 안 한 항목은 비율이 낮게 보일 수 있습니다\n'
    '• 이름을 바꾼 항목은 한 줄로, 지금 목록에서 지운 항목은 따로 모읍니다\n'
    '• 최장 연속 = 고른 기간 안에서 해야 한 날을 이어서 해낸 가장 긴 날 수 (보류·주말 보류는 건너뜀, 오늘 아직은 끊지 않음)\n'
    '• 달별 추이 = 기간과 상관없이 오늘 기준 최근 $maxTrendMonths달의 달마다 비율, ▲▼는 지난달 대비 (지금 목록 항목만)';

class PlanStatsScreen extends StatefulWidget {
  const PlanStatsScreen({super.key, required this.store, this.now = DateTime.now});
  final PlanStore store;
  final DateTime Function() now;

  @override
  State<PlanStatsScreen> createState() => _PlanStatsScreenState();
}

class _PlanStatsScreenState extends State<PlanStatsScreen> {
  PlanPeriod? _period = PlanPeriod.month; // null = 직접 고른 기간
  late DateTime _from;
  late DateTime _to;
  final _search = TextEditingController(); // F-044 — 화면을 나가면 지워진다(저장 없음)

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTime get _today {
    final n = widget.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _setRange(periodRange(PlanPeriod.month, _today));
  }

  void _setRange((DateTime, DateTime) r) {
    _from = r.$1;
    _to = r.$2;
  }

  void _pick(PlanPeriod p) => setState(() {
        _period = p;
        _setRange(periodRange(p, _today));
      });

  Future<void> _custom() async {
    final today = _today;
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: DateTimeRange(start: _from, end: _to.isAfter(today) ? today : _to),
      helpText: '기간 고르기',
    );
    if (r == null || !mounted) return;
    setState(() {
      _period = null;
      _from = r.start;
      _to = r.end;
    });
  }

  static String _ymd(DateTime d) => dayKey(d);
  static String _md(DateTime d) => '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _pct((int, int) v) => v.$2 == 0 ? '—' : '${(v.$1 * 100 / v.$2).round()}%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = planStats(widget.store, _from, _to, _today);
    final q = _search.text;
    final st = filterStats(all, q);
    final sameYear = st.from.year == st.to.year;
    final range = st.days == 0
        ? '${_ymd(_from)} ~ (아직 오지 않은 기간)'
        : '${_ymd(st.from)} ~ ${sameYear ? _md(st.to) : _ymd(st.to)} (${st.days}일)';
    return Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('계획 통계'),
          SizedBox(width: 4),
          Tooltip(
            key: ValueKey('plan-stats-help'),
            message: _help,
            triggerMode: TooltipTriggerMode.tap,
            showDuration: Duration(seconds: 15),
            padding: EdgeInsets.all(12),
            margin: EdgeInsets.symmetric(horizontal: 16),
            child: Padding(padding: EdgeInsets.all(8), child: Icon(Icons.help_outline, size: 20)),
          ),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final p in PlanPeriod.values)
            ChoiceChip(label: Text(p.label), selected: _period == p, onSelected: (_) => _pick(p)),
          ChoiceChip(label: const Text('직접'), selected: _period == null, onSelected: (_) => _custom()),
        ]),
        const SizedBox(height: 10),
        Text(range, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
        if (widget.store.broken)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('계획 파일을 읽지 못했습니다',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 10),
        _searchField(theme, all, st),
        const SizedBox(height: 12),
        if (all.isEmpty)
          Text('이 기간에는 계획이 없습니다', style: theme.textTheme.bodyLarge)
        else if (st.isEmpty)
          Text("'$q'에 맞는 항목이 없습니다", key: const ValueKey('search-none'), style: theme.textTheme.bodyLarge)
        else ...[
          _totals(theme, st),
          for (final k in PlanKind.values) ..._section(theme, _label(k), [
            for (final s in st.current) if (s.item.kind == k) s,
          ]),
          ..._section(theme, '지운 항목', st.removed, faded: true),
          ..._trendSection(theme, planBestStreaks(widget.store, _from, _to, _today), planTrend(widget.store, _today)),
        ],
      ]),
    );
  }

  /// F-044 검색창 — 검색어가 있으면 아래에 "검색 결과 M개 / 이 기간 N개"(전체 건수를 함께).
  Widget _searchField(ThemeData theme, PlanStats all, PlanStats shown) {
    final count = shown.current.length + shown.removed.length;
    final total = all.current.length + all.removed.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        key: const ValueKey('plan-stats-search'),
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          hintText: '항목 이름으로 찾기',
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('plan-stats-search-clear'),
                  tooltip: '지우기',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_search.clear),
                ),
        ),
      ),
      if (_search.text.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('검색 결과 $count개 / 이 기간 $total개',
              key: const ValueKey('search-count'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ),
    ]);
  }

  static String _label(PlanKind k) => k == PlanKind.dont ? "DON'T" : 'DO';

  Widget _totals(ThemeData theme, PlanStats st) {
    final parts = [
      for (final k in PlanKind.values)
        if ([...st.current, ...st.removed].any((s) => s.item.kind == k))
          '${_label(k)} ${st.total(k).$1}/${st.total(k).$2} (${_pct(st.total(k))})',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('전체  ${parts.join(' · ')}', style: theme.textTheme.titleSmall),
    );
  }

  List<Widget> _section(ThemeData theme, String title, List<PlanStat> rows, {bool faded = false}) {
    if (rows.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Text(title, style: theme.textTheme.titleMedium),
      const SizedBox(height: 6),
      for (final s in rows) Opacity(opacity: faded ? 0.6 : 1, child: _row(theme, s)),
    ];
  }

  Widget _row(ThemeData theme, PlanStat s) {
    final color = s.item.kind == PlanKind.dont ? planDontColor : planDoColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s.item.title, style: theme.textTheme.bodyLarge, overflow: TextOverflow.ellipsis)),
          Text('${s.done} / ${s.due}일', style: theme.textTheme.bodyMedium),
          SizedBox(
            width: 52,
            child: Text(_pct((s.done, s.due)), textAlign: TextAlign.right, style: theme.textTheme.bodyMedium),
          ),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: s.rate ?? 0,
            minHeight: 8,
            color: color,
            backgroundColor: color.withAlpha(40),
          ),
        ),
        if (s.held > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('보류 ${s.held}일',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ),
      ]),
    );
  }

  /// F-043 '연속 · 달별 추이' 묶음 — 지금 목록 항목만. 보일 달이 없으면(깨진 파일·목록 없음) 묶음째 없음.
  List<Widget> _trendSection(ThemeData theme, Map<String, int> best, PlanTrend tr) {
    final items = [for (final i in widget.store.current) if (planNameMatches(i.title, _search.text)) i];
    if (items.isEmpty || tr.months.isEmpty) return const [];
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    final n = tr.months.length;
    return [
      const SizedBox(height: 20),
      Text('연속 · 달별 추이', style: theme.textTheme.titleMedium),
      Text('최장 연속은 고른 기간 안 · 달별 비율은 오늘 기준 최근 $n달', style: small),
      if (tr.totalMonths > n) Text('전체 ${tr.totalMonths}달 중 최근 $n달', key: const ValueKey('trend-cut'), style: small),
      const SizedBox(height: 6),
      for (final i in items) _trendRow(theme, i, best[i.id] ?? 0, tr),
    ];
  }

  Widget _trendRow(ThemeData theme, PlanItem item, int best, PlanTrend tr) {
    final color = item.kind == PlanKind.dont ? planDontColor : planDoColor;
    final rates = tr.rates[item.id] ?? List<double?>.filled(tr.months.length, null);
    final small = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(item.title, style: theme.textTheme.bodyLarge, overflow: TextOverflow.ellipsis)),
          Text(best > 0 ? '최장 🔥 $best일' : '최장 0일', key: ValueKey('best-${item.id}'), style: theme.textTheme.bodySmall),
        ]),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var k = 0; k < tr.months.length; k++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 32,
                      color: color.withAlpha(35),
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(heightFactor: rates[k] ?? 0, widthFactor: 1, child: ColoredBox(color: color)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('${tr.months[k].month}월 ${_rate(rates[k])}', key: ValueKey('trend-${item.id}-$k'), style: small),
                ]),
              ),
            ),
          SizedBox(width: 64, child: _delta(theme, item, tr.delta(item.id))),
        ]),
      ]),
    );
  }

  static String _rate(double? r) => r == null ? '—' : '${(r * 100).round()}%';

  /// 지난달 대비 ▲ 세이지 / ▼ 빨강 / ± 0 흐림 — 비교할 수 없으면 빈 칸.
  Widget _delta(ThemeData theme, PlanItem item, int? d) {
    if (d == null) return const SizedBox.shrink();
    final (text, color) = d > 0
        ? ('▲ $d%p', planDoColor)
        : d < 0
            ? ('▼ ${-d}%p', planDontColor)
            : ('± 0%p', theme.colorScheme.outline);
    return Text(text,
        key: ValueKey('delta-${item.id}'),
        textAlign: TextAlign.right,
        style: theme.textTheme.bodySmall?.copyWith(color: color));
  }
}
