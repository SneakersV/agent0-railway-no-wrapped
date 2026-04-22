FROM agent0ai/agent-zero:latest
ARG CACHE_BUST=2
RUN echo "CACHE_BUST=$CACHE_BUST"

WORKDIR /a0

# --- ML Stack Alignment ---
# The base image has pre-compiled ML libs. We re-pin them here for ABI consistency.
ENV PYTHONNOUSERSITE=1

# Upgrade build tooling
RUN /opt/venv-a0/bin/python -m pip install --no-cache-dir -U "pip<25" "setuptools" "wheel"

# 1) Remove problematic preinstalled compiled stack first (avoid mixing ABIs)
RUN /opt/venv-a0/bin/python -m pip uninstall -y \
  numpy scipy scikit-learn transformers accelerate sentence-transformers \
  torchvision timm onnx onnxruntime ml_dtypes faiss-cpu \
  || true

# 2) Install NUMPY FIRST (pin hard)
RUN /opt/venv-a0/bin/python -m pip install --no-cache-dir --only-binary=:all: \
  "numpy==1.26.4"

# 3) Install SCIPY + SKLEARN pinned, binary only (must match numpy ABI)
RUN /opt/venv-a0/bin/python -m pip install --no-cache-dir --only-binary=:all: \
  "scipy==1.12.0" \
  "scikit-learn==1.5.2"

# 4) NLP stack pinned (stable combo with py3.12 CPU)
RUN /opt/venv-a0/bin/python -m pip install --no-cache-dir --only-binary=:all: \
  "transformers==4.40.2" \
  "accelerate==0.30.1" \
  "sentence-transformers==2.7.0"

# 5) Torch CPU 2.4.0
RUN /opt/venv-a0/bin/python -m pip install --no-cache-dir \
  --index-url https://download.pytorch.org/whl/cpu \
  "torch==2.4.0" \
  "torchvision==0.19.0" \
  "numpy<2"

RUN /opt/venv-a0/bin/python -m pip install --no-cache-dir \
  "timm==1.0.9" \
  "faiss-cpu==1.8.0" \
  "numpy<2"

# --- Persistence Setup ---
# STRATEGY A: Core libs stay in /opt/venv-a0 (from the Docker Image).
#             /per only persists DATA (memory, prompts, usr, ssh).
#             We do NOT set PIP_TARGET or override PYTHONPATH globally.
#             This prevents "zombie" libraries from /per/lib overriding the runtime.

# Copy the custom initialization script
COPY initialize_with_persistence.sh /initialize_with_persistence.sh
RUN chmod +x /initialize_with_persistence.sh

# --- Extra Tools ---
# Install ONLY our custom dependencies. DO NOT install fastmcp or pydantic here.
# The base image already has the correct, compatible versions of those.
RUN /opt/venv-a0/bin/python -m pip install --no-cache-dir \
  "fastapi" \
  "uvicorn" \
  "python-multipart" \
  "google-api-python-client" \
  "google-auth-httplib2" \
  "google-auth-oauthlib" \
  "pandas" \
  "openpyxl" \
  "tabulate"

# Copy the file receiver script and start script
COPY file_receiver.py /a0/file_receiver.py
COPY start_services.sh /a0/start_services.sh
COPY tools/read_drive_file.py /a0/tools/read_drive_file.py
COPY overrides/settings_get.py /tmp/settings_get.py
RUN chmod +x /a0/start_services.sh

RUN mkdir -p /a0/api /git/agent-zero/api /a0/python/api /git/agent-zero/python/api && \
  cp /tmp/settings_get.py /a0/api/settings_get.py && \
  cp /tmp/settings_get.py /git/agent-zero/api/settings_get.py && \
  cp /tmp/settings_get.py /a0/python/api/settings_get.py && \
  cp /tmp/settings_get.py /git/agent-zero/python/api/settings_get.py

# Mask mcp_server_token in settings_get responses until the upstream base image
# includes the same fix.
RUN /opt/venv-a0/bin/python - <<'PY'
from pathlib import Path

needle = '    out["settings"]["root_password"] = API_KEY_PLACEHOLDER if out["settings"].get("root_password") else ""\\n'
replacement = needle + (
    '    out["settings"]["mcp_server_token"] = (\\n'
    '        API_KEY_PLACEHOLDER if out["settings"].get("mcp_server_token") else ""\\n'
    '    )\\n'
)

for raw_path in (
    "/git/agent-zero/helpers/settings.py",
    "/a0/helpers/settings.py",
    "/git/agent-zero/python/helpers/settings.py",
    "/a0/python/helpers/settings.py",
):
    path = Path(raw_path)
    if not path.exists():
        continue
    content = path.read_text()
    if 'out["settings"]["mcp_server_token"] = (' in content:
        continue
    if needle not in content:
        raise SystemExit(f"Could not patch {path}: anchor not found")
    path.write_text(content.replace(needle, replacement, 1))
    print(f"Patched {path}")
PY

# Set the new entrypoint/command to run both services
CMD ["/initialize_with_persistence.sh", "/a0/start_services.sh"]
