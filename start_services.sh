# Start the File Receiver API in the background
echo "Starting File Receiver on port 8001..."

# --- Auto-configure Credentials from Env Var ---
if [ -n "$GDRIVE_JSON" ]; then
    echo "Creating credentials.json from GDRIVE_JSON environment variable..."
    echo "$GDRIVE_JSON" > /a0/credentials.json
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
# -----------------------------------------------

/opt/venv-a0/bin/python file_receiver.py &

# Start the Main Agent Zero Process (Keep this in foreground to be the main process)
echo "Starting Agent Zero..."
/opt/venv-a0/bin/python main.py
