FROM agent0ai/agent-zero:v0.9.7
WORKDIR /a0

# (khuyến nghị) cập nhật installer trước
RUN /opt/venv-a0/bin/pip install --no-cache-dir -U "pip<25" "setuptools" "wheel"

# cài lại đồng bộ + ép cài lại wheel
RUN /opt/venv-a0/bin/pip install --no-cache-dir -U \
  "numpy>=1.26,<2" \
  "scipy>=1.11,<1.13" \
  "scikit-learn>=1.4,<1.6" \
  "transformers<4.50" \
  "sentence-transformers<3.0" \
  "accelerate<1.0"

# Chỉ ép lại các gói gây lỗi (nhanh hơn nhiều)
RUN /opt/venv-a0/bin/pip install --no-cache-dir --force-reinstall \
  --index-url https://download.pytorch.org/whl/cpu \
  "torch==2.3.1" "torchvision==0.18.1"

# test fail-sớm ngay trong build
RUN /opt/venv-a0/bin/python -c "import numpy; import numpy.core.multiarray as ma; print('numpy ok', numpy.__version__)"
RUN /opt/venv-a0/bin/python -c "import accelerate; print('accelerate ok', accelerate.__version__)"
RUN /opt/venv-a0/bin/python -c "import numpy; print(numpy.__version__, numpy.__file__)"
RUN /opt/venv-a0/bin/python -c "import torch, torchvision; print(torch.__version__, torchvision.__version__)"
RUN /opt/venv-a0/bin/python -c "from torchvision.ops import nms; import torch; b=torch.tensor([[0,0,1,1]],dtype=torch.float32); s=torch.tensor([0.9]); print('nms ok', nms(b,s,0.5))"