# Python

## Signals
Kind: stack
Manifest: pyproject.toml
Lockfile: uv.lock, poetry.lock, pdm.lock
Workspace: `[tool.uv.workspace]`
Extensions: .py .pyi
Shebangs: python python3
Runtime version: .python-version, pyproject `requires-python`, .tool-versions, mise.toml

## lint

### ruff
Publisher: astral-sh
Tier: 2: https://github.com/astral-sh/ruff
Evidence: `[tool.ruff]` table, `ruff` dev dependency
Rung: edit
Run: `ruff check --fix --force-exclude {files}`
Hook: https://github.com/astral-sh/ruff-pre-commit
Pin: package pypi ruff
Route: `uv tool install ruff=={version}`; Blocked: Astral's curl installer, release binaries
Constraints: None.
Traps: an explicit file path bypasses `[tool.ruff] exclude` unless `--force-exclude` is passed.

## format

### ruff format
Publisher: astral-sh
Tier: 2: https://github.com/astral-sh/ruff
Evidence: `[tool.ruff.format]` table, `ruff` dev dependency
Rung: edit
Run: `ruff format {files}`
Hook: https://github.com/astral-sh/ruff-pre-commit
Pin: package pypi ruff
Route: `uv tool install ruff=={version}`; Blocked: Astral's curl installer, release binaries
Constraints: the lint role's `--fix` must run before this, on the vendor hook's own ordering.
Traps: None.

### black
Publisher: psf
Tier: 2: https://github.com/psf/black
Evidence: `[tool.black]` table, `black` dev dependency
Rung: edit
Run: `black {files}`
Hook: https://github.com/psf/black-pre-commit-mirror
Pin: package pypi black
Route: `uv tool install black=={version}`
Constraints: None.
Traps: None.

## typecheck

### mypy
Publisher: python
Tier: 2: https://github.com/python/mypy
Evidence: `[tool.mypy]` table, `mypy.ini`, `mypy` dev dependency
Rung: turn
Run: `mypy .`
Hook: local
Pin: package pypi mypy
Route: `uv tool install mypy=={version}`
Constraints: None.
Traps: the only pre-commit hook, `pre-commit/mirrors-mypy`, is a third-party mirror that runs in an isolated venv without project dependencies; this entry pins and runs mypy itself instead.

### pyright
Publisher: Microsoft
Tier: 2: https://github.com/microsoft/pyright
Evidence: `pyrightconfig.json`, `[tool.pyright]` table, `pyright` dev dependency
Rung: turn
Run: `pyright .`
Hook: local
Pin: package npm pyright
Route: `npm install -g pyright@{version}`; Blocked: the PyPI `pyright` wheel is a third-party wrapper, not the vendor's own registry
Constraints: needs Node on PATH (ships as an npm package).
Traps: the CLI costs 4 to 10 s per call (Node start, no cache); do not put it on the edit rung.

### ty
Publisher: astral-sh
Tier: 2: https://github.com/astral-sh/ty
Evidence: `[tool.ty]` table, `ty` dev dependency
Rung: turn
Run: `ty check .`
Hook: https://github.com/astral-sh/ty-pre-commit
Pin: package pypi ty
Route: `uv tool install ty=={version}`
Constraints: beta (0.0.x, classifier "4 - Beta").
Traps: the vendor hook may create or update `uv.lock`; pass `--isolated` to avoid that.

## test runner

### pytest
Publisher: pytest-dev
Tier: 2: https://github.com/pytest-dev/pytest
Evidence: `pytest` dev dependency, `[tool.pytest.ini_options]` table, `pytest.ini`, `tests/` directory
Rung: turn
Run: `pytest`
Hook: local
Pin: package pypi pytest
Route: `uv tool install pytest=={version}`
Constraints: None.
Traps: None.

## affected tests

### pytest-testmon
Publisher: tarpas
Tier: 2: https://testmon.org
Evidence: `.testmondata`, `pytest-testmon` dev dependency
Rung: turn
Run: `pytest --testmon`
Hook: local
Pin: package pypi pytest-testmon
Route: `uv tool install pytest-testmon=={version}`
Constraints: needs `coverage<8` and a first full run to build `.testmondata` before it can select.
Traps: crashes with `KeyError: 'lf'` under `-p no:cacheprovider`.
