#!/bin/bash
set -e

echo "----------------------------------------------------------------"
echo "Initializing Agent Zero with Single-Disk Persistence (/per)"
echo "----------------------------------------------------------------"

# Define the single persistent volume path
PER_VOL="/per"

# Define the directories we want to persist (SYMLINK STRATEGY)
# ONLY user data is persisted. Core runtime (/opt/venv-a0) stays in the image.
declare -A PERSIST_PATHS=(
    ["/a0/usr"]="usr"
    ["/a0/memory"]="memory"
    ["/a0/prompts"]="prompts"
    ["/root/.ssh"]="ssh"
    ["/a0/skills"]="skills"
    ["/a0/tmp_chats"]="tmp_chats"
)

# Ensure /per is mounted
if [ ! -d "$PER_VOL" ]; then
    echo "WARNING: $PER_VOL is not mounted! Data will not be persisted."
    echo "Please mount a volume to $PER_VOL in Railway settings."
else
    echo "Volume detected at $PER_VOL"

    # 0. PRE-POPULATE /a0
    # We must populate /a0 from /git/agent-zero NOW, before creating symlinks.
    if [ ! -f "/a0/run_ui.py" ]; then
        echo "Pre-populating /a0 from /git/agent-zero..."
        cp -rn --no-preserve=ownership,mode /git/agent-zero/. /a0/
    fi

    # Re-apply the settings_get override after pre-population so the live API
    # path cannot drift back to the base-image copy.
    if [ -f /tmp/settings_get.py ]; then
        mkdir -p /a0/python/api /git/agent-zero/python/api
        cp /tmp/settings_get.py /a0/python/api/settings_get.py
        cp /tmp/settings_get.py /git/agent-zero/python/api/settings_get.py
        echo "Re-applied settings_get override to /a0 and /git/agent-zero"
    else
        echo "WARNING: /tmp/settings_get.py missing; settings_get override was not re-applied"
    fi
    
    # 1. Handle Symlinked Directories
    for CONTAINER_PATH in "${!PERSIST_PATHS[@]}"; do
        PER_SUBDIR="${PERSIST_PATHS[$CONTAINER_PATH]}"
        PER_PATH="$PER_VOL/$PER_SUBDIR"
        
        echo "Processing $CONTAINER_PATH -> $PER_PATH"
        
        if [ ! -d "$PER_PATH" ]; then
            echo "  -> First run detected for $PER_SUBDIR. Moving initial data to volume..."
            mkdir -p "$(dirname "$PER_PATH")"
            if [ -d "$CONTAINER_PATH" ]; then
                mv "$CONTAINER_PATH" "$PER_PATH"
            else
                mkdir -p "$PER_PATH"
            fi
        else
            echo "  -> Found existing data in volume for $PER_SUBDIR. Syncing..."
            
            # If the container path is already a symlink (from a previous run),
            # it points to the volume itself, so we can't copy from it.
            if [ -L "$CONTAINER_PATH" ]; then
                echo "  -> Already symlinked from previous run."
                # For prompts, copy from the original image source instead
                if [[ "$PER_SUBDIR" == "prompts" && -d "/git/agent-zero/prompts" ]]; then
                    echo "    -> Force updating prompts from image source..."
                    cp -rf /git/agent-zero/prompts/. "$PER_PATH"/
                fi
                # Remove the old symlink so we can recreate it cleanly below
                rm -f "$CONTAINER_PATH"
            else
                # Special handling for prompts: ALWAYS update them from image
                if [[ "$PER_SUBDIR" == "prompts" && -d "$CONTAINER_PATH" ]]; then
                    echo "    -> Force updating prompts from image..."
                    cp -rf "$CONTAINER_PATH"/. "$PER_PATH"/
                elif [ -d "$CONTAINER_PATH" ]; then
                    cp -rn "$CONTAINER_PATH"/. "$PER_PATH"/ || true
                fi
                
                # Remove the container version
                rm -rf "$CONTAINER_PATH"
            fi
        fi

        # Create the symlink
        ln -s "$PER_PATH" "$CONTAINER_PATH"
        echo "  -> Linked $CONTAINER_PATH -> $PER_PATH"
    done

    # 2. CLEANUP: Remove zombie libraries from /per/lib
    # Previous deployments may have installed conflicting libs here.
    # Strategy A: Core runtime lives ONLY in /opt/venv-a0.
    # /per/lib should not contain core libs that shadow the image's versions.
    PER_LIB="$PER_VOL/lib"
    if [ -d "$PER_LIB" ]; then
        echo "Cleaning zombie libraries from $PER_LIB..."
        # Remove known conflict packages that were previously installed here
        rm -rf "$PER_LIB/fastmcp"* "$PER_LIB/pydantic"* \
               "$PER_LIB/lxml"* "$PER_LIB/supervisor"* \
               "$PER_LIB/google"* "$PER_LIB/httplib2"* \
               "$PER_LIB/pandas"* "$PER_LIB/numpy"* \
               "$PER_LIB/scipy"* "$PER_LIB/torch"* \
               "$PER_LIB/bin" 2>/dev/null || true
        echo "  -> Cleanup complete."
    fi
fi

echo "Persistence setup complete."

echo "Starting standard Agent Zero initialization..."

# PATCH: The original initialize.sh tries to copy /per/* to /, which conflicts 
# with our symlink strategy (and overwrites /lib). We must disable it.
sed -i 's|cp -r --no-preserve=ownership,mode /per/\* /|echo "Skipping copy from /per (managed by persistence script)"|' /exe/initialize.sh

# 3. Compatibility patch for base-image scripts that expect:
#    source /opt/venv-a0/bin/activate
if [ -x /opt/venv-a0/bin/python ] && [ ! -f /opt/venv-a0/bin/activate ]; then
  echo "Creating compatibility activate script for /opt/venv-a0 ..."
  mkdir -p /opt/venv-a0/bin
  cat > /opt/venv-a0/bin/activate <<'EOF'
VIRTUAL_ENV=/opt/venv-a0
export VIRTUAL_ENV
case ":$PATH:" in
  *":$VIRTUAL_ENV/bin:"*) ;;
  *) PATH="$VIRTUAL_ENV/bin:$PATH"; export PATH ;;
esac
unset PYTHONHOME
EOF
  chmod +x /opt/venv-a0/bin/activate
fi

if [ -f /ins/setup_venv.sh ]; then
  cp /ins/setup_venv.sh /ins/setup_venv.sh.bak 2>/dev/null || true
  python3 - <<'PY'
from pathlib import Path
p = Path("/ins/setup_venv.sh")
if p.exists():
    s = p.read_text()
    old = "source /opt/venv-a0/bin/activate"
    new = """if [ -f /opt/venv-a0/bin/activate ]; then
  source /opt/venv-a0/bin/activate
elif [ -x /opt/venv-a0/bin/python ]; then
  export VIRTUAL_ENV=/opt/venv-a0
  export PATH=/opt/venv-a0/bin:$PATH
fi"""
    if old in s:
        p.write_text(s.replace(old, new))
PY
fi

# Ensure settings_get masks mcp_server_token even if the upstream base image
# has not yet shipped the fix.
/opt/venv-a0/bin/python - <<'PY'
from pathlib import Path

path = Path("/a0/python/helpers/settings.py")
if not path.exists():
    print("WARNING: settings.py not found at /a0/python/helpers/settings.py; skipping runtime mask patch")
    raise SystemExit(0)

marker = '\n    #secrets'
insertion = (
    '    out["settings"]["mcp_server_token"] = (\n'
    '        API_KEY_PLACEHOLDER if out["settings"].get("mcp_server_token") else ""\n'
    '    )\n'
)

content = path.read_text()
if 'out["settings"]["mcp_server_token"] = (' not in content:
    if marker not in content:
        print("WARNING: Could not find insertion marker for runtime mcp_server_token patch")
        raise SystemExit(0)
    path.write_text(content.replace(marker, f'\n{insertion}{marker}', 1))
    print("Patched runtime settings.py for mcp_server_token masking")
else:
    print("Runtime settings.py already masks mcp_server_token")
PY

exec /exe/initialize.sh "$@"
