/// 앱 버전 — `pubspec.yaml`의 `version`과 같아야 한다(F-101 도움말 맨 끝에 보인다).
/// 새 의존성(package_info) 없이 상수로 둔다 — pubspec을 올리고 여기를 안 고치면 `help_screen_test`가 실패한다.
library;

const appVersion = '1.0.0+1';

/// "1.0.0+1" → "버전 1.0.0 (1)". 빌드 번호가 없으면 "버전 1.0.0".
String versionLabel(String v) {
  final i = v.indexOf('+');
  return i < 0 ? '버전 $v' : '버전 ${v.substring(0, i)} (${v.substring(i + 1)})';
}
