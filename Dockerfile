# Kế thừa từ image gốc
FROM agent0ai/agent-zero:v0.9.7

WORKDIR /a0

RUN /opt/venv-a0/bin/pip install --no-cache-dir -U \
  "pip<25" "setuptools" "wheel" \
  "numpy<2" \
  "scipy>=1.11,<1.13" \
  "scikit-learn>=1.4,<1.6" \
  "transformers<4.50" \
  "sentence-transformers<3.0"
