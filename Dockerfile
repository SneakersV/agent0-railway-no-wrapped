FROM agent0ai/agent-zero:v0.9.7
WORKDIR /a0

# (khuyến nghị) cập nhật installer trước
RUN /opt/venv-a0/bin/pip install --no-cache-dir -U "pip<25" "setuptools" "wheel"

RUN /opt/venv-a0/bin/pip uninstall -y numpy scipy scikit-learn

# cài lại đồng bộ + ép cài lại wheel
RUN /opt/venv-a0/bin/pip install --no-cache-dir --force-reinstall -U \
  "numpy>=1.26,<2" \
  "scipy>=1.11,<1.13" \
  "scikit-learn>=1.4,<1.6" \
  "transformers<4.50" \
  "sentence-transformers<3.0" \
  "accelerate<1.0"

# test fail-sớm ngay trong build
RUN /opt/venv-a0/bin/python -c "import numpy; import numpy.core.multiarray as ma; print('numpy ok', numpy.__version__)"
RUN /opt/venv-a0/bin/python -c "import accelerate; print('accelerate ok', accelerate.__version__)"
