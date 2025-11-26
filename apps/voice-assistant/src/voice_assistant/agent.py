#!/usr/bin/env python3
"""
Voice Assistant Agent for Kubernetes
Detects wake word, transcribes speech using configurable STT backend, publishes to MQTT
"""
import json
import time
import queue
import os
import sounddevice as sd
from vosk import Model, KaldiRecognizer
import paho.mqtt.client as mqtt
from datetime import datetime
import logging

from voice_assistant.stt import get_stt_backend, STTBackend

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# CONFIG from environment
MQTT_BROKER = os.getenv("MQTT_BROKER", "mosquitto.voice-assistant.svc.cluster.local")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_TOPIC = os.getenv("MQTT_TOPIC", "home/voice/commands")

# STT Backend configuration
STT_BACKEND = os.getenv("STT_BACKEND", "vosk").lower()  # vosk, openrouter, groq
VOSK_MODEL_PATH = os.getenv("VOSK_MODEL_PATH", "/models/vosk-model")
STT_API_KEY = os.getenv("STT_API_KEY", "")  # For cloud backends
STT_MODEL = os.getenv("STT_MODEL", "")  # Optional model override

SAMPLE_RATE = int(os.getenv("SAMPLE_RATE", "16000"))
WAKE_PHRASES = os.getenv("WAKE_PHRASES", "hey assistant,hey wolt,ok assistant").split(",")
WAKE_PHRASES = [p.strip().lower() for p in WAKE_PHRASES]
POST_WAKE_RECORD_SECONDS = float(os.getenv("POST_WAKE_RECORD_SECONDS", "3.0"))
USER = os.getenv("USER", "duy")
SOURCE = os.getenv("SOURCE", "k8s-voice-assistant")

# MQTT callbacks
def on_connect(client, userdata, flags, rc):
    if rc == 0:
        logger.info(f"Connected to MQTT broker at {MQTT_BROKER}:{MQTT_PORT}")
    else:
        logger.error(f"Failed to connect to MQTT broker, return code {rc}")

def on_disconnect(client, userdata, rc):
    logger.warning(f"Disconnected from MQTT broker, return code {rc}")
    if rc != 0:
        logger.info("Attempting to reconnect...")

# Setup MQTT
mqttc = mqtt.Client()
mqttc.on_connect = on_connect
mqttc.on_disconnect = on_disconnect

# Audio queue for callback
q = queue.Queue()

def audio_callback(indata, frames, time_info, status):
    """Callback for audio stream"""
    if status:
        logger.warning(f"Audio status: {status}")
    q.put(bytes(indata))

def publish_command(text, confidence=0.0):
    """Publish voice command to MQTT"""
    payload = {
        "user": USER,
        "text": text,
        "confidence": confidence,
        "source": SOURCE,
        "timestamp": datetime.now().isoformat()
    }
    try:
        result = mqttc.publish(MQTT_TOPIC, json.dumps(payload), qos=1)
        if result.rc == mqtt.MQTT_ERR_SUCCESS:
            logger.info(f"Published command: {text}")
        else:
            logger.error(f"Failed to publish command, rc: {result.rc}")
    except Exception as e:
        logger.error(f"Exception publishing to MQTT: {e}")

def main():
    """Main voice assistant loop"""
    logger.info("Starting Voice Assistant Agent")
    logger.info(f"STT Backend: {STT_BACKEND}")
    logger.info(f"Wake phrases: {WAKE_PHRASES}")
    logger.info(f"MQTT: {MQTT_BROKER}:{MQTT_PORT} topic={MQTT_TOPIC}")

    # Connect to MQTT
    try:
        mqttc.connect(MQTT_BROKER, MQTT_PORT, 60)
        mqttc.loop_start()
    except Exception as e:
        logger.error(f"Failed to connect to MQTT broker: {e}")
        return

    # Initialize STT backend for command transcription
    logger.info(f"Initializing STT backend: {STT_BACKEND}")
    try:
        if STT_BACKEND == "vosk":
            stt_backend = get_stt_backend("vosk", vosk_model_path=VOSK_MODEL_PATH)
        elif STT_BACKEND in ["openrouter", "groq"]:
            if not STT_API_KEY:
                logger.error(f"{STT_BACKEND} backend requires STT_API_KEY environment variable")
                return
            stt_backend = get_stt_backend(
                STT_BACKEND,
                api_key=STT_API_KEY,
                model=STT_MODEL if STT_MODEL else None
            )
        else:
            logger.error(f"Unknown STT backend: {STT_BACKEND}")
            return
    except Exception as e:
        logger.error(f"Failed to initialize STT backend: {e}")
        return

    # Load Vosk model for wake word detection (always uses Vosk for speed)
    logger.info(f"Loading Vosk model for wake word detection: {VOSK_MODEL_PATH}")
    try:
        vosk_model = Model(VOSK_MODEL_PATH)
    except Exception as e:
        logger.error(f"Failed to load Vosk model: {e}")
        return

    rec = KaldiRecognizer(vosk_model, SAMPLE_RATE)
    rec.SetWords(True)

    logger.info("Voice assistant ready. Listening for wake phrases...")

    try:
        with sd.RawInputStream(
            samplerate=SAMPLE_RATE,
            blocksize=8000,
            dtype='int16',
            channels=1,
            callback=audio_callback
        ):
            while True:
                data = q.get()

                if rec.AcceptWaveform(data):
                    # Final result
                    res = json.loads(rec.Result())
                    text = res.get("text", "").lower().strip()

                    if text:
                        logger.debug(f"Final result: {text}")

                        # Check for wake phrase
                        for wake in WAKE_PHRASES:
                            if wake in text:
                                logger.info(f"Wake phrase detected: '{wake}' in '{text}'")

                                # Collect audio after wake phrase
                                collected = b""
                                blocks_to_collect = int(
                                    POST_WAKE_RECORD_SECONDS * SAMPLE_RATE / 8000
                                )

                                for _ in range(blocks_to_collect):
                                    collected += q.get()

                                # Transcribe collected audio using configured STT backend
                                final_text = stt_backend.transcribe(collected, SAMPLE_RATE)

                                if final_text:
                                    logger.info(f"Command transcribed: '{final_text}'")
                                    publish_command(final_text, confidence=0.9)
                                else:
                                    logger.warning("No speech detected after wake phrase")

                                break
                else:
                    # Partial result (for faster wake word detection)
                    pr = json.loads(rec.PartialResult())
                    partial = pr.get("partial", "").lower()

                    if partial:
                        # Check for wake phrase in partial results
                        for wake in WAKE_PHRASES:
                            if wake in partial:
                                logger.info(f"Wake phrase detected in partial: '{wake}'")

                                # Collect audio
                                collected = b""
                                blocks_to_collect = int(
                                    POST_WAKE_RECORD_SECONDS * SAMPLE_RATE / 8000
                                )

                                for _ in range(blocks_to_collect):
                                    collected += q.get()

                                # Transcribe using configured STT backend
                                final_text = stt_backend.transcribe(collected, SAMPLE_RATE)

                                if final_text:
                                    logger.info(f"Command transcribed: '{final_text}'")
                                    publish_command(final_text, confidence=0.85)
                                else:
                                    logger.warning("No speech detected after wake phrase")

                                # Reset recognizer after processing wake phrase
                                rec = KaldiRecognizer(vosk_model, SAMPLE_RATE)
                                rec.SetWords(True)
                                break

    except KeyboardInterrupt:
        logger.info("Shutting down voice assistant")
    except Exception as e:
        logger.error(f"Error in main loop: {e}", exc_info=True)
    finally:
        mqttc.loop_stop()
        mqttc.disconnect()
        logger.info("Voice assistant stopped")

if __name__ == "__main__":
    main()
