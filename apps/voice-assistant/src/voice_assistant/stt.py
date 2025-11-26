"""
Speech-to-Text abstraction layer supporting multiple backends.
"""
import logging
import os
import io
import wave
from abc import ABC, abstractmethod
from typing import Optional

logger = logging.getLogger(__name__)


class STTBackend(ABC):
    """Abstract base class for STT backends."""

    @abstractmethod
    def transcribe(self, audio_data: bytes, sample_rate: int = 16000) -> Optional[str]:
        """
        Transcribe audio data to text.

        Args:
            audio_data: Raw PCM audio bytes (int16)
            sample_rate: Audio sample rate in Hz

        Returns:
            Transcribed text or None if transcription failed
        """
        pass


class VoskSTT(STTBackend):
    """Local Vosk STT backend (offline, fast, moderate accuracy)."""

    def __init__(self, model_path: str):
        """Initialize Vosk STT with model path."""
        from vosk import Model, KaldiRecognizer
        import json

        self.model = Model(model_path)
        self.sample_rate = 16000
        logger.info(f"Initialized Vosk STT with model: {model_path}")

    def transcribe(self, audio_data: bytes, sample_rate: int = 16000) -> Optional[str]:
        """Transcribe using Vosk."""
        from vosk import KaldiRecognizer
        import json

        try:
            rec = KaldiRecognizer(self.model, sample_rate)
            rec.SetWords(True)
            rec.AcceptWaveform(audio_data)
            result = json.loads(rec.Result())
            text = result.get("text", "").strip()
            return text if text else None
        except Exception as e:
            logger.error(f"Vosk transcription failed: {e}")
            return None


class GroqWhisperSTT(STTBackend):
    """
    Cloud-based Whisper STT via Groq (very fast, high accuracy, generous free tier).

    Groq provides ultra-fast inference with Whisper large-v3.
    Free tier: 10,000 requests/month (as of 2025)
    """

    def __init__(self, api_key: str, model: str = "whisper-large-v3"):
        """Initialize Groq Whisper STT."""
        self.api_key = api_key
        self.model = model
        self.base_url = "https://api.groq.com/openai/v1"
        logger.info(f"Initialized Groq Whisper STT with model: {model}")

    def transcribe(self, audio_data: bytes, sample_rate: int = 16000) -> Optional[str]:
        """Transcribe using Groq Whisper API."""
        import requests

        try:
            # Convert raw PCM to WAV format
            wav_buffer = io.BytesIO()
            with wave.open(wav_buffer, 'wb') as wav_file:
                wav_file.setnchannels(1)  # Mono
                wav_file.setsampwidth(2)  # 16-bit
                wav_file.setframerate(sample_rate)
                wav_file.writeframes(audio_data)

            wav_buffer.seek(0)

            headers = {
                "Authorization": f"Bearer {self.api_key}",
            }

            files = {
                "file": ("audio.wav", wav_buffer, "audio/wav"),
                "model": (None, self.model),
            }

            response = requests.post(
                f"{self.base_url}/audio/transcriptions",
                headers=headers,
                files=files,
                timeout=10
            )

            if response.status_code == 200:
                result = response.json()
                text = result.get("text", "").strip()
                logger.debug(f"Groq transcription: {text}")
                return text if text else None
            else:
                logger.error(f"Groq API error: {
                             response.status_code} - {response.text}")
                return None

        except Exception as e:
            logger.error(f"Groq transcription failed: {e}")
            return None


def get_stt_backend(
    backend_type: str = "vosk",
    vosk_model_path: Optional[str] = None,
    api_key: Optional[str] = None,
    model: Optional[str] = None
) -> STTBackend:
    """
    Factory function to create STT backend.

    Args:
        backend_type: One of "vosk", "groq"
        vosk_model_path: Path to Vosk model (for backend_type="vosk")
        api_key: API key (for cloud backends)
        model: Model name (optional, uses defaults)

    Returns:
        STTBackend instance

    Raises:
        ValueError: If backend_type is invalid or required params missing
    """
    backend_type = backend_type.lower()

    if backend_type == "vosk":
        if not vosk_model_path:
            raise ValueError("vosk_model_path required for Vosk backend")
        return VoskSTT(vosk_model_path)

    elif backend_type == "groq":
        if not api_key:
            raise ValueError("api_key required for Groq backend")
        model = model or "whisper-large-v3"
        return GroqWhisperSTT(api_key, model)

    else:
        raise ValueError(
            f"Invalid backend_type: {backend_type}. "
            f"Choose from: vosk, groq"
        )
