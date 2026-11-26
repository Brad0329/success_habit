/// F-042 두 번 연속 빠지지 않기 — 첫 목록 날부터 오늘까지 한 번 훑어 항목별 연속(🔥)·직전 놓침 횟수와
/// '두 번 연속 놓친 날'(달력 점)을 낸다. 계산만 한다(저장 없음).
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
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

PlanStreaks planStreaks(PlanStore store, DateTime today) {
  final t = _day(today);
  final first = store.firstDay;
  final runs = <String, _Run>{};
  final doubleMiss = <String>{};
  final shown = <String, PlanStreak>{};
  if (first == null) return PlanStreaks(shown, doubleMiss);
  for (var d = _day(first); !d.isAfter(t); d = DateTime(d.year, d.month, d.day + 1)) {
    final items = store.itemsOn(d);
    if (items == null) continue;
    final held = store.heldOn(d);
    final done = store.doneOn(d);
    final isToday = d == t;
    for (final i in items) {
      if (held.contains(i.id)) continue;
      final r = runs.putIfAbsent(i.id, _Run.new);
      final byDefault = i.kind == PlanKind.dont && store.dontDefaultOn(d);
      final missed = !done.contains(i.id) && (!isToday || byDefault);
      // 오늘 기본 지킴 DON'T는 하루가 끝나야 확정 — 연속엔 넣되 직전 놓침 강조는 그대로 둔다.
      if (isToday && byDefault && !missed && r.miss > 0) {
        shown[i.id] = (streak: 1, misses: r.miss);
        continue;
      }
      if (done.contains(i.id)) {
        r.ok++;
        r.miss = 0;
      } else if (missed) {
        if (r.miss > 0) doubleMiss.add(dayKey(d));
        r.miss++;
        r.ok = 0;
      }
      if (isToday) shown[i.id] = (streak: r.ok, misses: missed && r.miss < 2 ? 0 : r.miss);
    }
  }
  return PlanStreaks(shown, doubleMiss);
}
