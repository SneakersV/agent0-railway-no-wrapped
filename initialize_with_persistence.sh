#!/bin/bash
set -e

echo "----------------------------------------------------------------"
echo "Initializing Agent Zero with Single-Disk Persistence (/per)"
echo "----------------------------------------------------------------"

# Define the single persistent volume path
PER_VOL="/per"

# Define the directories we want to persist (SYMLINK STRATEGY)
# CAUTION: We REMOVED /opt/venv-a0 from here to avoid "No space left on device"
# instead we will use PIP_TARGET strategy for libraries
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
    # Otherwise, the default copy_A0.sh script will run later, try to copy directories
    # over our symlinks, and fail with "cannot overwrite non-directory".
    if [ ! -f "/a0/run_ui.py" ]; then
        echo "Pre-populating /a0 from /git/agent-zero..."
        cp -rn --no-preserve=ownership,mode /git/agent-zero/. /a0/
    fi
    
    # 1. Handle Symlinked Directories
    for CONTAINER_PATH in "${!PERSIST_PATHS[@]}"; do
        PER_SUBDIR="${PERSIST_PATHS[$CONTAINER_PATH]}"
        PER_PATH="$PER_VOL/$PER_SUBDIR"
        
        echo "Processing $CONTAINER_PATH -> $PER_PATH"
        
        # Check if we have data in the container (now we do, because of pre-populate)
        # If persistent storage is empty, move container data there.
        # If persistent storage has data, delete container data and link.
        
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
            # This fixes "FileNotFound" if the volume has broken/old prompts
            if [[ "$PER_SUBDIR" == "prompts" && -d "$CONTAINER_PATH" ]]; then
                echo "    -> Force updating prompts from image..."
                cp -rf "$CONTAINER_PATH"/. "$PER_PATH"/
            elif [ -d "$CONTAINER_PATH" ]; then
                # For other dirs, just fill missing files (don't overwrite user data)
                # Use /. to copy contents including hidden files, avoids error if empty
                cp -rn "$CONTAINER_PATH"/. "$PER_PATH"/ || true
            fi
            
            # Remove the container version
            rm -rf "$CONTAINER_PATH"
        fi

        # Create the symlink
        ln -s "$PER_PATH" "$CONTAINER_PATH"
        echo "  -> Linked $CONTAINER_PATH -> $PER_PATH"
    done

    # 2. Handle Python Libraries (PIP_TARGET Strategy)
    # We create a directory for user-installed packages
    PER_LIB="$PER_VOL/lib"
    mkdir -p "$PER_LIB"
    echo "  -> Prepared persistent library directory at $PER_LIB"
fi

echo "Persistence setup complete."

echo "Starting standard Agent Zero initialization..."

# PATCH: The original initialize.sh tries to copy /per/* to /, which conflicts 
# with our symlink strategy (and overwrites /lib). We must disable it.
# The line is: cp -r --no-preserve=ownership,mode /per/* /
sed -i 's|cp -r --no-preserve=ownership,mode /per/\* /|echo "Skipping copy from /per (managed by persistence script)"|' /exe/initialize.sh

# --- Self-Healing: Fix Persistence Conflicts (Pre-Boot) ---
# We must do this HERE, before transferring control to supervisor, to avoid race conditions.
echo "Self-Healing: Cleaning up potential conflict libraries in /per/lib..."
export PIP_TARGET=/per/lib
export PYTHONPATH=/per/lib:/a0

# 1. Force Uninstall to remove old/incompatible versions from volume
# We allow failure (|| true) in case they don't exist
/opt/venv-a0/bin/python -m pip uninstall -y fastmcp pydantic google-api-python-client google-auth-httplib2 google-auth-oauthlib || true

# 2. Re-install fresh compatible versions
# Downgrading to ensure compatibility with Agent Zero v0.9.7 code
echo "Self-Healing: Installing FIXED compatible libraries..."
/opt/venv-a0/bin/python -m pip install --no-cache-dir \
    "fastmcp==1.4.1" \
    "pydantic==2.9.2" \
    "google-api-python-client" \
    "google-auth-httplib2" \
    "google-auth-oauthlib" || echo "WARNING: Self-healing install failed!"
# -----------------------------------------------

exec /exe/initialize.sh "$@"
