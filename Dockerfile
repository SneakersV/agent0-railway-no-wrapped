FROM agent0ai/agent-zero:v0.9.7
WORKDIR /a0

# Modify requirements.txt to prevent runtime re-installation of vision packages
RUN [ -f requirements.txt ] && sed -i '/timm/d' requirements.txt && \
  sed -i '/torchvision/d' requirements.txt && \
  sed -i '/onnx/d' requirements.txt || true

ENV PYTHONNOUSERSITE=1
ENV PYTHONPATH=

RUN /opt/venv-a0/bin/pip install --no-cache-dir -U "pip<25" "setuptools" "wheel"

# Pin numpy early (avoid accidental numpy 2.x upgrades)
RUN /opt/venv-a0/bin/pip install --no-cache-dir --force-reinstall -U "numpy>=1.26,<2"

# Install torch CPU only (NO torchvision)
RUN /opt/venv-a0/bin/pip install --no-cache-dir --force-reinstall -U \
  --index-url https://download.pytorch.org/whl/cpu \
  --no-deps \
  "torch==2.3.1"

# Core libs
RUN /opt/venv-a0/bin/pip install --no-cache-dir --force-reinstall -U \
  "scipy>=1.11,<1.13" \
  "scikit-learn>=1.4,<1.6"

# NLP stack
RUN /opt/venv-a0/bin/pip install --no-cache-dir --force-reinstall -U \
  "transformers<4.50" \
  "sentence-transformers<3.0" \
  "accelerate<1.0"

# Remove vision/onnx stack at the END (in case something re-pulled it)
RUN /opt/venv-a0/bin/pip uninstall -y torchvision timm onnx onnxruntime ml_dtypes || true

# ---- Fail-fast tests during build ----
RUN /opt/venv-a0/bin/python -c "import numpy; print('numpy ok', numpy.__version__, numpy.__file__)"
RUN /opt/venv-a0/bin/python -c "import scipy, sklearn; print('scipy ok', scipy.__version__, 'sklearn ok', sklearn.__version__)"
RUN /opt/venv-a0/bin/python -c "import torch; print('torch ok', torch.__version__)"

# Ensure problematic packages are NOT present
RUN /opt/venv-a0/bin/python -c "import importlib.util as u; assert u.find_spec('torchvision') is None, 'torchvision still installed'"
RUN /opt/venv-a0/bin/python -c "import importlib.util as u; assert u.find_spec('timm') is None, 'timm still installed'"
RUN /opt/venv-a0/bin/python -c "import importlib.util as u; assert u.find_spec('onnx') is None, 'onnx still installed'"
RUN /opt/venv-a0/bin/python -c "import importlib.util as u; assert u.find_spec('ml_dtypes') is None, 'ml_dtypes still installed'"
