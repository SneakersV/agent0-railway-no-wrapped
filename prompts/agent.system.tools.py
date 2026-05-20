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
    from helpers import files
    from helpers.print_style import PrintStyle
except ModuleNotFoundError:
    from python.helpers.files import VariablesPlugin
    from python.helpers import files
    from python.helpers.print_style import PrintStyle


class BuidToolsPrompt(VariablesPlugin):
    def get_variables(
        self, file: str, backup_dirs: list[str] | None = None, **kwargs
    ) -> dict[str, Any]:

        folder = files.get_abs_path(os.path.dirname(file))
        folders = [folder]
        if backup_dirs:
            for backup_dir in backup_dirs:
                folders.append(files.get_abs_path(backup_dir))

        prompt_files = files.get_unique_filenames_in_dirs(
            folders, "agent.system.tool.*.md"
        )

        tools = []
        for prompt_file in prompt_files:
            try:
                tool = files.read_prompt_file(prompt_file, **kwargs)
                tools.append(tool)
            except Exception as e:
                PrintStyle().error(f"Error loading tool '{prompt_file}': {e}")

        return {"tools": "\n\n".join(tools)}
