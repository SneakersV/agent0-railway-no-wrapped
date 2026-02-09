FROM agent0ai/agent-zero:v0.9.7
WORKDIR /a0

# Avoid user-site / stray PYTHONPATH interfering with venv imports
ENV PYTHONNOUSERSITE=1
ENV PYTHONPATH=

RUN /opt/venv-a0/bin/pip install --no-cache-dir -U "pip<25" "setuptools" "wheel"

# Install torch/torchvision CPU WITHOUT deps (so it won't upgrade numpy to 2.x) ----
RUN /opt/venv-a0/bin/pip install --no-cache-dir --force-reinstall -U \
  --index-url https://download.pytorch.org/whl/cpu \
  --no-deps \
  "torch==2.3.1" \
  "torchvision==0.18.1"

# cài lại đồng bộ + ép cài lại wheel
RUN /opt/venv-a0/bin/pip install --no-cache-dir --force-reinstall -U \
  "numpy>=1.26,<2" \
  "scipy>=1.11,<1.13" \
  "scikit-learn>=1.4,<1.6"

RUN /opt/venv-a0/bin/pip install --no-cache-dir -U \
  "transformers<4.50" \
  "sentence-transformers<3.0" \
  "accelerate<1.0"

# Install the missing pieces explicitly, pinned to avoid numpy dtype recursion
RUN /opt/venv-a0/bin/pip install --no-cache-dir --force-reinstall -U \
  "timm==1.0.9" \
  "onnx==1.16.1" \
  "ml_dtypes==0.4.0"

# ---- Fail-fast tests during build ----
RUN /opt/venv-a0/bin/python -c "import numpy, torch, torchvision, timm, onnx, ml_dtypes; print('ok', numpy.__version__, torch.__version__, torchvision.__version__, timm.__version__, onnx.__version__, ml_dtypes.__version__)"
RUN /opt/venv-a0/bin/python -c "import numpy; import numpy.core.multiarray as ma; print('numpy ok', numpy.__version__, numpy.__file__)"
RUN /opt/venv-a0/bin/python -c "import scipy, sklearn; print('scipy ok', scipy.__version__, 'sklearn ok', sklearn.__version__)"
RUN /opt/venv-a0/bin/python -c "import torch, torchvision; print('torch ok', torch.__version__, 'torchvision ok', torchvision.__version__)"
RUN /opt/venv-a0/bin/python -c "from torchvision.ops import nms; import torch; b=torch.tensor([[0,0,1,1]],dtype=torch.float32); s=torch.tensor([0.9]); print('nms ok', nms(b,s,0.5))"