import os
import sys
from pathlib import Path
from typing import Any, TYPE_CHECKING

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
    from helpers import projects, subagents
except ModuleNotFoundError:
    from python.helpers.files import VariablesPlugin
    from python.helpers import projects, subagents

if TYPE_CHECKING:
    from agent import Agent


class CallSubordinate(VariablesPlugin):
    def get_variables(
        self, file: str, backup_dirs: list[str] | None = None, **kwargs
    ) -> dict[str, Any]:
        agent: Agent | None = kwargs.get("_agent", None)
        project = projects.get_context_project_name(agent.context) if agent else None
        agents = subagents.get_available_agents_dict(project)

        if agents:
            profiles = {}
            for name, subagent in agents.items():
                profiles[name] = {
                    "title": subagent.title,
                    "description": subagent.description,
                    "context": subagent.context,
                }
            return {"agent_profiles": profiles}

        return {"agent_profiles": None}
