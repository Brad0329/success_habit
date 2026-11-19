/// 요일 한 글자 — 표 하나(기존판 D3 2026-11-15: 목록 날짜 머리줄·계획 달력이 순서가 다른 표를 따로 들고 있었다).
library;

/// [DateTime.weekday] 순서(월=1 … 일=7).
const _names = ['월', '화', '수', '목', '금', '토', '일'];

/// "월" … "일".
String weekdayKo(DateTime d) => _names[d.weekday - 1];
