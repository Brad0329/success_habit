/// F-037 계획 통계 — 기간 안 날마다 그날 목록·체크·보류를 세어 항목별 (성공, 해야 한 날, 보류한 날)을 낸다.
/// 계산만 한다(저장 없음). 항목은 id로 묶는다 — 이름을 바꿔도 한 줄, 지금 목록에 없는 항목은 '지운 항목'.
/// 해야 한 날 = 목록에 있고 보류가 아닌 날. 보류 = 직접 보류한 날만 — 쉬는 날 기본 보류(F-031)는 어느 쪽에도 안 센다.
library;

import 'plans.dart';

class PlanStat {
  PlanStat(this.item);

  /// 지금 항목이면 지금 이름, 지운 항목이면 기간 안에서 마지막으로 본 이름.
  PlanItem item;
  int done = 0;
  int due = 0;
  int held = 0;

  /// 해야 한 날이 0이면 null(화면은 "—").
  double? get rate => due == 0 ? null : done / due;
}

class PlanStats {
  PlanStats(this.from, this.to, this.days, this.current, this.removed);

  /// 센 기간 — [to]는 오늘까지로 자른 끝. [days] = 센 날 수(시작이 오늘보다 뒤면 0).
  final DateTime from;
  final DateTime to;
  final int days;
  final List<PlanStat> current;
  final List<PlanStat> removed;

  bool get isEmpty => current.isEmpty && removed.isEmpty;

  /// 종류별 합계 (성공, 해야 한 날).
  (int, int) total(PlanKind kind) {
    var done = 0, due = 0;
    for (final s in [...current, ...removed]) {
      if (s.item.kind != kind) continue;
      done += s.done;
      due += s.due;
    }
    return (done, due);
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// 비율(0~1) → 화면·위젯의 %(정수). % 를 만드는 반올림은 이것 하나뿐이다(one_rule_test) — 통계 합계·항목·달별 추이·▲▼·위젯 막대가
/// 같은 수에서 같은 %를 보이고, ▲▼(delta)는 화면에 보인 % 끼리의 차가 된다.
/// 1e-9를 더하는 이유: 0.145 * 100 = 14.4999…처럼 부동소수 오차로 x.5가 내림되는 것을 막는다(실제 비율이 x.5에서 1e-9 안쪽인 경우는 없다 —
/// 분모가 날 수·항목 수라 작다).
int ratePct(double rate) => (rate * 100 + 1e-9).round();

/// [from]~[to](둘 다 포함)를 [today]까지로 잘라 센다. 계획 없는 날은 건너뛴다.
PlanStats planStats(PlanStore store, DateTime from, DateTime to, DateTime today) {
  final start = _day(from);
  final end = _day(to).isAfter(_day(today)) ? _day(today) : _day(to);
  final byId = <String, PlanStat>{};
  var days = 0;
  for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    days++;
    final items = store.itemsOn(d);
    if (items == null) continue;
    final rest = store.restHeldOn(d);
    final due = store.dueOn(d);
    final done = store.doneOn(d);
    for (final i in items) {
      if (rest.contains(i.id)) continue; // 쉬는 날 기본 보류 — 해야 한 날도 보류한 날도 아니다
      final s = byId.putIfAbsent(i.id, () => PlanStat(i))..item = i;
      if (due.contains(i.id)) {
        s.due++;
        if (done.contains(i.id)) s.done++;
      } else {
        s.held++;
      }
    }
  }
  final current = <PlanStat>[];
  for (final i in store.current) {
    final s = byId.remove(i.id);
    if (s != null) current.add(s..item = i);
  }
  return PlanStats(start, end, days, current, byId.values.toList());
}

/// F-044 이름에 [query]가 들어 있나(띄어쓰기·대소문자 무시). 빈 검색어면 모두 맞음.
bool planNameMatches(String title, String query) => planNameKey(title).contains(planNameKey(query));

/// F-044 맞는 항목만 남긴 통계 — 합계(`total`)도 남은 항목으로 다시 센다. 기간·날 수는 그대로.
PlanStats filterStats(PlanStats st, String query) => PlanStats(st.from, st.to, st.days,
    [for (final s in st.current) if (planNameMatches(s.item.title, query)) s],
    [for (final s in st.removed) if (planNameMatches(s.item.title, query)) s]);

/// F-043 달별 비율 추이 — 오늘 기준 최근 [maxTrendMonths]달(첫 목록 달보다 앞선 달은 없음). 넘으면 화면이 전체 달 수를 함께 적는다.
const maxTrendMonths = 3;

class PlanTrend {
  PlanTrend(this.months, this.totalMonths, this.rates);

  /// 보이는 달(그 달 1일), 오래된 달부터.
  final List<DateTime> months;

  /// 첫 목록 달부터 이번 달까지 달 수 — [months]보다 많으면 화면이 "전체 N달 중 최근 M달"을 적는다.
  final int totalMonths;

  /// 항목 id → 달마다 비율(해야 한 날 0이면 null), [months]와 같은 순서.
  final Map<String, List<double?>> rates;

  /// 이번 달 − 지난달(%p, 화면에 보이는 반올림 % 끼리 뺀다). 달이 둘 미만이거나 한쪽이 null이면 null.
  int? delta(String id) {
    final r = rates[id];
    if (r == null || r.length < 2 || r[r.length - 1] == null || r[r.length - 2] == null) return null;
    return ratePct(r.last!) - ratePct(r[r.length - 2]!);
  }
}

PlanTrend planTrend(PlanStore store, DateTime today) {
  final first = store.firstDay;
  if (first == null) return PlanTrend(const [], 0, const {});
  final thisMonth = DateTime(today.year, today.month);
  final firstMonth = DateTime(first.year, first.month);
  final total = (thisMonth.year - firstMonth.year) * 12 + thisMonth.month - firstMonth.month + 1;
  final shown = total < maxTrendMonths ? total : maxTrendMonths;
  final months = [for (var k = shown - 1; k >= 0; k--) DateTime(thisMonth.year, thisMonth.month - k)];
  final rates = <String, List<double?>>{};
  for (var m = 0; m < months.length; m++) {
    final st = planStats(store, months[m], DateTime(months[m].year, months[m].month + 1, 0), today);
    for (final s in [...st.current, ...st.removed]) {
      (rates[s.item.id] ??= List<double?>.filled(months.length, null))[m] = s.rate;
    }
  }
  return PlanTrend(months, total, rates);
}

/// F-037 기간 빠른 선택.
enum PlanPeriod {
  week('이번 주'),
  month('이번 달'),
  lastMonth('지난 달'),
  days30('최근 $recentDays일');

  const PlanPeriod(this.label);
  final String label;
}

/// F-037 '최근 N일' 빠른 선택의 날 수(오늘 포함).
const recentDays = 30;

/// 빠른 선택의 (시작, 끝). 이번 주는 일요일 시작(달력과 같음). 끝이 오늘 뒤일 수 있는 건 없다.
(DateTime, DateTime) periodRange(PlanPeriod p, DateTime today) {
  final t = _day(today);
  return switch (p) {
    PlanPeriod.week => (DateTime(t.year, t.month, t.day - t.weekday % 7), t),
    PlanPeriod.month => (DateTime(t.year, t.month), t),
    PlanPeriod.lastMonth => (DateTime(t.year, t.month - 1), DateTime(t.year, t.month, 0)),
    PlanPeriod.days30 => (DateTime(t.year, t.month, t.day - (recentDays - 1)), t),
  };
}
