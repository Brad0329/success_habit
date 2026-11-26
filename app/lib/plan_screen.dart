/// F-016 계획 화면 — 월 달력 + 고른 날의 체크 목록(목업 ④, 2026-11-08 "이대로"). 채록 첫 화면.
/// 날짜 칸 = "한 수/전체"(한 만큼 옅은 하늘색 → 다 함 스카이 블루로 진해짐·0은 색 없음, 미래는 표시 없음), 오늘 테두리, 고른 날 진한 테두리.
/// F-026: 칸 위 = DO(파랑, 진해짐)·아래 = DON'T(빨강, 지킬수록 옅어져 다 지키면 색 없음), 한쪽만 있으면 칸 전체. 목록도 DO 위·DON'T 아래.
/// F-031: 평일을 눌러 '휴일로 지정'(그날 주말 계획) — 휴일 날짜 숫자는 빨갛게. 쉬는 날의 보류된 평일 계획은 길게 눌러 그날만 풀기.
/// F-024: 체크 목록 맨 아래 '하루 평가하기' 칸(자동 저장) + 평가를 쓴 날을 누르면 그 칸이 커진 말풍선(목업 '가', 2026-11-13).
/// F-042: 오늘 목록에 '🔥 N일'(연속)·직전 놓침 강조(옅은 빨강 줄 + 문구), 두 번 연속 놓친 날은 달력 칸 오른쪽 위 빨간 점(목업 2026-11-26 "이대로").
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_menu.dart';
import 'log.dart';
import 'plan_stats_screen.dart';
import 'plan_streak.dart';
import 'plans.dart';
import 'weekday.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.store, this.now = DateTime.now});
  final PlanStore store;
  final DateTime Function() now;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}


/// DO 세이지·DON'T 산호빛 빨강 — 달력 칸과 통계 막대(F-037)가 같이 쓴다.
const planDoColor = Color(0xFF5FA585);
const planDontColor = Color(0xFFD2574E);

/// 평가 칸에서 치다 멈춘 뒤 저장까지(F-024 '약 1초').
const reviewSaveDelay = Duration(seconds: 1);

class _PlanScreenState extends State<PlanScreen> with WidgetsBindingObserver {
  late DateTime _month; // 그 달 1일
  late DateTime _sel;
  String? _note;

  // F-024 하루 평가 — 칸은 _reviewDay의 글을 담는다(_sel과 같다. 날짜를 바꿀 때 먼저 이전 날 것을 저장).
  final _review = TextEditingController();
  late DateTime _reviewDay;
  Timer? _debounce;
  String? _reviewNote;
  bool _reviewError = false;
  DateTime? _bubble; // 말풍선을 띄운 날짜
  PlanStreaks _streaks = PlanStreaks(const {}, const {}); // F-042 — build마다 다시 센다(체크·보류·휴일이 바꾼다)

  PlanStore get s => widget.store;

  /// 매번 다시 잰다 — 화면을 켜 둔 채 자정을 넘겨도 오늘이 맞게.
  DateTime get _today {
    final n = widget.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _month = DateTime(_today.year, _today.month);
    _sel = _today;
    _loadReview(_sel);
    WidgetsBinding.instance.addObserver(this);
    s.addListener(_onPlansChanged);
  }

  /// 설정(위에 쌓인 화면)에서 목록을 바꾸면 다시 그린다 — 이 화면은 맨 밑에 계속 떠 있다.
  void _onPlansChanged() {
    if (mounted) setState(() {});
  }

  /// 앱이 화면에서 내려갈 때(뒤로·홈·최근 앱에서 밀어 끄기 모두 paused를 거친다) 안 저장한 평가를 저장한다.
  /// 계획 화면이 맨 밑 화면이면 뒤로 = 앱 닫힘이라 dispose가 불린다는 보장이 없다(2026-11-19 spec-checker R1).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _flushReview();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.removeListener(_onPlansChanged);
    // 화면을 나갈 때 아직 안 저장한 글을 저장한다(화면은 사라지므로 결과는 로그로만 — _saveReview가 남긴다).
    _flushReview(mounted: false);
    _review.dispose();
    super.dispose();
  }

  /// 1초 기다리는 중인 평가가 있으면 지금 저장한다. 없으면 아무것도 안 한다(고친 게 없는데 쓰지 않게).
  void _flushReview({bool mounted = true}) {
    if (!(_debounce?.isActive ?? false)) return;
    _debounce!.cancel();
    unawaited(_saveReview(_reviewDay, _review.text, mounted: mounted));
  }

  void _loadReview(DateTime d) {
    _reviewDay = d;
    _review.text = s.reviewOn(d) ?? '';
    _reviewNote = null;
    _reviewError = false;
  }

  void _onReviewChanged(String _) {
    if (_bubble != null) setState(() => _bubble = null);
    _debounce?.cancel();
    final day = _reviewDay;
    _debounce = Timer(reviewSaveDelay, () => _saveReview(day, _review.text));
  }

  Future<void> _saveReview(DateTime day, String text, {bool mounted = true}) async {
    String note;
    var error = false;
    try {
      final ok = await s.saveReview(day, text, _today);
      final t = widget.now();
      note = ok ? '저장됨 · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}' : '저장하지 못했습니다';
      error = !ok;
      if (!ok) logWarn('하루 평가 저장 거부(${dayKey(day)} — 미래·깨진 파일·글자 수 초과)');
    } on Object catch (e) {
      logError('하루 평가 저장 실패', e);
      note = '저장하지 못했습니다';
      error = true;
    }
    if (mounted && this.mounted && day == _reviewDay) {
      setState(() {
        _reviewNote = note;
        _reviewError = error;
      });
    }
  }

  /// 날짜를 누름 — 안 저장한 평가를 먼저 저장하고, 그날 평가를 칸에 싣는다. 평가가 있는 날이면 말풍선(같은 날 다시 누르면 닫힘).
  void _select(DateTime d) {
    _flushReview();
    final text = s.reviewOn(d);
    setState(() {
      _bubble = (text != null && _bubble != d) ? d : null;
      _sel = d;
      _note = null;
      _loadReview(d);
    });
  }

  bool _future(DateTime d) => d.isAfter(_today);

  Future<void> _toggle(PlanItem item) async {
    try {
      final ok = await s.toggle(_sel, item.id, _today);
      setState(() => _note = ok ? null : (_future(_sel) ? '미래 날짜는 보기만 합니다' : '체크하지 못했습니다'));
    } on Object catch (e) {
      logError('계획 체크 저장 실패', e);
      setState(() => _note = '체크를 저장하지 못했습니다');
    }
  }

  /// F-031 고른 평일을 휴일로 지정 ↔ 해제.
  Future<void> _holiday() async {
    try {
      final ok = await s.toggleHoliday(_sel);
      setState(() => _note = ok ? null : '휴일을 바꾸지 못했습니다');
    } on Object catch (e) {
      logError('휴일 지정 저장 실패', e);
      setState(() => _note = '휴일을 저장하지 못했습니다');
    }
  }

  /// F-025 길게 누름 — 보류 ↔ 해제.
  Future<void> _hold(PlanItem item) async {
    try {
      final ok = await s.toggleHold(_sel, item.id, _today);
      setState(() => _note = ok ? null : (_future(_sel) ? '미래 날짜는 보기만 합니다' : '보류하지 못했습니다'));
    } on Object catch (e) {
      logError('계획 보류 저장 실패', e);
      setState(() => _note = '보류를 저장하지 못했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _streaks = planStreaks(s, _today);
    return Scaffold(
      appBar: AppBar(title: const Text('계획'), actions: [
        IconButton(
          key: const ValueKey('plan-stats'),
          tooltip: '통계',
          icon: const Icon(Icons.bar_chart),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => PlanStatsScreen(store: s, now: widget.now))),
        ),
        IconButton(
          tooltip: '이전 달',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() {
            _month = DateTime(_month.year, _month.month - 1);
            _bubble = null;
          }),
        ),
        Center(child: Text('${_month.year}년 ${_month.month}월', style: theme.textTheme.titleSmall)),
        IconButton(
          tooltip: '다음 달',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() {
            _month = DateTime(_month.year, _month.month + 1);
            _bubble = null;
          }),
        ),
        const AppMenu(current: AppMenuItem.plan),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
        if (s.broken)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('계획 파일을 읽지 못했습니다 — 체크와 저장을 막아 두었습니다',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
          ),
        // F-039 정체성 문장 — 0개면 칸째 없음(안 써도 되는 기능).
        if (s.identities.isNotEmpty) _identityBox(theme),
        _calendar(theme),
        const SizedBox(height: 8),
        _legend(theme),
        const SizedBox(height: 14),
        // 디자인 B: 고른 날 목록은 둥근 카드 한 장에
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _dayList(theme)),
          ),
        ),
      ]),
    );
  }

  /// F-039 달력 위 옅은 세이지색 칸에 정체성 문장 한 줄씩(길면 말줄임).
  Widget _identityBox(ThemeData theme) => Container(
        key: const ValueKey('identity-box'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: planDoColor.withAlpha(40), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final t in s.identities)
            Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
        ]),
      );

  Widget _calendar(ThemeData theme) {
    final first = _month;
    final days = DateTime(first.year, first.month + 1, 0).day;
    final lead = first.weekday % 7; // 일요일 시작
    final cells = <Widget>[
      for (final w in calendarHeader)
        Center(child: Text(w, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline))),
      for (var k = 0; k < lead; k++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++) _cell(theme, DateTime(first.year, first.month, d)),
    ];
    final grid = GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: _gap,
      crossAxisSpacing: _gap,
      childAspectRatio: _aspect,
      children: cells,
    );
    final b = _bubble;
    if (b == null || b.year != first.year || b.month != first.month) return grid;
    final index = 7 + lead + b.day - 1; // 요일 줄 7칸 뒤
    final rows = (7 + lead + days + 6) ~/ 7;
    return LayoutBuilder(builder: (context, box) {
      final cellW = (box.maxWidth - _gap * 6) / 7;
      final rowH = cellW / _aspect + _gap;
      final row = index ~/ 7, col = index % 7;
      final width = (box.maxWidth * 0.62).clamp(160.0, 260.0);
      final left = (col * (cellW + _gap) + cellW / 2 - width / 2).clamp(0.0, box.maxWidth - width);
      final bubble = _bubbleCard(theme, b, width);
      // 위쪽 줄은 칸 윗변에서 아래로, 아래쪽 줄은 칸 아랫변에서 위로 자란다 — 달력 밖으로 덜 나가게.
      final top = row * rowH;
      final bottom = (rows - row - 1) * rowH;
      return Stack(clipBehavior: Clip.none, children: [
        grid,
        if (row <= rows / 2)
          Positioned(left: left, top: top, child: bubble)
        else
          Positioned(left: left, bottom: bottom, child: bubble),
      ]);
    });
  }

  static const _gap = 3.0;
  static const _aspect = 0.95;

  /// F-026 그날 목록에 있는 종류(DO 먼저). 계획 없는 날은 빈 목록.
  List<PlanKind> _kindsOn(DateTime d) {
    final have = {for (final i in s.itemsOn(d) ?? const <PlanItem>[]) i.kind};
    return [for (final k in PlanKind.values) if (have.contains(k)) k];
  }

  static String _label(PlanKind k) => k == PlanKind.dont ? "DON'T" : 'DO';

  (Color, Color)? _toneOf(ThemeData theme, PlanKind k, (int, int) sum) =>
      k == PlanKind.dont ? _dontTone(theme, sum) : _tone(theme, sum);

  Widget _bubbleCard(ThemeData theme, DateTime d, double width) {
    final kinds = _kindsOn(d);
    final sums = {for (final k in kinds) k: s.summary(d, kind: k)!};
    final tone = kinds.isEmpty ? null : _toneOf(theme, kinds.first, sums[kinds.first]!);
    final bg = tone?.$1 ?? theme.colorScheme.surfaceContainerHighest;
    final fg = tone?.$2 ?? theme.colorScheme.onSurface;
    final counts = [for (final k in kinds) '${_label(k)} ${sums[k]!.$1}/${sums[k]!.$2}'].join(' · ');
    final head = '${d.month}월 ${d.day}일 (${weekdayKo(d)})${counts.isEmpty ? '' : ' · $counts'}';
    return GestureDetector(
      key: const ValueKey('review-bubble'),
      onTap: () => setState(() => _bubble = null),
      child: Material(
        elevation: 4,
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: fg, width: 1.5),
        ),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(head, style: theme.textTheme.titleSmall?.copyWith(color: fg)),
              const SizedBox(height: 4),
              Text(s.reviewOn(d) ?? '', maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: fg, height: 1.4)),
            ]),
          ),
        ),
      ),
    );
  }

  // 달성률 색(2026-11-13 사용자 '가' — 연속): 1개 = 시작색, 다 함 = 끝색, 그 사이는 한 개마다 고르게 섞는다.
  // 2026-11-17 디자인 B: 하늘색 → 세이지 초록(뜻은 그대로 — 많이 할수록 짙게).
  static const _sage = planDoColor;
  static const _startLight = Color(0xFFE2EEE6); // 아주 옅은 세이지
  static const _startDark = Color(0xFF1B2D24); // 어두운 숲색 — 다크 모드는 밝아지며 세이지로

  /// 칸 배경색과 글자색. 0개·계획 없음은 색 없음(null). [t] = (한 수 - 1) / (전체 - 1).
  (Color, Color) _toneAt(ThemeData theme, double t) {
    final dark = theme.brightness == Brightness.dark;
    final bg = Color.lerp(dark ? _startDark : _startLight, _sage, t)!;
    // 다크 모드는 앞쪽이 어두워 밝은 글자, 절반을 넘으면 칸이 밝아져 진한 초록 글자.
    final fg = dark && t < 0.55 ? const Color(0xFFDDEFE5) : const Color(0xFF163D2F);
    return (bg, fg);
  }

  (Color, Color)? _tone(ThemeData theme, (int, int) sum) {
    final (done, total) = sum;
    if (total == 0 || done == 0) return null;
    return _toneAt(theme, total == 1 ? 1 : (done - 1) / (total - 1));
  }

  // F-026 DON'T 색(2026-11-15 사용자): 하나도 안 지켰으면 가장 짙은 빨강, 지킬수록 옅어져 다 지키면 색 없음(흰색).
  // 2026-11-17 디자인 B: 세이지와 어울리는 산호빛 빨강.
  static const _red = planDontColor;

  /// [t] = 지킨 비율(0~1). 1이면 색 없음.
  (Color, Color) _dontToneAt(ThemeData theme, double t) {
    final dark = theme.brightness == Brightness.dark;
    final bg = _red.withAlpha(((1 - t) * 255).round());
    final fg = t < 0.5 ? Colors.white : (dark ? const Color(0xFFFFB4AB) : const Color(0xFF8E1B1B));
    return (bg, fg);
  }

  (Color, Color)? _dontTone(ThemeData theme, (int, int) sum) {
    final (kept, total) = sum;
    if (total == 0 || kept == total) return null;
    return _dontToneAt(theme, kept / total);
  }

  /// 달력 칸 — F-026 그날 목록에 DO·DON'T가 둘 다 있으면 위(DO)·아래(DON'T) 반쪽, 한쪽만 있으면 그쪽이 칸 전체.
  Widget _cell(ThemeData theme, DateTime d) {
    final future = _future(d);
    final kinds = future ? const <PlanKind>[] : _kindsOn(d);
    final isToday = d == _today;
    final isSel = d == _sel;
    final halves = kinds.isEmpty
        ? [Expanded(child: _half(theme, d, null, showDay: true))]
        : [for (var k = 0; k < kinds.length; k++) Expanded(child: _half(theme, d, kinds[k], showDay: k == 0))];
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _select(d),
      child: Container(
        decoration: BoxDecoration(
          color: future ? null : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            width: 1.5,
            color: isSel
                ? theme.colorScheme.onSurface
                : isToday
                    ? theme.colorScheme.primary
                    : Colors.transparent,
          ),
        ),
        child: Stack(children: [
          Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Column(children: halves))),
          if (_streaks.doubleMissDays.contains(dayKey(d)))
            Positioned(top: 4, right: 4, child: _missDot(theme, key: ValueKey('miss-dot-${dayKey(d)}'))),
        ]),
      ),
    );
  }

  /// F-042 두 번 연속 놓친 날 점.
  Widget _missDot(ThemeData theme, {Key? key}) => Container(
        key: key,
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: theme.colorScheme.error, shape: BoxShape.circle),
      );

  /// 칸의 한쪽 — [kind]가 null이면 계획 없는 날·미래(날짜만).
  Widget _half(ThemeData theme, DateTime d, PlanKind? kind, {required bool showDay}) {
    final sum = kind == null ? null : s.summary(d, kind: kind);
    final tone = sum == null ? null : _toneOf(theme, kind!, sum);
    // F-031 휴일로 지정한 평일은 날짜 숫자를 빨갛게(색 칸 위에서는 칸 글자색 그대로).
    final fg = tone?.$2 ??
        (s.isHoliday(d)
            ? theme.colorScheme.error
            : _future(d)
                ? theme.colorScheme.outline
                : theme.colorScheme.onSurface);
    return Container(
      color: tone?.$1,
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (showDay) Text('${d.day}', style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
          if (sum != null)
            Text('${sum.$1}/${sum.$2}',
                style: theme.textTheme.labelSmall?.copyWith(color: tone?.$2 ?? theme.colorScheme.outline)),
        ]),
      ),
    );
  }

  Widget _legend(ThemeData theme) {
    final small = theme.textTheme.labelSmall;
    Widget chip((Color, Color)? t, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: t?.$1, borderRadius: BorderRadius.circular(4)),
          child: Text(text, style: small?.copyWith(color: t?.$2)),
        );
    Widget bar(Color a, Color b) => Container(
          width: 72,
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.5),
            gradient: LinearGradient(colors: [a, b]),
          ),
        );
    return Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        chip(_toneAt(theme, 0), 'DO 조금'),
        const SizedBox(width: 6),
        bar(_toneAt(theme, 0).$1, _toneAt(theme, 1).$1),
        const SizedBox(width: 6),
        chip(_toneAt(theme, 1), '다 함'),
      ]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        chip(_dontToneAt(theme, 0), "DON'T 안 지킴"),
        const SizedBox(width: 6),
        bar(_dontToneAt(theme, 0).$1, _dontToneAt(theme, 1).$1),
        const SizedBox(width: 6),
        chip(null, '다 지킴'),
      ]),
      Text('0/N 안 함 · 미래는 표시 없음', style: small?.copyWith(color: theme.colorScheme.outline)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        _missDot(theme),
        const SizedBox(width: 4),
        Text('어떤 계획을 두 번 연속 놓친 날', style: small?.copyWith(color: theme.colorScheme.outline)),
      ]),
    ]);
  }

  List<Widget> _dayList(ThemeData theme) {
    final items = s.itemsOn(_sel);
    final future = _future(_sel);
    final done = s.doneOn(_sel);
    final held = s.heldOn(_sel);
    final rest = s.isRestDay(_sel);
    final title = '${_sel.month}월 ${_sel.day}일 (${weekdayKo(_sel)})${s.isHoliday(_sel) ? ' · 휴일' : ''}'
        '${_sel == _today ? ' · 오늘' : ''}';
    return [
      Row(children: [
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        // F-031 평일만 — 휴가·공휴일이면 휴일로 지정해 주말 계획을 쓴다.
        if (s.canSetHoliday(_sel))
          TextButton(
            key: const ValueKey('holiday-toggle'),
            onPressed: _holiday,
            child: Text(s.isHoliday(_sel) ? '휴일 해제' : '휴일로 지정'),
          ),
      ]),
      const SizedBox(height: 4),
      if (items == null || items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            s.current.isEmpty ? '설정 → 평일 계획에서 매일 할 계획을 넣으세요' : '이날은 계획이 없습니다',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
          ),
        )
      else
        // F-026 위 DO · 아래 DON'T 묶음(그날 목록에 없는 종류는 묶음째 없음).
        for (final k in _kindsOn(_sel)) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(child: Text(_label(k), style: theme.textTheme.titleSmall)),
              if (!future) Text(_count(k), style: theme.textTheme.bodySmall),
            ]),
          ),
          for (final it in items)
            if (it.kind == k)
              _planTile(theme, it,
                  future: future,
                  done: done.contains(it.id),
                  held: held.contains(it.id),
                  streak: _sel == _today ? _streaks.today[it.id] : null),
        ],
      if (future && items != null && items.isNotEmpty)
        Text('미래 날짜는 보기만 합니다. 그날이 되면 체크할 수 있습니다.', style: theme.textTheme.bodySmall)
      else if (items != null && items.isNotEmpty)
        Text(
            rest
                ? '주말·휴일 — 보류된 평일 계획은 길게 눌러 그날만 풀 수 있습니다'
                : '그날 할 수 없는 계획은 길게 눌러 보류 — 개수에서 빠집니다',
            style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline)),
      if (_note != null)
        Text(_note!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
      if (!future) ..._reviewBox(theme),
    ];
  }

  /// 묶음 머리의 "N / M 완료"(DO) · "N / M 지킴"(DON'T) — 보류는 M에서 빠진다.
  String _count(PlanKind k) {
    final (a, b) = s.summary(_sel, kind: k)!;
    return '$a / $b ${k == PlanKind.dont ? '지킴' : '완료'}';
  }

  /// 그날 목록 한 줄. F-025 길게 누르면 보류 ↔ 해제 — 보류한 항목은 흐리게 · 체크 칸 꺼짐.
  /// F-042 [streak]은 오늘 해야 하는 항목만(그 밖엔 null) — 연속 1 이상이면 '🔥 N일', 직전 놓침이면 옅은 빨강 줄 + 문구.
  Widget _planTile(ThemeData theme, PlanItem it,
      {required bool future, required bool done, required bool held, PlanStreak? streak}) {
    final dim = theme.colorScheme.outline;
    final warn = (streak?.misses ?? 0) > 0;
    return GestureDetector(
      key: ValueKey('plan-${it.id}'),
      onLongPress: future || s.broken ? null : () => _hold(it),
      child: CheckboxListTile(
        contentPadding: warn ? const EdgeInsets.symmetric(horizontal: 4) : EdgeInsets.zero,
        tileColor: warn ? theme.colorScheme.errorContainer : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        subtitle: _missText(theme, it, streak),
        controlAffinity: ListTileControlAffinity.leading,
        value: !future && done,
        onChanged: future || s.broken || held ? null : (_) => _toggle(it),
        title: Text(
          it.title,
          style: done && !future
              ? TextStyle(decoration: TextDecoration.lineThrough, color: dim)
              : held
                  ? TextStyle(color: dim)
                  : null,
        ),
        secondary: held ? Text('보류', style: theme.textTheme.labelSmall?.copyWith(color: dim)) : _fire(theme, it, streak),
      ),
    );
  }

  /// F-042 직전 놓침 문구 — 1회 '어제 놓침 — 오늘은 꼭', 2회 이상 'N회 연속 놓침', 없으면 null.
  Widget? _missText(ThemeData theme, PlanItem it, PlanStreak? streak) {
    final n = streak?.misses ?? 0;
    if (n == 0) return null;
    return Text(n == 1 ? '어제 놓침 — 오늘은 꼭' : '$n회 연속 놓침',
        key: ValueKey('miss-${it.id}'),
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer));
  }

  /// F-042 연속 1일 이상이면 '🔥 N일', 아니면 null.
  Widget? _fire(ThemeData theme, PlanItem it, PlanStreak? streak) {
    final n = streak?.streak ?? 0;
    return n > 0 ? Text('🔥 $n일', key: ValueKey('streak-${it.id}'), style: theme.textTheme.labelSmall) : null;
  }

  List<Widget> _reviewBox(ThemeData theme) => [
        const SizedBox(height: 16),
        Text('하루 평가하기', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('review-field'),
          controller: _review,
          enabled: !s.reviewsBroken,
          minLines: 3,
          maxLines: null,
          maxLength: maxReviewChars,
          keyboardType: TextInputType.multiline,
          onChanged: _onReviewChanged,
          decoration: const InputDecoration(
            hintText: '오늘 하루를 간단히 정리해 보세요',
            border: OutlineInputBorder(),
          ),
        ),
        if (s.reviewsBroken)
          Text('평가 파일을 읽지 못했습니다 — 저장을 막아 두었습니다',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))
        else if (_reviewNote != null)
          Text(_reviewNote!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: _reviewError ? theme.colorScheme.error : theme.colorScheme.outline)),
      ];
}
