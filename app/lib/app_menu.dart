/// 화면 이동 입구를 **한자리에** 모은 `⋯` 메뉴(F-017).
///
/// 어느 화면에서든 앱바 오른쪽 끝 같은 자리에서 연다 — 같은 입구를 두 자리에 두면 한쪽만 고쳐진다.
///
/// 메뉴로 연 화면은 **지금 화면 위에 쌓는다** — 뒤로를 누르면 지나온 화면을 차례로 되밟는다.
/// 단 '붙여넣기'는 맨 밑 화면이라 위를 걷어내고 내려간다(같은 화면을 둘 만들면 클립보드 채우기를 둘이 받는다).
library;

import 'package:flutter/material.dart';

/// 메뉴 항목. **순서가 곧 메뉴 순서다**(계획이 맨 위, 설정은 맨 아래).
/// 화면이 아직 없는 항목(대화·외울 문장 — Phase 006·007)은 입구가 null이라 메뉴에 안 나온다.
enum AppMenuItem {
  plan('계획', Icons.event_available),
  paste('붙여넣기', Icons.edit_note),
  list('목록', Icons.manage_search),
  chat('대화', Icons.chat_bubble_outline),
  memorize('외울 문장', Icons.bookmark_border),
  settings('설정', Icons.settings_outlined);

  const AppMenuItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// 화면 여는 법을 앱 전체에 내려 준다 — `MaterialApp.builder`에 두어 모든 화면(쌓인 것 포함)의 조상이 된다.
/// 화면마다 의존성을 생성자로 넘기지 않으려고 이렇게 둔다. null인 입구는 메뉴에 안 나온다.
class AppNav extends InheritedWidget {
  const AppNav({
    super.key,
    required super.child,
    this.openPlan,
    this.openList,
    this.openChat,
    this.openMemorize,
    this.openSettings,
  });

  final void Function(BuildContext)? openPlan;
  final void Function(BuildContext)? openList;
  final void Function(BuildContext)? openChat;
  final void Function(BuildContext)? openMemorize;
  final void Function(BuildContext)? openSettings;

  static AppNav? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppNav>();

  /// **★ `switch`에 `default`/`_`를 넣지 말 것** — 항목을 더했을 때 여기를 빠뜨리면 컴파일러가 잡는다
  /// (메뉴에 항목이 늘어도 화면이 안 열리는 것은 조용한 무반응이라 눈에 안 띈다).
  void Function(BuildContext)? opener(AppMenuItem item) => switch (item) {
        AppMenuItem.plan => openPlan,
        AppMenuItem.paste => (c) => Navigator.of(c).popUntil((r) => r.isFirst),
        AppMenuItem.list => openList,
        AppMenuItem.chat => openChat,
        AppMenuItem.memorize => openMemorize,
        AppMenuItem.settings => openSettings,
      };

  @override
  bool updateShouldNotify(AppNav old) =>
      openPlan != old.openPlan ||
      openList != old.openList ||
      openChat != old.openChat ||
      openMemorize != old.openMemorize ||
      openSettings != old.openSettings;
}

/// 앱바 끝에 붙이는 `⋯`. [current]는 지금 보고 있는 화면이고 그 항목은 잠긴다(어디 있는지 보인다).
/// 위로 쌓인 상세 화면처럼 메뉴 항목이 아닌 화면은 null.
class AppMenu extends StatelessWidget {
  const AppMenu({super.key, this.current});

  final AppMenuItem? current;

  @override
  Widget build(BuildContext context) {
    final nav = AppNav.maybeOf(context);
    if (nav == null) return const SizedBox.shrink();
    final items = [for (final i in AppMenuItem.values) if (nav.opener(i) != null) i];
    return PopupMenuButton<AppMenuItem>(
      icon: const Icon(Icons.more_vert),
      tooltip: '메뉴',
      itemBuilder: (_) => [
        for (final item in items)
          PopupMenuItem(
            value: item,
            enabled: item != current,
            child: Row(children: [Icon(item.icon, size: 20), const SizedBox(width: 12), Text(item.label)]),
          ),
      ],
      onSelected: (item) {
        if (item == current) return; // 잠겨 있지만 경로를 하나로 둔다
        nav.opener(item)!(context);
      },
    );
  }
}
