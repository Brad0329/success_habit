"""`scripts/app.py`(루트에서 flutter를 app/ 안에서 실행) 검증.

flutter 자리에 현재 파이썬을 끼워, 실제로 app/에서 돌고 종료 코드를 그대로 돌려주는지 잰다.
"""

from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# 이름으로 import하지 않는다 — 루트의 app/ 폴더(Flutter)가 'app' 이름 공간 패키지로 먼저 잡힐 수 있다.
_spec = importlib.util.spec_from_file_location("scripts_app", ROOT / "scripts" / "app.py")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
APP, run = _mod.APP, _mod.run


def test_app_폴더_안에서_실행한다():
    code = f"import os,sys; sys.exit(0 if os.getcwd() == {str(APP)!r} else 3)"
    assert run(["-c", code], flutter=sys.executable) == 0


def test_종료_코드를_그대로_돌려준다():
    assert run(["-c", "import sys; sys.exit(7)"], flutter=sys.executable) == 7


def test_호출한_쪽의_작업_디렉토리는_그대로다():
    before = os.getcwd()
    run(["-c", "pass"], flutter=sys.executable)
    assert os.getcwd() == before


class _FakeRun:
    """subprocess.run 대역 — 부른 인자를 모으고, 지정한 하위 명령에 지정한 종료 코드를 준다."""

    def __init__(self, codes):
        self.calls, self._codes = [], codes

    def __call__(self, argv, **_kw):
        self.calls.append(argv[1:])
        return type("P", (), {"returncode": self._codes.get(argv[1], 0)})()


def test_analyze는_복잡도_지표도_돌리고_위반이면_실패(monkeypatch):
    # debt-audit S1 — 지표를 따로 부르게 두었더니 아무도 안 불러 위반이 쌓였다
    fake = _FakeRun({"pub": 2})
    monkeypatch.setattr(_mod.subprocess, "run", fake)
    assert run(["analyze"], flutter="flutter") == 2
    assert fake.calls[0] == ["analyze"]
    assert fake.calls[1][:4] == ["pub", "run", "dart_code_linter:metrics", "analyze"]


def test_analyze_둘_다_통과면_0_다른_명령은_지표_안_돌림(monkeypatch):
    fake = _FakeRun({})
    monkeypatch.setattr(_mod.subprocess, "run", fake)
    assert run(["analyze"], flutter="flutter") == 0
    assert len(fake.calls) == 2
    fake.calls.clear()
    assert run(["test"], flutter="flutter") == 0
    assert fake.calls == [["test"]]


def test_인자가_없으면_사용법과_2(capsys):
    assert run([], flutter=sys.executable) == 2
    assert "사용" in capsys.readouterr().err


def test_flutter가_없으면_127과_이유(monkeypatch, capsys):
    monkeypatch.setattr("shutil.which", lambda _name: None)
    assert run(["test"]) == 127
    assert "flutter를 찾지 못했다" in capsys.readouterr().err
