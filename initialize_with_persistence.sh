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
    
    # 1. Handle Symlinked Directories
    for CONTAINER_PATH in "${!PERSIST_PATHS[@]}"; do
        PER_SUBDIR="${PERSIST_PATHS[$CONTAINER_PATH]}"
        PER_PATH="$PER_VOL/$PER_SUBDIR"
        
        echo "Processing $CONTAINER_PATH -> $PER_PATH"
        
        # If persistent path doesn't exist, copy initial data from container
        if [ ! -d "$PER_PATH" ]; then
            echo "  -> First run detected for $PER_SUBDIR. Initializing from image..."
            mkdir -p "$(dirname "$PER_PATH")"
            if [ -d "$CONTAINER_PATH" ]; then
                cp -r --no-preserve=ownership "$CONTAINER_PATH" "$PER_PATH"
            else
                mkdir -p "$PER_PATH"
            fi
        fi

        # Swap container directory with symlink
        rm -rf "$CONTAINER_PATH"
        ln -s "$PER_PATH" "$CONTAINER_PATH"
        echo "  -> Linked $CONTAINER_PATH -> $PER_PATH"
    done

    # 2. Handle Python Libraries (PIP_TARGET Strategy)
    # We create a directory for user-installed packages, but we DO NOT move the system venv
    PER_LIB="$PER_VOL/lib"
    mkdir -p "$PER_LIB"
    echo "  -> Prepared persistent library directory at $PER_LIB"
    
    # We rely on ENV variables (PIP_TARGET, PYTHONPATH) set in Dockerfile 
    # to make use of this directory.
fi

echo "Persistence setup complete."

echo "Starting standard Agent Zero initialization..."

# PATCH: The original initialize.sh tries to copy /per/* to /, which conflicts 
# with our symlink strategy (and overwrites /lib). We must disable it.
# The line is: cp -r --no-preserve=ownership,mode /per/* /
sed -i 's|cp -r --no-preserve=ownership,mode /per/\* /|echo "Skipping copy from /per (managed by persistence script)"|' /exe/initialize.sh

exec /exe/initialize.sh "$@"
