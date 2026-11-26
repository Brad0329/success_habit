/// F-101 도움말 — 이 앱이 지향하는 것(Atomic Habits) + 사용법. 문구는 2026-11-26 사용자 "이대로 진행".
/// 맨 끝에 제작자 한 줄과 버전. 저장 없음.
library;

import 'package:flutter/material.dart';

import 'app_menu.dart';
import 'app_version.dart';

const helpCredit = '이 앱은 Brad 2.0 이 제작했습니다.';

/// (제목, 문단들). 문단이 '• '로 시작하면 글머리 줄.
const helpSections = <(String, List<String>)>[
  ('이 앱이 지향하는 것', [
    "성공습관은 제임스 클리어의 『아주 작은 습관의 힘(Atomic Habits)』이 말하는 정신을 따릅니다.",
    '• 목표보다 시스템 — 큰 결심보다 매일 반복하는 작은 행동이 결과를 만듭니다. 이 앱은 그 작은 행동을 하루하루 체크하는 도구입니다.',
    '• 1%씩 나아지기 — 오늘 하루의 차이는 작아 보여도 쌓이면 큽니다. 통계의 달별 추이로 지난달보다 나아졌는지 볼 수 있습니다.',
    '• 정체성이 먼저 — "운동을 한다"보다 "나는 운동하는 사람이다"가 오래갑니다. 체크 하나하나가 되고 싶은 나에게 던지는 한 표입니다.',
    '• 두 번 연속 빠지지 않기 — 한 번 놓치는 건 누구나 겪는 일이지만, 두 번 연속이면 새 습관의 시작이 됩니다. 앱이 직전에 놓친 계획을 오늘 눈에 띄게 보여 줍니다.',
    '• 완벽보다 꾸준함 — 못 하는 날은 보류하면 됩니다. 기록을 끊지 않는 것이 더 중요합니다.',
  ]),
  ('1. 계획 만들기', [
    '• ⋯ 메뉴 → 설정 → 평일 계획에서 매일 할 일을 넣습니다.',
    "• DO는 할 일(운동, 독서), DON'T는 하지 않을 일(야식, 늦잠)입니다.",
    '• 작게 시작하세요. "운동 1시간"보다 "팔굽혀펴기 5개"가 오래갑니다.',
    '• 바꾼 계획은 오늘부터 적용되고, 지난 날의 기록은 그대로 남습니다.',
    '• 줄을 길게 눌러 끌면 순서를 바꿀 수 있습니다. 계획은 최대 30개, 이름은 40자까지입니다.',
  ]),
  ('2. 매일 체크하기', [
    '• 앱을 켜면 달력이 나오고, 날짜를 누르면 그날 계획 목록이 아래에 뜹니다.',
    '• DO는 했으면 누릅니다.',
    "• DON'T는 아침부터 모두 '지킴'으로 체크되어 있습니다. 어겼을 때만 눌러 체크를 풉니다.",
    '• 오늘과 지난 날만 체크할 수 있고, 미래는 보기만 합니다.',
    "• 달력 칸의 위쪽 파란색은 DO, 아래쪽 빨간색은 DON'T입니다. 파란색은 많이 할수록 진해지고, 빨간색은 잘 지킬수록 옅어집니다.",
  ]),
  ('3. 못 하는 날은 보류', [
    '• 그날 할 수 없는 계획(출장, 아플 때)은 목록에서 길게 누르면 보류됩니다.',
    '• 보류한 계획은 그날 개수에서 빠지고, 연속 기록도 끊기지 않습니다. 다시 길게 누르면 풀립니다.',
  ]),
  ('4. 평일과 주말·휴일', [
    '• 설정 → 주말·휴일 계획에서 토·일에 할 계획을 따로 정합니다.',
    '• 주말에는 평일 DO가 보류로 보입니다. 그날 하고 싶으면 길게 눌러 풉니다.',
    "• 평일 DON'T는 주말에도 그대로 지킵니다.",
    '• 평일에 쉬는 날(휴가, 공휴일)은 계획 화면의 휴일로 지정을 누르면 그날 주말 계획으로 바뀝니다. 달력에서는 날짜가 빨갛게 보입니다.',
  ]),
  ('5. 나는 이런 사람 (선택)', [
    '• 설정 → 나는 이런 사람에 되고 싶은 모습을 최대 3개까지 적습니다(예: "나는 매일 읽는 사람이다").',
    '• 적은 문장은 달력 위에 매일 보입니다. 안 써도 됩니다.',
  ]),
  ('6. 🔥 연속과 놓침 표시', [
    '• 오늘 목록에서 이어 온 날 수가 🔥 N일로 보입니다. 보류한 날과 쉬는 날은 연속을 끊지 않습니다.',
    '• 직전에 놓친 계획에는 "어제 놓침 — 오늘은 꼭", 여러 번 이어 놓쳤으면 "N회 연속 놓침"이 붙습니다.',
    '• 두 번 연속 놓친 날은 달력 칸에 작은 점이 찍힙니다.',
  ]),
  ('7. 하루 평가와 통계', [
    '• 날짜 목록 맨 아래 하루 평가하기에 하루를 짧게 정리합니다. 저장은 자동입니다. 평가를 쓴 날을 누르면 달력 위에 말풍선으로 보입니다.',
    '• 계획 화면 위의 통계 아이콘으로 기간별 성공 수와 비율을 봅니다.',
    "• 아래 '연속 · 달별 추이' 묶음에서 최장 연속과 지난달 대비 ▲▼을 봅니다.",
    '• 검색창에 이름을 넣으면 그 계획만 볼 수 있습니다.',
    '• 제목 옆 물음표를 누르면 세는 규칙이 나옵니다.',
  ]),
  ('8. 홈 화면 위젯 (선택)', [
    '• 홈 화면 빈 곳을 길게 누르고 위젯 → 성공습관을 골라 추가합니다.',
    '• 모서리를 끌어 크기를 바꾸면 모양이 바뀝니다. 작게 하면 오늘 숫자만, 크게 하면 진행 막대와 🔥 연속이 보입니다.',
    '• 위젯은 보기만 합니다. 누르면 앱이 열리고, 체크는 앱에서 합니다.',
    '• 자정이 지나고 앱을 아직 안 열었으면 "새 하루예요"와 어제 결과가 보입니다.',
    '• 위젯을 지워도 계획은 그대로입니다.',
  ]),
  ('꼭 알아 두세요', [
    '• 모든 기록은 이 폰 안에만 저장됩니다. 인터넷, 로그인, 백업이 없습니다.',
    '• 앱을 지우거나 폰을 바꾸면 계획과 기록이 사라집니다.',
  ]),
];

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    return Scaffold(
      appBar: AppBar(
        title: const Text('도움말'),
        actions: const [AppMenu(current: AppMenuItem.help)],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        for (final (title, paras) in helpSections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 6),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          for (final p in paras) _para(theme, p),
        ],
        const SizedBox(height: 28),
        Text(helpCredit, key: const ValueKey('help-credit'), textAlign: TextAlign.center, style: small),
        const SizedBox(height: 2),
        Text(versionLabel(appVersion), key: const ValueKey('help-version'), textAlign: TextAlign.center, style: small),
      ]),
    );
  }

  static Widget _para(ThemeData theme, String p) {
    final body = theme.textTheme.bodyMedium;
    if (!p.startsWith('• ')) {
      return Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(p, style: body));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('•  ', style: body),
        Expanded(child: Text(p.substring(2), style: body)),
      ]),
    );
  }
}
