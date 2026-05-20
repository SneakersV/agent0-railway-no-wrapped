import os
import sys
from pathlib import Path
from typing import Any

ROOT_CANDIDATES = [
    Path(os.environ.get("AGENT_ZERO_ROOT", "")),
    Path("/git/agent-zero"),
    Path("/a0"),
    Path(__file__).resolve().parents[1],
]
for root in ROOT_CANDIDATES:
    if root and root.exists() and str(root) not in sys.path:
        sys.path.insert(0, str(root))

try:
    from helpers.files import VariablesPlugin
    from helpers import settings
except ModuleNotFoundError:
    from python.helpers.files import VariablesPlugin
    from python.helpers import settings


class WorkdirPath(VariablesPlugin):
    def get_variables(
        self, file: str, backup_dirs: list[str] | None = None, **kwargs
    ) -> dict[str, Any]:
        set = settings.get_settings()
        return {"workdir_path": set["workdir_path"]}
