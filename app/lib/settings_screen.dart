/// 설정 화면. Phase 004에는 계획 줄 둘(F-016·F-031 '평일 계획'·'주말·휴일 계획')만 있다 —
/// API 키·AI 모델·웹 검색·분류 카테고리 절은 그 기능을 옮기는 Phase에서 기존판과 같은 자리(계획 줄 위·아래)에 붙인다.
library;

import 'package:flutter/material.dart';

import 'app_menu.dart';
import 'plan_settings.dart';
import 'plans.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.plans});

  final PlanStore plans;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        actions: const [AppMenu(current: AppMenuItem.settings)],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [PlanSettingsTile(store: plans)]),
    );
  }
}
