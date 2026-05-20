# Start the File Receiver API in the background
echo "Starting File Receiver on port 8001..."

# --- Auto-configure Credentials from Env Var ---
if [ -n "$GDRIVE_JSON" ]; then
    echo "Creating credentials.json from GDRIVE_JSON environment variable..."
    printf '%s' "$GDRIVE_JSON" > /a0/credentials.json
    chmod 600 /a0/credentials.json
    export GOOGLE_APPLICATION_CREDENTIALS=/a0/credentials.json
elif [ -f /a0/credentials.json ]; then
    export GOOGLE_APPLICATION_CREDENTIALS=/a0/credentials.json
else
    echo "WARNING: GDRIVE_JSON is not set and /a0/credentials.json does not exist."
fi

# --- Self-Healing: Fix Persistence Conflicts ---
# The volume (/per/lib) mimics user-installed packages but might hold outdated/conflicting libs
# (like old pydantic) that break the new image's code (fastmcp).
# We force-install critical libs to /per/lib to ensure consistency.
echo "Self-Healing: Ensuring critical libraries in /per/lib are up to date..."
export PIP_TARGET=/per/lib
/opt/venv-a0/bin/python -m pip install --upgrade --no-deps \
    "fastmcp" \
    "pydantic" \
    "google-api-python-client" \
    "google-auth-httplib2" \
    "google-auth-oauthlib" || echo "WARNING: Self-healing update failed, continuing anyway..."

# --- Environment Setup: Supabase Venv & Dependencies ---
echo "Ensuring supabase_venv exists and has required dependencies..."
mkdir -p /a0/skills
VENV_PATH="/a0/skills/supabase_venv"
if [ ! -d "$VENV_PATH" ]; then
    /opt/venv-a0/bin/python -m venv "$VENV_PATH"
fi
"$VENV_PATH/bin/python" -m pip install --upgrade pip
"$VENV_PATH/bin/python" -m pip install requests ipython

# --- Compatibility Fix: ipython path ---
echo "Creating ipython compatibility symlink..."
mkdir -p /usr/local/bin
mkdir -p /opt/venv-a0/bin
ln -sf "$VENV_PATH/bin/ipython" /usr/local/bin/ipython || true
ln -sf "$VENV_PATH/bin/ipython" /opt/venv-a0/bin/ipython || true
# -----------------------------------------------

# --- Optimization: Generate Skills Index ---
echo "Generating enhanced skills index in /per/memory/skills_index.md..."
/opt/venv-a0/bin/python tools/index_skills_v2.py
# -----------------------------------------------

/opt/venv-a0/bin/python file_receiver.py &

# Start the Main Agent Zero Process (Keep this in foreground to be the main process)
echo "Starting Agent Zero..."
/opt/venv-a0/bin/python main.py
