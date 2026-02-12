# Start the File Receiver API in the background
echo "Starting File Receiver on port 8001..."

# --- Auto-configure Credentials from Env Var ---
if [ -n "$GDRIVE_JSON" ]; then
    echo "Creating credentials.json from GDRIVE_JSON environment variable..."
    echo "$GDRIVE_JSON" > /a0/credentials.json
fi
# -----------------------------------------------

/opt/venv-a0/bin/python file_receiver.py &

# Start the Main Agent Zero Process (Keep this in foreground to be the main process)
echo "Starting Agent Zero..."
/opt/venv-a0/bin/python main.py
