"""Offline Waterhouse palette: original synthesis plus credited licensed foley.

Python standard library and FFmpeg only. No downloads occur during generation.
The retained source recordings and notices live in assets/audio/v2/source.
"""
from array import array
from pathlib import Path
import hashlib
import json
import math
import random
import subprocess
import wave
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio/v2"
MUSIC = ROOT / "assets/audio/music"
SOURCE = OUT / "source"
RATE = 48000
TAU = math.tau
KENNEY_URL = "https://kenney.nl/assets/impact-sounds"
WATER_URL = "https://opengameart.org/content/water-splashes"
DOWNLOAD_DATE = "2026-10-09"
MANIFEST = {"version": 2, "sample_rate": RATE, "cues": {}, "music": {}, "sources": []}


def run(args, data=None):
    return subprocess.run(args, input=data, check=True, capture_output=True).stdout


def reference(path):
    return "res://" + path.relative_to(ROOT).as_posix()


def source_record(path, kind, parents=None):
    original = kind == "original"
    is_water = kind == "water"
    return {
        "file": reference(path), "kind": "original" if original else "licensed-recording",
        "url": "tools/generate_audio_v2.py" if original else WATER_URL if is_water else KENNEY_URL,
        "license": "Original-project" if original else "CC-BY-3.0" if is_water else "CC0-1.0",
        "author": "The Waterhouse project" if original else "Michel Baradari" if is_water else "Kenney",
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "processing": "deterministic offline synthesis; 48 kHz; peak normalization; loop-only periodic join"
        if original else "unmodified retained source recording"
        if path.is_relative_to(SOURCE) else
        "48 kHz; mono/stereo conversion; pitch/filter/envelope processing; peak normalization; see generator",
        "parents": parents or [], "download_date": None if original else DOWNLOAD_DATE,
        "license_file": reference(SOURCE / ("WATER_LICENSE.txt" if is_water else "KENNEY_LICENSE.txt"))
        if not original else None,
    }


def prepare_sources():
    SOURCE.mkdir(parents=True, exist_ok=True)
    for archive_name, kind in [("kenney_impact-sounds.zip", "kenney"), ("splash.7z", "water")]:
        record = source_record(SOURCE / archive_name, kind)
        record["processing"] = "unmodified archive downloaded directly from original publisher"
        MANIFEST["sources"].append(record)
    with zipfile.ZipFile(SOURCE / "kenney_impact-sounds.zip") as archive:
        notice = archive.read("License.txt").decode("utf-8-sig")
        normalized = "\n".join(line.rstrip() for line in notice.splitlines()).strip() + "\n"
        (SOURCE / "KENNEY_LICENSE.txt").write_bytes(normalized.encode("utf-8"))
        names = [f"footstep_concrete_{i:03}.ogg" for i in range(4)]
        names += [f"impactMetal_light_{i:03}.ogg" for i in range(4)]
        names += [f"impactPlate_light_{i:03}.ogg" for i in range(4)]
        names += ["impactMetal_medium_000.ogg", "impactBell_heavy_000.ogg"]
        for name in names:
            path = SOURCE / name
            path.write_bytes(archive.read("Audio/" + name))
            MANIFEST["sources"].append(source_record(path, "kenney"))
    (SOURCE / "WATER_LICENSE.txt").write_text(
        "Water splashes — Michel Baradari, submitted by qubodup\n"
        "Original source: https://opengameart.org/content/water-splashes\n"
        "License: Creative Commons Attribution 3.0 Unported (CC BY 3.0)\n"
        "https://creativecommons.org/licenses/by/3.0/\n"
        "Legal terms: https://creativecommons.org/licenses/by/3.0/legalcode\n"
        "Downloaded 2026-10-09. Retain this attribution when redistributing.\n"
        "Modified for The Waterhouse: mono conversion, resampling, trim, pitch, filtering,\n"
        "layering, gain and envelopes. No endorsement by the original author is implied.\n",
        encoding="utf-8",
    )
    for path in sorted((SOURCE / "splash").glob("*.wav")):
        MANIFEST["sources"].append(source_record(path, "water"))


def decoded(path, pitch=1.0, cutoff=8000):
    data = run([
        "ffmpeg", "-v", "error", "-i", str(path), "-af",
        f"aresample={RATE},asetrate={int(RATE * pitch)},aresample={RATE},highpass=f=35,lowpass=f={cutoff}",
        "-ac", "1", "-ar", str(RATE), "-f", "f32le", "pipe:1",
    ])
    result = array("f")
    result.frombytes(data)
    return result


def blend_recordings(parts, seconds, gains=None):
    result = array("f", [0.0]) * int(seconds * RATE)
    for part, gain in zip(parts, gains or [1.0] * len(parts)):
        for i, value in enumerate(part[:len(result)]):
            result[i] += value * gain
    return result


def seam(values, channels):
    # Preserve energy at the wrap: blend the final 12 ms towards the opening
    # sequence, rather than fading both ends to silence on every repetition.
    frames = len(values) // channels
    width = min(576, frames // 8)
    for i in range(width):
        weight = 0.5 - 0.5 * math.cos(math.pi * i / max(1, width - 1))
        for channel in range(channels):
            tail = (frames - width + i) * channels + channel
            head = max(0, i - width + 1) * channels + channel
            values[tail] = values[tail] * (1.0 - weight) + values[head] * weight


def save(name, values, channels=1, loop=False, category="world", provenance="original", parents=None, music=False):
    peak = max(abs(value) for value in values) or 1.0
    target = 0.29 if category in ("environment", "music") else 0.46
    gain = target / peak
    frames = len(values) // channels
    if loop:
        seam(values, channels)
    pcm = array("h")
    for index, value in enumerate(values):
        frame = index // channels
        envelope = 1.0 if loop else min(1.0, frame / 192, (frames - frame - 1) / 1440)
        pcm.append(int(max(-0.95, min(0.95, value * gain * max(0.0, envelope))) * 32767))
    folder = MUSIC if music else OUT
    folder.mkdir(parents=True, exist_ok=True)
    extension = ".ogg" if music or category == "environment" else ".wav"
    path = folder / (name + extension)
    if extension == ".wav":
        with wave.open(str(path), "wb") as handle:
            handle.setnchannels(channels)
            handle.setsampwidth(2)
            handle.setframerate(RATE)
            handle.writeframes(pcm.tobytes())
    else:
        run(["ffmpeg", "-y", "-v", "error", "-f", "s16le", "-ar", str(RATE),
             "-ac", str(channels), "-i", "pipe:0", "-c:a", "libvorbis", "-q:a", "5", str(path)], pcm.tobytes())
    MANIFEST["sources"].append(source_record(path, provenance, parents))
    if music:
        MANIFEST["music"][name] = reference(path)
    else:
        cue = name.rsplit("_", 1)[0] if name.rsplit("_", 1)[-1].isdigit() else name
        entry = MANIFEST["cues"].setdefault(cue, {"files": [], "loop": loop, "category": category})
        entry["files"].append(reference(path))


def foley():
    waters = [SOURCE / "splash/splash1.wav", SOURCE / "splash/splash2.wav"]
    for surface in ("dry_tile", "wet_tile", "metal", "concrete"):
        for index in range(4):
            if surface == "metal":
                src = SOURCE / f"impactPlate_light_{index:03}.ogg"
                part = decoded(src, 0.79 + index * 0.025, 5500)
            else:
                src = SOURCE / f"footstep_concrete_{index:03}.ogg"
                part = decoded(src, 1.1 if surface == "dry_tile" else 0.93, 6200 if surface == "dry_tile" else 3900)
            parents = [reference(src)]
            kind = "kenney"
            parts, gains = [part], [1.0]
            if surface == "wet_tile":
                water = waters[index % 2]
                parts.append(decoded(water, 1.45 + index * 0.1, 4500))
                gains.append(0.24)
                parents.append(reference(water))
                kind = "water"
            save(f"step_{surface}_{index}", blend_recordings(parts, 0.65, gains), provenance=kind, parents=parents)
    for cue, pitch, cutoff, seconds in [
        ("swim", 0.85, 2900, 1.1), ("swim_fast", 1.3, 5200, 0.8),
        ("splash", 0.62, 7000, 1.5), ("dive", 0.72, 1700, 1.0),
        ("surface", 1.0, 4900, 1.0), ("drip", 2.1, 6100, 0.6),
    ]:
        for index in range(2):
            src = waters[index]
            save(f"{cue}_{index}", blend_recordings([decoded(src, pitch, cutoff)], seconds),
                 provenance="water", parents=[reference(src)])
    for cue, source, pitch, cutoff, seconds, category in [
        ("climb_start", "impactMetal_light_000.ogg", 0.85, 6500, 0.8, "world"),
        ("climb_end", "impactMetal_light_001.ogg", 0.73, 5500, 0.8, "world"),
        ("land", "footstep_concrete_003.ogg", 0.7, 4900, 0.8, "player"),
        ("jump", "footstep_concrete_000.ogg", 1.2, 3900, 0.5, "player"),
        ("valve", "impactMetal_medium_000.ogg", 0.6, 3800, 1.5, "world"),
        ("valve_stop", "impactMetal_light_002.ogg", 0.9, 5500, 0.6, "world"),
        ("valve_done", "impactBell_heavy_000.ogg", 0.85, 4500, 1.1, "world"),
        ("gate_stop", "impactMetal_medium_000.ogg", 0.46, 3400, 1.2, "world"),
        ("stress", "impactMetal_medium_000.ogg", 0.3, 1800, 2.8, "environment"),
        ("pipe", "impactBell_heavy_000.ogg", 0.32, 1800, 3.0, "environment"),
    ]:
        src = SOURCE / source
        values = blend_recordings([decoded(src, pitch, cutoff)], seconds)
        if category == "environment":
            values = stereo(values)
        save(cue, values, channels=2 if category == "environment" else 1,
             category=category, provenance="kenney", parents=[reference(src)])


def stereo(values):
    result = array("f")
    delay = 311
    for index, value in enumerate(values):
        result.extend((value, values[(index - delay) % len(values)] * 0.94))
    return result


def synth(name, seconds, fn, loop=False, category="world", channels=1):
    rng = random.Random(77011 + sum(map(ord, name)))
    low = 0.0
    values = array("f")
    for index in range(int(seconds * RATE)):
        t = index / RATE
        noise = rng.uniform(-1.0, 1.0)
        low = low * 0.978 + noise * 0.022
        value = fn(t, noise, low)
        if channels == 1:
            values.append(value)
        elif isinstance(value, tuple):
            values.extend(value)
        else:
            values.extend((value, value * 0.97 + 0.013 * math.sin(TAU * 63.0 * t)))
    save(name, values, channels, loop, category)


def bodies_devices():
    for name, seconds, freq in [("gasp", 1.15, 80), ("breath_low", 2.7, 65),
                                 ("breath_run", 2.3, 110), ("hurt", 0.75, 75)]:
        synth(name, seconds, lambda t, n, low, s=seconds, f=freq:
              (low * 1.7 + n * 0.065 + math.sin(TAU * f * t) * 0.08) *
              math.sin(math.pi * min(1.0, t / s)) ** 2, category="player")
    synth("relay", 0.3, lambda t, n, low: (n * 0.1 + math.sin(TAU * 920 * t) * 0.2) * math.exp(-t * 35))
    synth("pump_start", 3.5, lambda t, n, low:
          (math.sin(TAU * (35 * t + 5 * t * t)) * 0.4 + low * 1.1) * min(1.0, t))
    synth("pump", 8, lambda t, n, low:
          math.sin(TAU * 50 * t) * (0.3 + 0.04 * math.sin(TAU * t / 8)) +
          math.sin(TAU * 100 * t) * 0.08 + low * 0.5, loop=True)
    synth("gate", 6, lambda t, n, low:
          low * 1.5 + math.sin(TAU * 72 * t) * 0.16 +
          math.sin(TAU * 320 * t) * 0.055 * (0.7 + math.sin(TAU * 2 * t) * 0.3), loop=True)
    synth("vent", 12, lambda t, n, low:
          low * 2 + math.sin(TAU * 48 * t) * 0.06, loop=True, category="environment", channels=2)
    synth("submerged", 16, lambda t, n, low:
          low * 1.8 + math.sin(TAU * 37 * t) * 0.1 + math.sin(TAU * 62 * t) * 0.04,
          loop=True, category="environment", channels=2)
    synth("heartbeat", 1.6, lambda t, n, low:
          math.sin(TAU * 48 * t) * (math.exp(-((t - 0.12) / 0.065) ** 2) +
          0.7 * math.exp(-((t - 0.35) / 0.065) ** 2)), loop=True, category="player")
    for name, frequency in [("ui_move", 440), ("ui_confirm", 620), ("ui_locked", 170), ("pressure_ready", 290)]:
        synth(name, 0.65, lambda t, n, low, f=frequency:
              math.sin(TAU * f * t) * math.exp(-t * 8) +
              math.sin(TAU * (f * 1.5) * t) * math.exp(-t * 11) * 0.2,
              category="ui" if name.startswith("ui_") else "world")


def environments():
    water = decoded(SOURCE / "splash/splash1.wav", 0.43, 1700)
    metal = decoded(SOURCE / "impactMetal_medium_000.ogg", 0.27, 1800)
    configs = [("hall", 37, 0.17, 0.025), ("corridor", 61, 0.11, 0.04),
               ("mechanical", 50, 0.3, 0.08), ("archive", 73, 0.055, 0.015),
               ("reservoir", 31, 0.23, 0.035), ("egress", 45, 0.13, 0.022)]
    for name, frequency, level, hiss in configs:
        duration = 16
        rng = random.Random(200 + frequency)
        values = array("f")
        low = 0.0
        for index in range(duration * RATE):
            t = index / RATE
            low = low * 0.99 + rng.uniform(-1, 1) * 0.01
            tone = math.sin(TAU * frequency * t) * level * (0.8 + 0.18 * math.sin(TAU * t / duration))
            noise = low * hiss * 4
            event = index % (5 * RATE)
            drop = water[event] * 0.07 if event < len(water) else 0.0
            resonance = metal[index % (11 * RATE)] * 0.035 if index % (11 * RATE) < len(metal) else 0.0
            values.extend((tone + noise + drop + resonance,
                           tone * 0.91 + noise - drop * 0.35 + resonance * 0.6))
        save("ambient_" + name, values, 2, True, "environment", "water",
             [reference(SOURCE / "splash/splash1.wav"), reference(SOURCE / "impactMetal_medium_000.ogg")])


def creatures():
    frequencies = {"leviathan": 32, "angler": 113, "crab": 163, "whale": 43,
                   "colossus": 26, "hunter": 91, "lurker": 67, "drifter": 137}
    for species, frequency in frequencies.items():
        for stage, duration in [("omen", 4.2), ("windup", 1.1), ("hit", 0.8)]:
            def voice(t, noise, low, f=frequency, s=species, kind=stage, d=duration):
                contour = math.sin(math.pi * min(1.0, t / d)) ** 0.7
                chirp = math.sin(TAU * (f * t + (5 if kind == "windup" else -2) * t * t))
                body = chirp * 0.4 + math.sin(TAU * f * 1.011 * t) * 0.23
                breath = low * 1.4
                if s in ("angler", "crab", "hunter"):
                    pulse = (0.5 + 0.5 * math.sin(TAU * (13 if s == "crab" else 7) * t)) ** 8
                    body = body * 0.23 + pulse * (noise * 0.27 + math.sin(TAU * 800 * t) * 0.13)
                if s in ("lurker", "drifter"):
                    body *= 0.22
                    breath *= 1.8
                if s == "whale":
                    body += math.sin(TAU * (150 * t + 18 * t * t)) * 0.13
                if kind == "hit":
                    return (body * 0.3 + low * 2 + noise * 0.2) * math.exp(-t * 5)
                return (body + breath) * contour
            synth(species + "_" + stage, duration, voice)


def music_track(name, seconds, layer, loop=False):
    # Integer-Hz carrier frequencies and phrase periods dividing 96 seconds
    # keep layer boundaries phase coherent. 60 BPM, 4/4, 24 bars per base loop.
    values = array("f")
    carriers = (55, 82.5, 110, 146.66666666666666)
    for index in range(int(seconds * RATE)):
        t = index / RATE
        breath = 0.72 + 0.16 * math.sin(TAU * t / 24)
        if layer == "base":
            left = (math.sin(TAU * 55 * t) * 0.12 + math.sin(TAU * 110 * t) * 0.025 +
                    math.sin(TAU * 82.5 * t) * 0.06) * breath
            right = left * 0.93 + math.sin(TAU * 55.0625 * t) * 0.021
        elif layer == "texture":
            phase = t % 8
            envelope = math.sin(math.pi * phase / 8) ** 3
            pitch = (220, 293.3333333333333, 330, 247.5)[int(t // 24) % 4]
            left = (math.sin(TAU * pitch * t) * 0.055 + math.sin(TAU * pitch * 0.5 * t) * 0.045) * envelope
            right = left * 0.83 + math.sin(TAU * 165 * t) * 0.02 * envelope
        elif layer == "pulse":
            pulse = math.exp(-(t % 1) * 7)
            left = math.sin(TAU * 55 * t) * pulse * 0.1 + math.sin(TAU * 110 * t) * pulse * 0.025
            right = left * 0.97
        else:
            attack = 1.0 if loop else min(1.0, t / 3)
            tail = min(1.0, (seconds - t) / 5) if not loop else 1.0
            color = {"first_dive": 0.89, "reservoir": 0.74, "pump": 1.0,
                     "egress": 1.1224620483, "dead": 0.5, "won": 1.2599210499}.get(name, 1.0)
            left = sum(math.sin(TAU * f * color * t) * g for f, g in zip(carriers, (0.10, 0.07, 0.035, 0.025)))
            if name in ("pump", "egress"):
                left += math.sin(TAU * 55 * t) * math.exp(-(t % (0.5 if name == "egress" else 1)) * 7) * 0.06
            if name == "first_dive":
                left += math.sin(TAU * (220 * t - 2 * t * t)) * 0.023 * math.sin(math.pi * t / seconds)
            left *= attack * tail * breath
            right = left * 0.94 + math.sin(TAU * 220 * color * t) * 0.012 * attack * tail
        values.extend((left, right))
    save(name, values, 2, loop, "music", music=True)


def main():
    prepare_sources()
    foley()
    bodies_devices()
    environments()
    creatures()
    # Decoy feedback shares a licensed impact recording, with world/SFX routing.
    MANIFEST["cues"]["metal"] = dict(MANIFEST["cues"]["gate_stop"])
    MANIFEST["cues"]["metal"]["category"] = "world"
    for name in ("base", "texture", "pulse"):
        music_track(name, 96, name, True)
    for name, seconds, loop in [("title", 32, True), ("first_dive", 16, False),
                                ("reservoir", 24, False), ("pump", 24, True),
                                ("egress", 16, False), ("dead", 5, False), ("won", 20, False)]:
        music_track(name, seconds, "event", loop)
    MANIFEST["music_metadata"] = {"bpm": 60, "beats_per_bar": 4, "layer_duration": 96,
                                  "looped": ["base", "texture", "pulse", "title", "pump"]}
    (ROOT / "assets/audio/audio_v2_manifest.json").write_text(
        json.dumps(MANIFEST, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(MANIFEST['cues'])} cues, {len(MANIFEST['music'])} music tracks; all 48 kHz.")


if __name__ == "__main__":
    main()
