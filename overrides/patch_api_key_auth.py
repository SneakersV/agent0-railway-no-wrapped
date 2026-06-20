from pathlib import Path


TARGETS = (
    "/a0/helpers/api.py",
    "/git/agent-zero/helpers/api.py",
    "/a0/python/helpers/api.py",
    "/git/agent-zero/python/helpers/api.py",
)

OLD_TOKEN_LINE = '        valid_api_key = get_settings()["mcp_server_token"]\n'
NEW_TOKEN_BLOCK = '''        configured_api_keys = [
            get_settings()["mcp_server_token"],
            os.environ.get("AGENT0_API_KEY"),
            os.environ.get("API_KEY"),
            os.environ.get("MCP_SERVER_TOKEN"),
            os.environ.get("AGENT0_MCP_SERVER_TOKEN"),
        ]
        valid_api_keys = {key for key in configured_api_keys if key}
'''


def ensure_os_import(content: str) -> str:
    if "\nimport os\n" in f"\n{content}\n":
        return content

    for anchor in ("import functools\n", "import json\n", "import time\n"):
        if anchor in content:
            return content.replace(anchor, f"{anchor}import os\n", 1)

    return "import os\n" + content


def patch_file(path: Path) -> bool:
    if not path.exists():
        return False

    content = path.read_text()
    if "valid_api_keys = {key for key in configured_api_keys if key}" in content:
        print(f"API key auth already supports env aliases: {path}")
        return True

    if OLD_TOKEN_LINE not in content:
        print(f"WARNING: api key auth anchor not found: {path}")
        return False

    content = ensure_os_import(content)
    content = content.replace(OLD_TOKEN_LINE, NEW_TOKEN_BLOCK, 1)
    content = content.replace("if api_key != valid_api_key:", "if api_key not in valid_api_keys:")
    path.write_text(content)
    print(f"Patched API key auth env aliases: {path}")
    return True


patched = False
for raw_path in TARGETS:
    patched = patch_file(Path(raw_path)) or patched

if not patched:
    raise SystemExit("Could not patch any Agent Zero helpers/api.py path")
