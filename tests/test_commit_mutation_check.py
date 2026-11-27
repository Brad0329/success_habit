"""커밋 메시지 변이 확인 훅(`.claude/hooks/commit_mutation_check.py`) 검증 — Phase 007 A3.

테스트 파일을 넣거나 고친 커밋인데 메시지에 변이 확인 결과가 없거나(생략), 변이를 한 실행에 묶었으면(묶기 — 2026-11-27
사용자 결정 "허용 안 함") 커밋을 막는다. 예문은 실제로 어긴 커밋(b34de40·3ef0ada / c2927be·f514b88)의 문장이다.

실행: python -m pytest tests/test_commit_mutation_check.py
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / ".claude" / "hooks" / "commit_mutation_check.py"
sys.path.insert(0, str(HOOK.parent))
from commit_mutation_check import add_paths, message_of, problems  # noqa: E402

DART_TEST = ["app/test/plans_test.dart", "app/lib/plans.dart"]
PY_TEST = ["tests/test_session_context.py"]
NO_TEST = ["app/lib/plans.dart", "work_log/plan.md"]

GOOD = "검증:\n- 변이 확인(하나씩): toggleHold 알림을 빼면 notify 테스트 실패 — 되돌림은 diff로 확인\n"


def test_테스트_파일이_없으면_아무것도_안_본다():
    assert problems("문서만 고침", NO_TEST) == []


def test_변이_결과가_있으면_통과():
    assert problems(GOOD, DART_TEST) == []
    assert problems(GOOD, PY_TEST) == []


def test_변이_언급이_없으면_생략이다():
    out = problems("검증: 정적 분석 통과, 전체 테스트 160개 통과.", DART_TEST)
    assert len(out) == 1 and "결과가 없다" in out[0]


def test_하지_않았다고_적으면_이유가_있어도_생략이다():
    # b34de40·3ef0ada — 이유를 붙여 건너뛰었다.
    msg = "검증: 정적 분석 통과. 새 테스트 둘은 변이 확인을 하지 않았다 —\n숨김 조립 테스트는 고치기 전 값과 다르다.\n"
    out = problems(msg, DART_TEST)
    assert any("생략" in p for p in out)


def test_해당_없음_표시는_통과한다():
    msg = "변이 확인 해당 없음: 기존 단언의 기대값만 바꿨다(2/4 → 2/5)\n"
    assert problems(msg, PY_TEST) == []


def test_해당_없음_뒤에_이유가_없으면_막는다():
    assert problems("변이 확인 해당 없음:\n", PY_TEST) != []


def test_한_실행에_묶으면_막는다():
    # f514b88·c2927be의 문장.
    for msg in (
        "변이 확인: 메뉴 순서 뒤집기 + 경로 이름 바꾸기를 한 번에 넣어 전체 실행 → 4개 실패. 둘을 한 실행에 묶었다\n",
        "변이 확인 4건을 각각 다른 파일에 넣어 한 번에 돌렸고, 넷 다 의도한 테스트가 실패했다.\n",
    ):
        out = problems(msg, DART_TEST)
        assert any("묶기" in p for p in out), msg


def test_줄이_바뀌어도_한_문단으로_본다():
    # 6f85f7e(들여쓰기 없이 줄바꿈)·c2927be(들여 쓴 줄바꿈) — '변이'와 '실패'가 다른 줄에 있다.
    plain = "검증: 훅 로직 변경. 변이 확인 1회: 절 이름을\n'보류 항목'으로 바꿔 새 테스트 2개 실패 확인.\n"
    assert problems(plain, PY_TEST) == []
    bullet = "- 변이 확인 4건을\n  각각 다른 파일에 넣어 한 번에 돌렸고 넷 다 실패했다.\n"
    assert any("묶기" in p for p in problems(bullet, DART_TEST))


def test_명사_묶음은_묶기가_아니다():
    # b88e5d7 — 화면 묶음 이름.
    msg = "변이 확인 1건: '연속 · 달별 추이' 묶음을 검색어로 안 거름 → 전체 실행 실패(exit 1)\n"
    assert problems(msg, DART_TEST) == []


def test_한_번에_하나씩은_묶기가_아니다():
    assert problems("변이 확인(한 번에 하나씩): ① 빼면 실패 ② 바꾸면 실패\n", DART_TEST) == []


def test_메시지는_F_파일과_m_인자에서_읽는다(tmp_path):
    (tmp_path / ".commit_msg.txt").write_text("변이 확인: 실패 봄\n", encoding="utf-8")
    assert message_of("git commit -F .commit_msg.txt", tmp_path) == "변이 확인: 실패 봄\n"
    assert message_of("git add a; git commit -F .commit_msg.txt; git push", tmp_path) == "변이 확인: 실패 봄\n"
    assert message_of('git commit -m "변이 확인: 실패"', tmp_path) == "변이 확인: 실패"
    assert message_of("git status", tmp_path) is None
    assert message_of("git commit --amend --no-edit", tmp_path) is None


def test_같은_명령의_git_add_경로도_커밋에_든다():
    # 훅은 git add보다 먼저 돈다 — 같은 명령에서 올릴 파일을 놓치면 안 된다.
    cmd = "git add app/lib/plans.dart tests/test_x.py; git commit -F .commit_msg.txt"
    assert add_paths(cmd) == ["app/lib/plans.dart", "tests/test_x.py"]
    assert add_paths("git commit -F .commit_msg.txt") == []


def test_settings_json에_등록돼_있다():
    hooks = json.loads((ROOT / ".claude" / "settings.json").read_text(encoding="utf-8"))["hooks"]["PreToolUse"]
    commands = [h["command"] for group in hooks for h in group["hooks"]]
    assert any("commit_mutation_check.py" in c for c in commands)


def test_cp949_콘솔에서도_경고가_ASCII로_나가고_커밋은_막지_않는다(tmp_path):
    # 2026-11-27 사용자 결정 "경고만 하게" — permissionDecision을 내지 않아 커밋은 그대로 진행되고,
    # 사용자(systemMessage)와 AI(additionalContext)에게 같은 경고가 간다.
    # 실제 git 저장소에서 테스트 파일을 올리고 변이 결과 없는 메시지로 커밋하려 한다.
    subprocess.run(["git", "init"], cwd=tmp_path, check=True, capture_output=True)
    (tmp_path / "tests").mkdir()
    (tmp_path / "tests" / "test_a.py").write_text("x = 1\n", encoding="utf-8")
    subprocess.run(["git", "add", "tests/test_a.py"], cwd=tmp_path, check=True, capture_output=True)
    (tmp_path / ".commit_msg.txt").write_text("검증: 전체 통과\n", encoding="utf-8")
    env = dict(os.environ, PYTHONIOENCODING="cp949", CLAUDE_PROJECT_DIR=str(tmp_path))
    env.pop("PYTHONUTF8", None)
    p = subprocess.run(
        [sys.executable, str(HOOK)],
        input=json.dumps({"tool_input": {"command": "git commit -F .commit_msg.txt"}}),
        capture_output=True, text=True, encoding="utf-8", env=env,
    )
    assert p.returncode == 0, p.stderr
    assert p.stdout.isascii()
    out = json.loads(p.stdout)
    assert "permissionDecision" not in out["hookSpecificOutput"]
    assert "결과가 없다" in out["hookSpecificOutput"]["additionalContext"]
    assert "결과가 없다" in out["systemMessage"]
