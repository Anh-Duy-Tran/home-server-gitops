FROM python:3.11-slim AS base

# Install system dependencies for audio processing
RUN apt-get update && apt-get install -y \
    portaudio19-dev \
    libsndfile1 \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Set working directory
WORKDIR /app

# Copy project files
COPY pyproject.toml ./
COPY src/ ./src/

# Install dependencies using uv
RUN uv pip install --system --no-cache .

# Download Vosk model (small English model ~40MB)
RUN mkdir -p /models && \
    cd /models && \
    wget -q https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip && \
    unzip vosk-model-small-en-us-0.15.zip && \
    mv vosk-model-small-en-us-0.15 vosk-model && \
    rm vosk-model-small-en-us-0.15.zip

# Run as non-root user
RUN useradd -m -u 1000 voiceuser && \
    chown -R voiceuser:voiceuser /app /models

USER voiceuser

# Set environment defaults
ENV MQTT_BROKER=mosquitto.voice-assistant.svc.cluster.local \
    MQTT_PORT=1883 \
    MQTT_TOPIC=home/voice/commands \
    VOSK_MODEL_PATH=/models/vosk-model \
    SAMPLE_RATE=16000 \
    WAKE_PHRASES="hey assistant,hey wolt,ok assistant" \
    POST_WAKE_RECORD_SECONDS=3.0 \
    USER=duy \
    SOURCE=k8s-voice-assistant

# Run the voice agent
CMD ["voice-agent"]
