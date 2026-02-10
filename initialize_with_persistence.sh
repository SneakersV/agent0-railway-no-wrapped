#!/bin/bash
set -e

echo "----------------------------------------------------------------"
echo "Initializing Agent Zero with Single-Disk Persistence (/per)"
echo "----------------------------------------------------------------"

# Define the single persistent volume path
PER_VOL="/per"

# Define the directories we want to persist
# These are the internal paths in the container that should be linked to /per
declare -A PERSIST_PATHS=(
    ["/a0/usr"]="usr"
    ["/a0/memory"]="memory"
    ["/a0/prompts"]="prompts"
    ["/opt/venv-a0"]="venv-a0"
    ["/root/.ssh"]="ssh"
)

# Ensure /per is mounted
if [ ! -d "$PER_VOL" ]; then
    echo "WARNING: $PER_VOL is not mounted! Data will not be persisted."
    echo "Please mount a volume to $PER_VOL in Railway settings."
else
    echo "Volume detected at $PER_VOL"
    
    # Iterate over each path to persist
    for CONTAINER_PATH in "${!PERSIST_PATHS[@]}"; do
        PER_SUBDIR="${PERSIST_PATHS[$CONTAINER_PATH]}"
        PER_PATH="$PER_VOL/$PER_SUBDIR"
        
        echo "Processing $CONTAINER_PATH -> $PER_PATH"
        
        # 1. If persistent path doesn't exist, copy initial data from container
        if [ ! -d "$PER_PATH" ]; then
            echo "  -> First run detected for $PER_SUBDIR. Initializing from image..."
            # Create parent dir in vol if needed
            mkdir -p "$(dirname "$PER_PATH")"
            
            # If container path exists, copy it. Else just make empty dir.
            if [ -d "$CONTAINER_PATH" ]; then
                cp -r --no-preserve=ownership "$CONTAINER_PATH" "$PER_PATH"
            else
                mkdir -p "$PER_PATH"
            fi
        else
            echo "  -> Found existing data in volume for $PER_SUBDIR."
        fi

        # 2. Swap container directory with symlink
        # Remove the original directory in the container (it's ephemeral anyway)
        rm -rf "$CONTAINER_PATH"
        
        # Create the symlink
        ln -s "$PER_PATH" "$CONTAINER_PATH"
        echo "  -> Linked $CONTAINER_PATH -> $PER_PATH"
    done
fi

echo "Persistence setup complete."

# pass control to the original entrypoint or command
# The original image CMD is ["/exe/initialize.sh", "main"] or similar.
# We will assume the user wants to run the standard startup directly.
# Looking at the base image Dockerfile (from previous research), the CMD is /exe/initialize.sh
echo "Starting standard Agent Zero initialization..."
exec /exe/initialize.sh "$@"
