/// F-042 두 번 연속 빠지지 않기 — 첫 목록 날부터 오늘까지 한 번 훑어 항목별 연속(🔥)·직전 놓침 횟수와
/// '두 번 연속 놓친 날'(달력 점)을 낸다. F-043 기간 안 최장 연속도 같은 판정으로 센다. 계산만 한다(저장 없음).
/// 해야 한 날 = 그날 목록에 있고 보류(쉬는 날 기본 보류 포함)가 아닌 날 — 그 밖의 날은 건너뛴다(끊지도 늘리지도 않음).
/// 오늘 아직 안 한 DO(와 옛 규칙 DON'T)는 '아직'이고, 기본 지킴 DON'T를 어겼으면 그날 놓침이 확정된다.
library;

import 'plans.dart';

/// 오늘 목록 한 항목의 표시. [misses]: 0 = 강조 없음, 1 = '어제 놓침 — 오늘은 꼭', 2 이상 = 'N회 연속 놓침'.
typedef PlanStreak = ({int streak, int misses});

class PlanStreaks {
  PlanStreaks(this.today, this.doubleMissDays);

  /// 오늘 해야 하는 항목 id → 표시. 오늘 보류한 항목·오늘 목록에 없는 항목은 없다.
  final Map<String, PlanStreak> today;

  /// 어떤 항목이든 직전 해야 한 날에 이어 또 놓친 날(`dayKey`) — 지난 날 + 오늘(확정된 놓침만).
  final Set<String> doubleMissDays;
}

class _Run {
  var ok = 0; // 이어진 성공
  var miss = 0; // 이어진 놓침
  var best = 0; // F-043 가장 길었던 성공 연속
}

enum _Mark { ok, miss, pending }

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// 그날 그 항목의 판정 — 해야 한 날이 아니면(보류·쉬는 날 기본 보류) null.
_Mark? _mark(PlanStore store, DateTime d, PlanItem i, Set<String> held, Set<String> done, bool isToday) {
  if (held.contains(i.id)) return null;
  if (done.contains(i.id)) return _Mark.ok;
  if (!isToday || (i.kind == PlanKind.dont && store.dontDefaultOn(d))) return _Mark.miss;
  return _Mark.pending;
}

/// [from]~[to]를 날마다 훑으며 항목마다 [onDay](그날 판정, 갱신된 연속)를 부른다. 계획 없는 날은 건너뛴다. [to]는 [today]까지로 자른다.
void _walk(PlanStore store, DateTime from, DateTime to, DateTime today,
    void Function(DateTime d, PlanItem i, _Mark m, _Run r, bool isToday) onDay) {
  final t = _day(today);
  final end = _day(to).isAfter(t) ? t : _day(to);
  final runs = <String, _Run>{};
  for (var d = _day(from); !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    final items = store.itemsOn(d);
    if (items == null) continue;
    final held = store.heldOn(d);
    final done = store.doneOn(d);
    final isToday = d == t;
    for (final i in items) {
      final m = _mark(store, d, i, held, done, isToday);
      if (m == null) continue;
      onDay(d, i, m, runs.putIfAbsent(i.id, _Run.new), isToday);
    }
  }
}

void _apply(_Run r, _Mark m) {
  if (m == _Mark.ok) {
    r.ok++;
    r.miss = 0;
    if (r.ok > r.best) r.best = r.ok;
  } else if (m == _Mark.miss) {
    r.miss++;
    r.ok = 0;
  }
}

PlanStreaks planStreaks(PlanStore store, DateTime today) {
  final first = store.firstDay;
  final doubleMiss = <String>{};
  final shown = <String, PlanStreak>{};
  if (first == null) return PlanStreaks(shown, doubleMiss);
  _walk(store, first, today, today, (d, i, m, r, isToday) {
    // 오늘 기본 지킴 DON'T는 하루가 끝나야 확정 — 연속엔 넣되 직전 놓침 강조는 그대로 둔다.
    final byDefault = i.kind == PlanKind.dont && store.dontDefaultOn(d);
    if (isToday && byDefault && m == _Mark.ok && r.miss > 0) {
      shown[i.id] = (streak: 1, misses: r.miss);
      return;
    }
    if (m == _Mark.miss && r.miss > 0) doubleMiss.add(dayKey(d));
    _apply(r, m);
    if (isToday) shown[i.id] = (streak: r.ok, misses: m == _Mark.miss && r.miss < 2 ? 0 : r.miss);
  });
  return PlanStreaks(shown, doubleMiss);
}

/// F-043 기간 [from]~[to](오늘까지로 자름) 안 항목별 최장 연속 — 기간 시작 전 날은 세지 않는다. 해야 한 날이 없던 항목은 없다.
Map<String, int> planBestStreaks(PlanStore store, DateTime from, DateTime to, DateTime today) {
  final best = <String, int>{};
  _walk(store, from, to, today, (d, i, m, r, isToday) {
    _apply(r, m);
    best[i.id] = r.best;
  });
  return best;
}
