FROM nvidia/cuda:12.6.3-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PATH="/opt/flutter/bin:${PATH}"

WORKDIR /workspace

# Install system dependencies, OpenCV, X11/GUI libraries, audio/video tools, and Flutter dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    git \
    wget \
    curl \
    unzip \
    xz-utils \
    zip \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    libgl1-mesa-dev \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    libpulse0 \
    libasound2 \
    espeak \
    espeak-ng \
    libespeak-ng-dev \
    x11-apps \
    lsof \
    && rm -rf /var/lib/apt/lists/*

# Symlink python3 to python and pip3 to pip
RUN ln -sf /usr/bin/python3 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# Upgrade pip
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Install PyTorch with CUDA 12.4 support
RUN pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# Install Python backend dependencies
COPY backend/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt || true
RUN pip install --no-cache-dir fastapi uvicorn sqlalchemy psycopg2-binary python-multipart python-dotenv google-genai pydantic opencv-python insightface onnxruntime-gpu aiortc av pgvector easyocr pymupdf sentence-transformers ultralytics psutil bcrypt pyjwt passlib pyttsx3 websockets faster-whisper openvino lapx kittentts soundfile
RUN pip install --no-cache-dir https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/wheels/llama_cpp_python-0.2.2%2Bcu120-cp310-cp310-manylinux_2_31_x86_64.whl

# Install Flutter SDK
RUN git clone https://github.com/flutter/flutter.git -b stable --depth 1 /opt/flutter && \
    flutter config --enable-web && \
    flutter doctor --suppress-analytics

EXPOSE 8000
EXPOSE 8080

COPY start_services.sh /usr/local/bin/start_services.sh
RUN chmod +x /usr/local/bin/start_services.sh

CMD ["/usr/local/bin/start_services.sh"]
