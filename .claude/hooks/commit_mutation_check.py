r"""테스트를 넣거나 고친 커밋에 변이 확인 결과가 없거나 변이를 묶었으면 경고한다 — 막지 않는다 (PreToolUse 훅, Phase 007 A3).

**왜 훅인가**: CLAUDE.md '검증 원칙'은 "새로 넣거나 고친 테스트는 대상 코드를 일부러 틀리게 만들어 실패를 한 번 본다
(한 번에 하나씩)"인데, 문장으로만 있어 4번 어겼다 — 생략(b34de40·3ef0ada: 이유를 붙여 건너뜀),
묶기(c2927be·f514b88: 변이 여러 개를 한 실행에). 묶기 예외는 두지 않는다(2026-11-27 사용자 결정 "허용 안 함").

**무엇을 보나** — 커밋에 테스트 파일(`app/test/*_test.dart`, `tests/test_*.py`)이 들어갈 때만:
  - 메시지에 '변이'가 든 줄 중 '실패'가 함께 든 줄이 없으면 → 결과 없음
  - '변이' 줄에 "하지 않았다·안 했다·생략·넣지 않았다"가 있으면 → 생략
  - '변이' 줄에 "묶·한 실행에·한 번에(‘하나씩’ 없이)"가 있으면 → 묶기
  - 정당한 예외(테스트를 지우기만 함, 기존 단언의 기대값만 바꿈)는 `변이 확인 해당 없음: <이유>` 한 줄로 통과
  버그 수정의 재현 테스트는 첫 실패가 변이를 겸한다 — "변이 확인: 재현 테스트 첫 실패로 겸함" 처럼 적는다.

**막지 않고 경고만 하는 이유**(2026-11-27 사용자 결정 "경고만 하게" — 처음엔 막았다): 커밋은 그대로 진행되고,
사용자(systemMessage)와 AI(additionalContext)에게 같은 경고가 간다. 경고를 받은 AI는 빠진 변이 확인을 하고
결과를 다음 커밋 메시지에 적는다(기록을 남기는 몫은 AI에게 있다 — 조용히 넘기지 않는다).

**커밋에 드는 파일** = 이미 올린 것(`git diff --cached`) + 같은 명령 앞쪽 `git add`의 경로 — 훅은 그 `git add`보다 먼저 돈다.
메시지는 `-F <파일>`(이 저장소의 표준, 팩_Windows_PowerShell.md) 또는 `-m "…"`에서 읽는다. 둘 다 아니면(amend --no-edit 등) 보지 않는다.

**훅이 고장 나면 경고 없이 통과시킨다**(이유는 stderr) — 경고가 안 나왔다고 규칙을 지킨 것은 아니다.
"""

from __future__ import annotations

import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

from hook_io import read_command, warn

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR") or Path(__file__).resolve().parents[2])

TEST_FILE = re.compile(r"(^|/)(app/test/.+_test\.dart|tests/test_[^/]+\.py)$")
COMMIT = re.compile(r"(?:^|[;&|]\s*)git\s+commit\b(?P<rest>[^;&|]*)")
FILE_ARG = re.compile(r"\s-F\s+(?P<path>\"[^\"]+\"|'[^']+'|\S+)")
MSG_ARG = re.compile(r"\s-m\s+(?:\"(?P<dq>[^\"]*)\"|'(?P<sq>[^']*)')")
ADD = re.compile(r"(?:^|[;&|]\s*)git\s+add\s+(?P<args>[^;&|]*)")

EXEMPT = re.compile(r"변이 확인 해당 없음:\s*\S")
SKIP = re.compile(r"하지 않았다|안 했다|생략|넣지 않았다|돌리지 않았다")  # '깨지지 않았다' 같은 결과 문장은 안 잡는다
# 동사 '묶다'만 — 명사 '묶음'(화면 이름, b88e5d7)은 안 잡는다.
BUNDLE = re.compile(r"묶(?:었|어|고|기|는다)|한 실행에|한 번에(?!\s*하나씩)")

REASON_HEAD = (
    "[경고 — 커밋은 막지 않았다] 커밋에 테스트 파일이 들어가는데 메시지의 변이 확인이 규칙"
    "(CLAUDE.md '검증 원칙' — 한 번에 하나씩, 실패를 본다)과 다르다:\n"
)
REASON_TAIL = (
    "\n→ 빠진 변이 확인을 하나씩 하고 결과(무엇을 틀리게 했고 어느 테스트가 실패했나)를 다음 커밋 메시지에 적는다.\n"
    "  버그 수정 재현 테스트는 '변이 확인: 재현 테스트 첫 실패로 겸함'. 테스트를 지우기만 했거나 기존 단언의 기대값만 바꿨으면\n"
    "  '변이 확인 해당 없음: <이유>' 한 줄. 묶기 예외는 없다(2026-11-27 사용자 결정)."
)


def _chunks(message: str) -> list[str]:
    """문단·글머리 하나(이어지는 줄까지)를 한 덩어리로 — 메시지는 72자쯤에서 줄을 바꿔 '변이'와 '실패'가
    다른 줄에 갈리기 쉽다(c2927be 들여 쓴 줄바꿈, 6f85f7e 들여쓰기 없는 줄바꿈). 빈 줄·글머리(`- `)에서 새 덩어리."""
    out: list[str] = []
    prev_blank = True
    for line in message.splitlines():
        blank = not line.strip()
        if not blank and not prev_blank and not line.lstrip().startswith("- "):
            out[-1] += " " + line.strip()
        elif not blank:
            out.append(line)
        prev_blank = blank
    return out


def problems(message: str, paths: list[str]) -> list[str]:
    """어긴 것 목록. 테스트가 이 함수를 직접 부른다."""
    if not any(TEST_FILE.search(p.replace("\\", "/")) for p in paths):
        return []
    lines = [l for l in _chunks(message) if "변이" in l]
    if any(EXEMPT.search(l) for l in lines):
        return []
    out = []
    if any(SKIP.search(l) for l in lines):
        out.append("생략 — '변이' 줄에 하지 않았다는 말이 있다(이유가 있으면 '변이 확인 해당 없음: <이유>')")
    if any(BUNDLE.search(l) for l in lines):
        out.append("묶기 — 변이를 한 실행에 묶었다는 말이 있다(하나씩 따로 돌린다)")
    if not any("실패" in l for l in lines) and not out:
        out.append("결과가 없다 — '변이'와 '실패'가 함께 든 줄이 없다")
    return out


def message_of(command: str, root: Path) -> str | None:
    """`git commit`의 메시지. 커밋이 아니거나 메시지를 알 수 없으면 None."""
    m = COMMIT.search(command or "")
    if not m:
        return None
    rest = " " + m.group("rest")
    f = FILE_ARG.search(rest)
    if f:
        path = root / f.group("path").strip("\"'")
        return path.read_text(encoding="utf-8")
    a = MSG_ARG.search(rest)
    if a:
        return a.group("dq") if a.group("dq") is not None else a.group("sq")
    return None


def add_paths(command: str) -> list[str]:
    """같은 명령 앞쪽 `git add`의 경로들(옵션 제외)."""
    out: list[str] = []
    for m in ADD.finditer(command or ""):
        out += [t for t in shlex.split(m.group("args"), posix=True) if not t.startswith("-")]
    return out


def _staged(root: Path) -> list[str]:
    p = subprocess.run(["git", "diff", "--cached", "--name-only", "--diff-filter=AM"], cwd=root,
                       capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=5)
    if p.returncode != 0:
        raise RuntimeError(f"git diff --cached 실패 (exit {p.returncode}) {p.stderr.strip()}")
    return p.stdout.splitlines()


def main() -> int:
    command = read_command("commit_mutation_check")
    if command is None:
        return 0
    try:
        message = message_of(command, ROOT)
        if message is None:
            return 0
        found = problems(message, _staged(ROOT) + add_paths(command))
    except Exception as e:
        # 훅 결함으로 커밋을 막지 않는다. 조용히 넘기지 않고 이유를 남긴다.
        print(f"commit_mutation_check: 검사하지 못해 통과시킨다 ({e})", file=sys.stderr)
        return 0
    if found:
        warn(REASON_HEAD + "\n".join(f"  - {p}" for p in found) + REASON_TAIL)
    return 0


if __name__ == "__main__":
    sys.exit(main())
