import 'package:flutter/material.dart';

import 'log.dart';

/// 채록 화면 공통 모양 — 2026-11-17 사용자 시안 B '세이지 라운드': 세이지 초록 강조, 큰 둥근 모서리,
/// 알약 모양 버튼·칩·검색, 테두리 대신 옅은 그림자, 글꼴 Gothic A1(app/assets/fonts, OFL).
/// 다크모드는 시스템 설정을 따른다(REQUIREMENTS '화면 방향').
ThemeData chaerokTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final cs = dark ? _darkScheme : _lightScheme;
  const pill = StadiumBorder();
  const fieldRadius = BorderRadius.all(Radius.circular(20));
  OutlineInputBorder field(Color c, [double w = 0]) => OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
      );
  return ThemeData(
    colorScheme: cs,
    fontFamily: 'GothicA1',
    scaffoldBackgroundColor: cs.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontFamily: 'GothicA1', fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface),
    ),
    cardTheme: CardThemeData(
      color: cs.surfaceContainerLow,
      elevation: 1,
      shadowColor: _shadow(dark),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(22))),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: pill, elevation: 2, shadowColor: cs.primary)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: pill, side: BorderSide(color: cs.outlineVariant, width: 1.5))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: pill)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(shape: pill)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant)),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide.none,
      backgroundColor: cs.surfaceContainerHighest,
      selectedColor: cs.primary,
      showCheckmark: false,
      labelStyle: TextStyle(fontFamily: 'GothicA1', color: cs.onSurface),
      secondaryLabelStyle: TextStyle(fontFamily: 'GothicA1', color: cs.onPrimary),
    ),
    // 화면마다 `border: OutlineInputBorder()`를 적어 둔 칸이 있어 상태별 테두리(enabled·focused…)까지 여기서 정한다
    // — 상태별 값이 있으면 그것이 이긴다.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerLow,
      border: field(cs.outlineVariant),
      enabledBorder: field(cs.outlineVariant),
      disabledBorder: field(cs.outlineVariant),
      focusedBorder: field(cs.primary, 1.5),
      errorBorder: field(cs.error, 1.2),
      focusedErrorBorder: field(cs.error, 1.5),
    ),
    checkboxTheme: CheckboxThemeData(shape: const CircleBorder(), side: BorderSide(color: cs.outline, width: 1.6)),
    popupMenuTheme: PopupMenuThemeData(
      color: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: cs.surfaceContainerLow, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    dividerTheme: DividerThemeData(color: cs.outlineVariant),
  );
}

/// 카드·목록 줄 그림자 — 세이지 기운이 도는 옅은 그림자(다크는 검정).
Color _shadow(bool dark) => dark ? const Color(0x66000000) : const Color(0x33284637);

final _lightScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2E6A55)).copyWith(
  primary: const Color(0xFF2E6A55),
  onPrimary: Colors.white,
  primaryContainer: const Color(0xFFDCEBE3),
  onPrimaryContainer: const Color(0xFF10382A),
  surface: const Color(0xFFEEF1EC),
  onSurface: const Color(0xFF1C2520),
  onSurfaceVariant: const Color(0xFF68756D),
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: const Color(0xFFFBFCFA),
  surfaceContainer: const Color(0xFFF4F7F2),
  surfaceContainerHigh: const Color(0xFFE9EEE7),
  surfaceContainerHighest: const Color(0xFFE3E9E1),
  outline: const Color(0xFF8A968E),
  outlineVariant: const Color(0xFFD5DDD3),
  error: const Color(0xFFC0433A),
);

final _darkScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2E6A55), brightness: Brightness.dark).copyWith(
  primary: const Color(0xFF8FCBB0),
  onPrimary: const Color(0xFF0E2A20),
  primaryContainer: const Color(0xFF23493B),
  onPrimaryContainer: const Color(0xFFCDEBDD),
  surface: const Color(0xFF121815),
  onSurface: const Color(0xFFE3E9E4),
  onSurfaceVariant: const Color(0xFFA3B0A8),
  surfaceContainerLowest: const Color(0xFF0D120F),
  surfaceContainerLow: const Color(0xFF1A211D),
  surfaceContainer: const Color(0xFF1E2621),
  surfaceContainerHigh: const Color(0xFF252E29),
  surfaceContainerHighest: const Color(0xFF2C3630),
  outline: const Color(0xFF7C887F),
  outlineVariant: const Color(0xFF34403A),
  error: const Color(0xFFF2867E),
);

/// MaterialApp `builder:` — 글자 크기 계산 고장을 우회한다(메인 화면·메모 공유 창 둘 다).
///
/// 원인(2026-11-03 실측): 안드로이드 엔진의 설정 대기열(SettingsChannel.CONFIGURATION_QUEUE)이 static이라
/// 같은 프로세스에 공유 화면 엔진이 뜨면 메인 엔진의 설정이 지워진다. 그 뒤 디버그 빌드는 글자 크기 계산마다
/// AssertionError를 던져 새 글자(대화 화면 등)가 통째로 안 그려진다. 릴리스 빌드는 같은 자리에서 단순 배율로
/// 넘어간다 — 여기서 그 동작을 디버그에도 똑같이 한다. 평소(고장이 없을 때)는 시스템 계산 그대로다.
Widget guardTextScale(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  final factor = View.of(context).platformDispatcher.textScaleFactor;
  return MediaQuery(
    data: mq.copyWith(textScaler: _GuardedTextScaler(mq.textScaler, factor)),
    child: child ?? const SizedBox.shrink(),
  );
}

var _loggedFallback = false;

class _GuardedTextScaler extends TextScaler {
  const _GuardedTextScaler(this._inner, this._factor);

  final TextScaler _inner;
  final double _factor;

  @override
  double scale(double fontSize) {
    try {
      return _inner.scale(fontSize);
    } on AssertionError catch (e, st) {
      // 글자마다 불리므로 첫 한 번만 남긴다(이후 같은 원인은 생략). 앱을 껐다 켜면 새 설정을 받아 풀린다.
      if (!_loggedFallback) {
        _loggedFallback = true;
        logError('글자 크기 계산 실패 — 단순 배율 x$_factor로 대신 그림(이후 같은 오류는 기록 생략)', e, st);
      }
      return fontSize * _factor;
    }
  }

  @override
  // ignore: deprecated_member_use — TextScaler를 구현하려면 이 멤버를 채워야 한다
  double get textScaleFactor => _factor;

  @override
  bool operator ==(Object other) =>
      other is _GuardedTextScaler && other._inner == _inner && other._factor == _factor;

  @override
  int get hashCode => Object.hash(_inner, _factor);
}
