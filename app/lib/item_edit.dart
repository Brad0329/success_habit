/// 글 한 칸 입력 창. 기존판 item_edit.dart에서 이 창만 먼저 옮겼다 — 제목·핵심 정리 고치기(F-020)는 그 기능의 Phase에서 이 파일에 더한다.
library;

import 'package:flutter/material.dart';

/// 글 한 칸 입력 창 — 계획 이름(F-016)이 쓴다(기존판에서는 제목·핵심 정리·대화 이름도 같이 쓴다).
/// 한 줄이면 엔터로 저장, [maxLength]가 있으면 글자 수 표시·상한. 확인이면 입력 글 그대로, 취소면 null.
/// 입력 칸 컨트롤러는 창이 다 닫힌 뒤(dispose)에 버린다 — 닫히는 동안 쓰면 빨간 화면(`dialog_controller_guard_test`).
class TextInputDialog extends StatefulWidget {
  const TextInputDialog({
    super.key,
    required this.title,
    required this.initial,
    this.multiline = false,
    this.maxLength,
    this.helperText,
    this.okLabel = '저장',
  });
  final String title;
  final String initial;
  final bool multiline;
  final int? maxLength;
  final String? helperText;
  final String okLabel;

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: _c,
            autofocus: true,
            maxLength: widget.maxLength,
            minLines: widget.multiline ? 6 : 1,
            maxLines: widget.multiline ? 14 : 3,
            // 한 줄 칸은 엔터 = 저장(여러 줄은 엔터 = 줄바꿈)
            textInputAction: widget.multiline ? TextInputAction.newline : TextInputAction.done,
            onSubmitted: widget.multiline ? null : (v) => Navigator.of(context).pop(v),
            decoration: InputDecoration(helperText: widget.helperText, border: const OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.of(context).pop(_c.text), child: Text(widget.okLabel)),
        ],
      );
}
