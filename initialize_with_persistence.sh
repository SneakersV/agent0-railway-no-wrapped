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

exec /exe/initialize.sh "$@"
