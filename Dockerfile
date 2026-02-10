FROM agent0ai/agent-zero:v0.9.7
ARG CACHE_BUST=0
RUN echo "CACHE_BUST=$CACHE_BUST"

WORKDIR /a0

ENV PYTHONNOUSERSITE=1
ENV PYTHONPATH=

# Upgrade build tooling
RUN /opt/venv-a0/bin/python -m pip install --no-cache-dir -U "pip<25" "setuptools" "wheel"

# 1) Remove problematic preinstalled compiled stack first (avoid mixing ABIs)
RUN /opt/venv-a0/bin/python -m pip uninstall -y \
  numpy scipy scikit-learn transformers accelerate sentence-transformers \
  torchvision timm onnx onnxruntime ml_dtypes \
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
  "numpy<2"

# ------------------------------------------------------------
# FIX: Enable FAISS <-> torch Tensor compatibility globally
# (prevents: ValueError: input not a numpy array)
# ------------------------------------------------------------
RUN /opt/venv-a0/bin/python - <<'PY'
import site, os
sp = site.getsitepackages()[0]
path = os.path.join(sp, "sitecustomize.py")
with open(path, "w", encoding="utf-8") as f:
    f.write(
        "try:\n"
        "    import faiss\n"
        "    import faiss.contrib.torch_utils\n"
        "except Exception:\n"
        "    pass\n"
    )
print("Wrote", path)
PY