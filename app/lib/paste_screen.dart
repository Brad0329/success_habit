/// F-003 붙여넣기 화면 — 모양은 기존판과 같다(REQUIREMENTS '화면 방향').
///
/// 창이 포커스를 얻으면 클립보드 텍스트를 입력칸에 채운다. 한 번 채운 클립보드는 다시 자동으로 채우지 않는다
/// (보낸 것은 두 번 보내기 방지, 안 보내고 지운 것은 켤 때마다 다시 뜨지 않게).
/// '보내기'는 폰에 바로 저장한다(F-035) — 업로드·재전송이 없다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_menu.dart';
import 'atomic_file.dart';
import 'change_signal.dart';
import 'log.dart';
import 'phone_store.dart';
import 'platform.dart';
import 'record.dart' as record;
import 'sender.dart';
import 'voice.dart' as voice;

enum StatusKind { info, ok, fail }

class Status {
  const Status(this.kind, this.text, {this.settings = false});
  final StatusKind kind;
  final String text;
  final bool settings; // '설정' 버튼(앱 권한 화면)을 붙인다 — 마이크 권한 거부(F-007)
}

class PasteScreen extends StatefulWidget {
  const PasteScreen({
    super.key,
    required this.store,
    required this.device,
    this.now = DateTime.now,
    this.changed,
    this.sentClipFile,
    this.recorder,
    this.voiceLimit = voice.voiceLimit,
    this.onOpenPlan,
    this.planFirst = false,
  });

  /// F-016 계획 화면 — [planFirst]일 때 켜자마자 연다. 화면 이동 입구는 ⋯ 메뉴(F-017, `app_menu.dart`).
  final void Function(BuildContext)? onOpenPlan;

  /// 앱을 켜면 계획 화면을 이 화면 위에 바로 연다(첫 화면 = 계획 달력).
  /// 이 화면은 밑에 남는다 — 클립보드 채우기·녹음이 여기 있어서(뒤로 가기 = 붙여넣기 화면).
  final bool planFirst;

  final PhoneStore store;

  /// F-029 저장하면 신호를 쓴다 — 녹음이 상한·앱 벗어남으로 저장될 때 목록이 위에 열려 있을 수 있다.
  final ChangeSignal? changed;
  final Device device;
  final DateTime Function() now;
  /// 마지막으로 칸에 채운 클립보드의 MD5 — 앱을 다시 켜도 같은 클립보드를 또 채우지 않게(내용은 남기지 않는다).
  /// 파일 이름 `sent_clip.md5`는 기존판에서 물려받았다(뜻은 '보낸 것'이 아니라 '채운 것').
  final File? sentClipFile;

  /// 앱 안 녹음(F-007). null이면 마이크 버튼을 그리지 않는다.
  final voice.Recorder? recorder;
  final Duration voiceLimit;

  @override
  State<PasteScreen> createState() => PasteScreenState();
}

class PasteScreenState extends State<PasteScreen> with WidgetsBindingObserver {
  final text = TextEditingController();
  StreamSubscription<void>? _focusSub;
  String? _lastClip; // 마지막으로 칸에 채운 클립보드 내용
  Status? status;
  bool notificationsOff = false;
  bool busy = false;
  bool recording = false;
  Duration elapsed = Duration.zero;
  DateTime? _recStart;
  String? _recPath;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusSub = widget.device.windowFocus.listen((_) => onFocus());
    final openPlan = widget.onOpenPlan;
    if (widget.planFirst && openPlan != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openPlan(context);
      });
    }
    unawaited(_start());
  }

  Future<void> _start() async {
    await _guard('알림 권한 요청', widget.device.requestNotificationPermission);
    // 첫 포커스 알림이 화면이 듣기 전에 지나갔을 수 있다 — 지금 포커스가 있으면 직접 한 번 읽는다.
    if (await widget.device.hasWindowFocus()) await onFocus();
  }

  @override
  void dispose() {
    // dispose 중에는 mounted가 아직 true라 setState가 예외를 낸다 — 녹음 멈추기·상태 표시가 이 표시를 본다.
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (recording) unawaited(stopVoice()); // 화면이 사라져도 녹음한 것은 남긴다
    _tick?.cancel();
    _focusSub?.cancel();
    text.dispose();
    super.dispose();
  }

  void _set(Status? s) {
    if (_live) setState(() => status = s);
  }

  bool _disposed = false;
  bool get _live => mounted && !_disposed;

  Future<void> _guard(String what, Future<void> Function() f) async {
    try {
      await f();
    } on Object catch (e, st) {
      logError('$what 실패', e, st);
    }
  }

  /// 창이 포커스를 얻었다 — 클립보드 채우기 + 알림 권한 다시 확인(설정에서 돌아왔을 수 있다).
  Future<void> onFocus() async {
    await _guard('알림 권한 확인', () async {
      final on = await widget.device.notificationsEnabled();
      if (mounted) setState(() => notificationsOff = !on);
    });
    await _guard('클립보드 읽기', () => fillFromClipboard(force: false));
  }

  Future<void> fillFromClipboard({required bool force}) async {
    final clip = await widget.device.readClipboard();
    if (clip == null || clip.isEmpty) return;
    if (!force && (clip == _lastClip || _wasFilled(clip))) return;
    _lastClip = clip;
    _remember(clip); // 한 번 채운 클립보드는 보내든 안 보내든 다시 자동으로 채우지 않는다(2026-11-02)
    text.text = clip;
    _set(const Status(StatusKind.info, '클립보드에서 채움'));
  }

  /// 칸을 비우고 폰 클립보드도 지운다(2026-11-09 사용자 — 클립보드에서 들어간 것이 계속 보일 때).
  /// 클립보드 지우기가 실패해도 칸은 비우고, 상태 줄에 클립보드는 못 지웠다고 적는다.
  Future<void> clearAll() async {
    try {
      await widget.device.clearClipboard();
    } on Object catch (e, st) {
      logError('클립보드 지우기 실패', e, st);
      text.clear();
      _set(const Status(StatusKind.fail, '칸은 비웠지만 클립보드는 지우지 못했습니다'));
      return;
    }
    _lastClip = null;
    text.clear();
    _set(const Status(StatusKind.info, '칸과 클립보드를 비움'));
  }

  static String _md5Of(String s) => record.md5Hex(Uint8List.fromList(utf8.encode(s)));

  /// 이 클립보드를 이미 자동으로 채웠는가(앱을 다시 켜도 남는 기억). 못 읽으면 아닌 것으로 본다 — 채워져 보일 뿐 저장은 안 된다.
  bool _wasFilled(String clip) {
    final f = widget.sentClipFile;
    if (f == null || !f.existsSync()) return false;
    try {
      return f.readAsStringSync().trim() == _md5Of(clip);
    } on FileSystemException catch (e) {
      logWarn('보낸 클립보드 기억을 못 읽음(다시 채울 수 있음): $e');
      return false;
    }
  }

  /// 칸에 채운 클립보드를 기억한다 — 보내든, 안 보내고 지우든 앱을 다시 켜도 또 채우지 않는다
  /// (2026-11-02 실기기: 안 보내려고 지운 것이 켤 때마다 다시 떴다. 다시 넣으려면 '클립보드에서 다시 채우기' 버튼).
  void _remember(String clip) {
    final f = widget.sentClipFile;
    if (f == null) return;
    try {
      writeAtomicSync(f, _md5Of(clip));
    } on FileSystemException catch (e) {
      // 채우기는 이미 됐다 — 기억 실패는 다음에 다시 채워 보이는 정도라 막지 않는다.
      logWarn('채운 클립보드 기억 쓰기 실패: $e');
    }
  }

  Future<void> send() async {
    if (busy) return;
    final body = text.text;
    final (NewRecord, Uint8List) prepared;
    try {
      prepared = preparePaste(body);
    } on record.EmptyTextError {
      // 오류가 아니라 정해진 흐름(빈 텍스트는 보내지 않고 알린다) — 화면에 보인다
      _set(const Status(StatusKind.info, '빈 칸은 보내지 않습니다'));
      return;
    }
    final (item, data) = prepared;
    setState(() => busy = true);
    try {
      widget.store.save(item, data);
      logInfo('수집: ${item.id} ${item.sidecar['kind']} input=paste');
      widget.changed?.mark(widget.now());
      text.clear();
      _set(Status(StatusKind.ok, '저장됨 · ${_hhmm(widget.now())}'));
    } on SaveFailed catch (e) {
      // 원인은 PhoneStore.save가 로그에 남겼다. 칸의 내용은 그대로 둔다 — 다시 '보내기'를 누르면 된다.
      _set(Status(StatusKind.fail, '${e.userMessage} — 칸의 내용은 그대로 있습니다'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---- F-007 앱 안 녹음 ------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 화면을 끄거나 다른 앱으로 가면 멈추고 저장(2026-10-30 사용자 결정 — 포그라운드 서비스 없음).
    // inactive(알림창 내리기 등)에서는 멈추지 않는다.
    if (recording && (state == AppLifecycleState.hidden || state == AppLifecycleState.paused)) {
      logInfo('녹음 중 앱을 벗어남 — 여기까지 저장');
      unawaited(stopVoice());
    }
  }

  Future<void> startVoice() async {
    final rec = widget.recorder;
    if (rec == null || busy || recording) return;
    try {
      if (!await rec.hasPermission()) {
        logWarn('마이크 권한 거부 — 녹음 안 함');
        _set(const Status(StatusKind.fail, '마이크 권한이 꺼져 있어 녹음할 수 없습니다', settings: true));
        return;
      }
      final dir = Directory('${await widget.device.filesDir()}/voice_tmp')..createSync(recursive: true);
      final path = '${dir.path}/${record.newId()}.m4a';
      await rec.start(path);
      _recPath = path;
      _recStart = widget.now();
      if (!mounted) return;
      setState(() {
        recording = true;
        elapsed = Duration.zero;
        status = null;
      });
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
      logInfo('녹음 시작');
    } on Object catch (e, st) {
      logError('녹음 시작 실패', e, st);
      _set(const Status(StatusKind.fail, '녹음을 시작하지 못했습니다'));
    }
  }

  void _onTick() {
    if (!recording || _recStart == null) return;
    final e = widget.now().difference(_recStart!);
    if (_live) setState(() => elapsed = e);
    if (e >= widget.voiceLimit) {
      logInfo('녹음 상한(${widget.voiceLimit.inMinutes}분) 도달 — 자동으로 멈추고 저장');
      unawaited(stopVoice());
    }
  }

  /// 멈추고 폰에 저장한다 — 앱을 벗어나 멈춘 것도 같은 길(업로드가 없어 화면 뒤에서도 저장이 끝난다).
  Future<void> stopVoice() async {
    if (!recording) return;
    recording = false;
    _tick?.cancel();
    final took = widget.now().difference(_recStart!);
    if (_live) setState(() {});
    if (await _saveVoice(took)) {
      _set(Status(StatusKind.ok, '저장됨 · 녹음 ${_mmss(took)} · ${_hhmm(widget.now())}'));
    }
  }

  /// 녹음 파일 → 수집물. 저장했으면 true. 너무 짧거나 실패하면 화면에 알리고 false.
  Future<bool> _saveVoice(Duration took) async {
    String? path;
    try {
      path = await widget.recorder!.stop() ?? _recPath;
    } on Object catch (e, st) {
      logError('녹음 멈추기 실패', e, st);
      path = _recPath;
    }
    final file = path == null ? null : File(path);
    try {
      if (file == null || !file.existsSync() || file.lengthSync() == 0) {
        logWarn('녹음 파일이 없거나 비어 있음: $path (${took.inMilliseconds}ms)');
        if (file != null && file.existsSync()) file.deleteSync(); // 0바이트 임시 파일은 남길 것이 없다
        _set(Status(StatusKind.fail, took < voice.voiceMinimum ? '너무 짧아 저장하지 않음' : '녹음 파일을 만들지 못했습니다'));
        return false;
      }
      if (took < voice.voiceMinimum) {
        file.deleteSync();
        logInfo('너무 짧은 녹음(${took.inMilliseconds}ms) — 저장 안 함');
        _set(const Status(StatusKind.info, '너무 짧아 저장하지 않음'));
        return false;
      }
      final (item, data) = prepareVoice(file.readAsBytesSync(), voice.voiceMime);
      widget.store.save(item, data);
      file.deleteSync(); // 수집물 나무에 들어갔다 — 녹음 임시 파일은 필요 없다
      logInfo('수집: ${item.id} voice ${took.inSeconds}초 ${data.length}B');
      widget.changed?.mark(widget.now());
      return true;
    } on Object catch (e, st) {
      logError('녹음 저장 실패(녹음 임시 파일은 남겨 둠: $path)', e, st);
      _set(const Status(StatusKind.fail, '녹음을 저장하지 못했습니다'));
      return false;
    }
  }

  static String _mmss(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  static String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notificationsOff) _NotifBanner(onTap: widget.device.openNotificationSettings),
              Row(children: [
                Text('채록', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: '비우기(칸·클립보드)',
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: busy || recording ? null : () => _guard('비우기', clearAll),
                ),
                IconButton(
                  tooltip: '클립보드에서 다시 채우기',
                  icon: const Icon(Icons.content_paste),
                  onPressed: () => _guard('클립보드 읽기', () => fillFromClipboard(force: true)),
                ),
                const AppMenu(current: AppMenuItem.paste),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: recording
                    ? _RecordingBox(elapsed: elapsed, limit: widget.voiceLimit)
                    : TextField(
                        controller: text,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          hintText: '보낼 내용을 붙여넣거나 입력',
                          border: OutlineInputBorder(),
                        ),
                      ),
              ),
              if (recording)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('앱을 벗어나면 여기까지 저장',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              if (status != null && !recording)
                _StatusLine(status!,
                    onSettings: () => _guard('앱 설정 열기', () async => widget.device.openAppSettings?.call())),
              const SizedBox(height: 12),
              SizedBox(height: 52, child: recording ? _stopButton(context) : _sendRow()),
            ],
          ),
        ),
      ),
    );
  }
}

extension on PasteScreenState {
  Widget _sendRow() => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.recorder != null) ...[
          OutlinedButton(
            onPressed: busy ? null : startVoice,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(56, 52)),
            child: const Icon(Icons.mic_none, semanticLabel: '녹음'),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: FilledButton.icon(
            onPressed: busy ? null : send,
            icon: const Icon(Icons.send),
            label: const Text('보내기'),
          ),
        ),
      ]);

  Widget _stopButton(BuildContext context) => FilledButton.icon(
        onPressed: stopVoice,
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA32D2D), foregroundColor: Colors.white),
        icon: const Icon(Icons.stop),
        label: const Text('완료 · 저장'),
      );
}

class _RecordingBox extends StatelessWidget {
  const _RecordingBox({required this.elapsed, required this.limit});
  final Duration elapsed;
  final Duration limit;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF501313) : const Color(0xFFFCEBEB);
    final fg = dark ? const Color(0xFFF7C1C1) : const Color(0xFFA32D2D);
    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 14, height: 14, decoration: const BoxDecoration(color: Color(0xFFE24B4A), shape: BoxShape.circle)),
        const SizedBox(height: 8),
        Text(PasteScreenState._mmss(elapsed), style: TextStyle(fontSize: 40, fontWeight: FontWeight.w500, color: fg)),
        const SizedBox(height: 4),
        Text('녹음 중 · 최대 ${PasteScreenState._mmss(limit)}', style: TextStyle(color: fg)),
      ]),
    );
  }
}

class _NotifBanner extends StatelessWidget {
  const _NotifBanner({required this.onTap});
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: dark ? const Color(0xFF633806) : const Color(0xFFFAEEDA),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTap().catchError((Object e) => logError('알림 설정 열기 실패', e)),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Icon(Icons.notifications_off_outlined, size: 18,
                  color: dark ? const Color(0xFFFAC775) : const Color(0xFF633806)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('알림이 꺼져 있어 공유 결과를 못 봅니다 · 설정',
                    style: TextStyle(color: dark ? const Color(0xFFFAC775) : const Color(0xFF633806))),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(this.status, {required this.onSettings});
  final Status status;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (Color bg, Color fg, IconData icon) = switch (status.kind) {
      StatusKind.ok => dark
          ? (const Color(0xFF27500A), const Color(0xFFC0DD97), Icons.check)
          : (const Color(0xFFEAF3DE), const Color(0xFF27500A), Icons.check),
      StatusKind.fail => (scheme.errorContainer, scheme.onErrorContainer, Icons.error_outline),
      StatusKind.info => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, Icons.info_outline),
    };
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(icon, size: 18, color: fg),
        const SizedBox(width: 8),
        Expanded(child: Text(status.text, style: TextStyle(color: fg))),
        if (status.settings)
          TextButton(
            onPressed: onSettings,
            style: TextButton.styleFrom(foregroundColor: fg),
            child: const Text('설정'),
          ),
      ]),
    );
  }
}
