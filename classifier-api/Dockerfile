FROM python:3.10-slim

# Avoid Python buffering issues
ENV PYTHONUNBUFFERED=1

# Install system deps (needed for torch/transformers sometimes)
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps first (better layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app
COPY main.py .

# Create model cache dir
RUN mkdir -p /models

# Environment variables for HuggingFace cache
ENV TRANSFORMERS_CACHE=/models
ENV HF_HOME=/models

# Expose port
EXPOSE 8000

# Run server
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8002"]
