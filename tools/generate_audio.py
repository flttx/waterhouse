"""Deterministic, original offline sound palette. Standard library only.

WAV loops use tapered ends and deliberately different above/below-water spectra.
No downloaded sounds, API calls, voices, or copyrighted recordings.
"""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"
OUT.mkdir(parents=True, exist_ok=True)
TAU = math.tau


def make(name, seconds, fn, stereo=False):
    rng = random.Random(4702 + sum(map(ord, name)))
    low = 0.0
    samples = bytearray()
    for i in range(int(seconds * RATE)):
        t = i / RATE
        n = rng.uniform(-1, 1)
        low = low * 0.96 + n * 0.04
        value = fn(t, n, low)
        fade = min(1.0, t / 0.04, (seconds - t) / 0.08)
        values = value if isinstance(value, tuple) else (value,)
        for v in values:
            samples += struct.pack("<h", int(max(-0.95, min(0.95, v * fade)) * 32767))
    with wave.open(str(OUT / (name + ".wav")), "wb") as wav:
        wav.setnchannels(2 if stereo else 1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(samples)


def facility(t, n, low):
    hum = 0.065 * math.sin(TAU * 50 * t) + 0.027 * math.sin(TAU * 100 * t)
    drone = 0.14 * math.sin(TAU * 32 * t) * (0.7 + 0.2 * math.sin(TAU * t / 16))
    drop_t = t % 2.0
    drop = 0.0 if drop_t > 0.4 else 0.12 * math.sin(TAU * (800 * drop_t - 600 * drop_t**2)) * math.exp(-drop_t * 20)
    hiss = low * 0.33 + n * 0.012
    return (hum + drone + hiss + drop, hum + drone + hiss - drop * 0.3)


def submerged(t, n, low):
    return low * 0.8 + math.sin(TAU * 39 * t) * 0.18 + math.sin(TAU * 61 * t) * 0.04


def leviathan(t, n, low):
    envelope = math.sin(math.pi * t / 5.0) ** 2
    rumble = math.sin(TAU * (42 * t - 1.8 * t * t)) * 0.25
    call = math.sin(TAU * (115 * t - 6 * t * t + 0.2 * math.sin(t * 12))) * 0.12
    return (rumble + call + low * 0.55) * envelope


def heartbeat(t, n, low):
    phase = t % 1.0
    first = math.exp(-phase * 33) * math.sin(TAU * 62 * phase)
    second = 0.0 if phase < 0.26 else math.exp(-(phase - 0.26) * 34) * math.sin(TAU * 49 * (phase - 0.26))
    return 0.65 * (first + second * 0.7)


make("facility", 16, facility, stereo=True)
make("submerged", 12, submerged)
make("leviathan", 5, leviathan)
make("heartbeat", 4, heartbeat)
make("pump", 8, lambda t, n, low: low * 0.5 + math.sin(TAU * 54 * t) * 0.18 + math.sin(TAU * 81 * t) * 0.07 + n * 0.07 * (0.6 + 0.4 * math.sin(TAU * 7 * t)))
make("step", 0.35, lambda t, n, low: (n * 0.48 + math.sin(TAU * 95 * t) * 0.2) * math.exp(-t * 24))
make("swim", 1.2, lambda t, n, low: low * 1.8 * math.sin(math.pi * t / 1.2) ** 2 + n * 0.04)
make("splash", 1.4, lambda t, n, low: (n * 0.42 + low * 0.7) * math.exp(-t * 3))
make("metal", 1.5, lambda t, n, low: sum(math.sin(TAU * f * t) * math.exp(-t * d) * 0.12 for f, d in [(380, 4), (611, 3), (921, 5), (1319, 8)]) + n * 0.12 * math.exp(-t * 30))
make("valve", 2, lambda t, n, low: (n * 0.11 + math.sin(TAU * (233 * t + 4 * math.sin(t * 11))) * 0.13) * (0.6 + 0.4 * math.sin(t * 17)))
make("relay", 1.0, lambda t, n, low: n * 0.25 * math.exp(-t * 30) + math.sin(TAU * 78 * t) * math.exp(-t * 9) * 0.32)
make("gate", 4, lambda t, n, low: (low * 1.0 + n * 0.08 + math.sin(TAU * 84 * t) * 0.17) * math.sin(math.pi * t / 4))
make("alarm", 2, lambda t, n, low: math.sin(TAU * (280 * t + 24 * math.sin(TAU * t / 2))) * 0.23 * math.sin(math.pi * t / 2) ** 2)
print(f"Generated 13 original WAVs: {OUT}")
