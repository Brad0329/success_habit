/// F-007 앱 안 녹음 — 녹음기 경계. 실제는 `record` 패키지, 테스트는 같은 모양의 가짜.
///
/// 형식: AAC-LC `.m4a`(`audio/mp4`), 모노 64kbps — 음성 메모용(1분 ≈ 0.5MB, 60분 ≈ 30MB).
library;

import 'package:record/record.dart';

const voiceMime = 'audio/mp4';
const voiceLimit = Duration(minutes: 60); // 닿으면 자동으로 멈추고 저장(2026-10-30 사용자 결정)
const voiceMinimum = Duration(seconds: 1); // 이보다 짧으면 실수로 두 번 누른 것 — 저장하지 않는다

abstract class Recorder {
  /// 마이크 권한. 없으면 묻는다(처음 한 번). 거부돼 있으면 false.
  Future<bool> hasPermission();
  Future<void> start(String path);

  /// 멈추고 녹음 파일 경로를 돌려준다(못 만들었으면 null).
  Future<String?> stop();
}

class DeviceRecorder implements Recorder {
  final _rec = AudioRecorder();

  @override
  Future<bool> hasPermission() => _rec.hasPermission();

  @override
  Future<void> start(String path) => _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1),
        path: path,
      );

  @override
  Future<String?> stop() => _rec.stop();
}
