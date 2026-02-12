FROM agent0ai/agent-zero:v0.9.7
ARG CACHE_BUST=1
RUN echo "CACHE_BUST=$CACHE_BUST"

WORKDIR /a0

ENV PYTHONNOUSERSITE=1
ENV PYTHONPATH=

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
# Downgrade transformers to avoid 'register_fake' issues with slightly older torch,
# or ensure torch is new enough. Let's align them.
RUN /opt/venv-a0/bin/python -m pip install --no-cache-dir --only-binary=:all: \
  "transformers==4.40.2" \
  "accelerate==0.30.1" \
  "sentence-transformers==2.7.0"

# 5) Torch CPU 2.4.0 (recent enough for modern transformers)
# FORCE numpy<2 again here to prevent torch dependencies from upgrading it
RUN /opt/venv-a0/bin/python -m pip install --no-cache-dir \
  --index-url https://download.pytorch.org/whl/cpu \
  "torch==2.4.0" \
  "numpy<2"

RUN /opt/venv-a0/bin/python -m pip install --no-cache-dir \
  "timm==1.0.9" \
  "faiss-cpu==1.8.0" \
  "numpy<2"

# --- Persistence Setup ---
# --- Persistence Setup ---
# 1. Config environment for persistent Python packages (Hybrid Persistence)
#    STRATEGY CHANGE: Core libs go to /opt/venv-a0 (default).
#    We prioritize the VENV site-packages over /per/lib to prevent "zombie" libs from overriding core.
ENV PYTHONPATH=/opt/venv-a0/lib/python3.12/site-packages:/a0:/per/lib \
  PATH=/opt/venv-a0/bin:/per/lib/bin:$PATH

# 2. Copy the custom initialization script
COPY initialize_with_persistence.sh /initialize_with_persistence.sh
RUN chmod +x /initialize_with_persistence.sh

# Set the new entrypoint/command
# --- File Receiver API Setup ---
# Install dependencies for the upload API AND Google Drive Tools
# CRITICAL: We install these into the IMAGE (/opt/venv-a0), so they are always fresh and compatible.
# We also pin versions to ensure stability.
RUN /opt/venv-a0/bin/python -m pip install --no-cache-dir \
  "fastapi" \
  "uvicorn" \
  "python-multipart" \
  "fastmcp<2.0" \
  "pydantic<2.10" \
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
RUN chmod +x /a0/start_services.sh

# Set the new entrypoint/command to run both services
CMD ["/initialize_with_persistence.sh", "/a0/start_services.sh"]
