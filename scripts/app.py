"""루트에서 flutter 명령을 app/ 안에서 대신 실행한다.

사용: python scripts/app.py test | analyze | pub get | build apk --debug …

**왜 있나**: flutter는 pubspec.yaml이 있는 폴더(app/)에서만 돈다. `cd app && flutter test`는
`no_redundant_cd` 훅이 막고, `cd app`을 따로 부르면 그 뒤의 `pytest tests/`·`git add`가 app/ 안에서
조용히 틀리게 돈다(기존판 2026-10-29 구조 결정을 그대로 잇는다). 이 스크립트는 작업 디렉토리를 바꾸지 않는다.

인자는 그대로 flutter에 넘기고, flutter의 종료 코드를 그대로 돌려준다.
`analyze`(인자 없이)만 예외 — 뒤이어 복잡도 지표(dart_code_linter)도 돌리고 둘 중 하나라도 실패면 실패.
`test`에 인자를 붙이는 형태는 `no_targeted_flutter_test` 훅이 이 스크립트 호출에도 똑같이 막는다.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "app"

USAGE = "사용: python scripts/app.py <flutter 하위 명령> [인자…]  (예: test, analyze, build apk --debug)"


def run(args: list[str], flutter: str | None = None) -> int:
    """flutter <args>를 app/에서 실행하고 종료 코드를 돌려준다. 테스트가 flutter 자리를 바꿔 끼운다."""
    if not args:
        print(USAGE, file=sys.stderr)
        return 2
    exe = flutter or shutil.which("flutter")
    if exe is None:
        print("app.py: PATH에서 flutter를 찾지 못했다 — flutter doctor로 설치를 확인할 것", file=sys.stderr)
        return 127
    if not (APP / "pubspec.yaml").exists():
        print(f"app.py: {APP / 'pubspec.yaml'}이 없다 — Flutter 앱 폴더가 아니다", file=sys.stderr)
        return 2
    code = subprocess.run([exe, *args], cwd=APP, check=False).returncode
    if args == ["analyze"]:
        # 복잡도 상한(analysis_options.yaml dart_code_linter)은 분석기 플러그인이 안 돼 CLI로만 돈다 — 따로 부르면
        # 아무도 안 불러 위반 2건이 쌓여 있었다(기존판 debt-audit 2026-11-04 S1). 그래서 analyze에 묶는다.
        print("app.py: 복잡도 지표(dart_code_linter) 검사", file=sys.stderr)
        metrics = subprocess.run([exe, "pub", "run", "dart_code_linter:metrics", "analyze", "lib",
                                  "--set-exit-on-violation-level=warning"], cwd=APP, check=False).returncode
        if metrics != 0:
            print(f"app.py: 복잡도 지표 위반 또는 실행 실패(종료 코드 {metrics})", file=sys.stderr)
        code = code or metrics
    return code


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
