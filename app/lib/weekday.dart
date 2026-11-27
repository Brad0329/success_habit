/// 요일 한 글자 — 표 하나(기존판 D3 2026-11-15: 목록 날짜 머리줄·계획 달력이 순서가 다른 표를 따로 들고 있었다).
library;

/// [DateTime.weekday] 순서(월=1 … 일=7).
const _names = ['월', '화', '수', '목', '금', '토', '일'];

/// "월" … "일".
String weekdayKo(DateTime d) => _names[d.weekday - 1];

/// 달력 머리줄 — 일요일부터.
final calendarHeader = [_names[6], ..._names.take(6)];

/// 일요일 시작 주에서 몇째 날인가(일 0 … 토 6) — [calendarHeader]의 칸과 같다. 달력 첫 줄 빈칸·통계 '이번 주'가 쓴다.
int daysSinceSunday(DateTime d) => d.weekday % 7;

/// "11월 26일 (목)" — 계획 화면의 날짜 머리줄·목록 제목이 쓴다(위젯의 같은 모양 글은 Kotlin `PlanWidget.dayLabel`).
String dayLabelKo(DateTime d) => '${d.month}월 ${d.day}일 (${weekdayKo(d)})';
