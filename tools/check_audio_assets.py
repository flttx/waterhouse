"""Validate shipped audio, retained provenance, loop joins and 4x true peaks."""
from array import array
from pathlib import Path
import hashlib
import json
import math
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "assets/audio/audio_v2_manifest.json"
REPORT_PATH = ROOT / "artifacts/audio-assets-report.json"


def local(reference):
    if not isinstance(reference, str) or not reference.startswith("res://"):
        raise ValueError(f"Invalid asset reference: {reference}")
    path = (ROOT / reference.removeprefix("res://")).resolve()
    if not path.is_relative_to(ROOT.resolve()):
        raise ValueError("Asset path escapes project")
    return path


def run(command):
    return subprocess.run(command, capture_output=True, check=True)


def inspect(reference, loop=False):
    path = local(reference)
    probe = json.loads(run(["ffprobe", "-v", "error", "-select_streams", "a:0",
                            "-show_entries", "stream=sample_rate,channels,duration:format=duration",
                            "-of", "json", str(path)]).stdout)
    stream = probe["streams"][0]
    channels = stream["channels"]
    decoded = run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "pipe:1"]).stdout
    samples = array("f")
    samples.frombytes(decoded)
    frames = len(samples) // channels
    duration = frames / int(stream["sample_rate"])
    sample_peak = max(abs(value) for value in samples)
    analysis = run(["ffmpeg", "-v", "info", "-i", str(path), "-af",
                    "aresample=192000,astats=metadata=0:reset=0", "-f", "null", "-"])
    peaks = re.findall(r"Peak level dB:\s*(-?[\d.]+)", analysis.stderr.decode(errors="replace"))
    if not peaks:
        raise ValueError("FFmpeg supplied no 4x peak measurement")
    true_peak = max(float(value) for value in peaks)
    jump = max(abs(samples[channel] - samples[-channels + channel]) for channel in range(channels))
    window = min(480, frames // 4) * channels
    head_rms = math.sqrt(sum(value * value for value in samples[:window]) / window)
    tail_rms = math.sqrt(sum(value * value for value in samples[-window:]) / window)
    rms = math.sqrt(sum(value * value for value in samples) / len(samples))
    issues = []
    if int(stream["sample_rate"]) != 48000:
        issues.append("sample rate must be 48000")
    if true_peak > -1.0:
        issues.append("4x reconstructed peak exceeds -1 dBTP")
    if loop and jump > 0.045:
        issues.append("loop boundary discontinuity exceeds 0.045 full scale")
    steady_loop = path.stem.startswith("ambient_") or path.stem in ("base", "title", "vent", "submerged", "pump", "gate")
    if loop and steady_loop and min(head_rms, tail_rms) < rms * 0.05:
        issues.append("steady loop loses energy at wrap; do not fade both ends to silence")
    if not samples or rms < 0.00001:
        issues.append("silent or missing audio")
    return {"file": reference, "sample_rate": int(stream["sample_rate"]), "channels": channels,
            "duration": duration, "sample_peak": sample_peak, "true_peak_dbtp_4x": true_peak,
            "loop": loop, "loop_jump": jump, "head_rms_10ms": head_rms,
            "tail_rms_10ms": tail_rms, "rms": rms, "issues": issues}


def main():
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    issues = []
    records = {entry["file"]: entry for entry in manifest["sources"]}
    for entry in records.values():
        path = local(entry["file"])
        if not path.exists():
            issues.append(f"Missing source: {entry['file']}")
            continue
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            issues.append(f"SHA256 mismatch: {entry['file']}")
        if not all(entry.get(key) for key in ("author", "license", "url", "processing")):
            issues.append(f"Incomplete provenance: {entry['file']}")
        if entry["kind"] == "licensed-recording":
            if entry["license"] not in ("CC0-1.0", "CC-BY-3.0"):
                issues.append(f"Unapproved license: {entry['file']}")
            notice = local(entry["license_file"])
            if not notice.exists() or not notice.read_text(encoding="utf-8-sig").strip():
                issues.append(f"Missing license notice: {entry['file']}")
        for parent in entry.get("parents", []):
            if parent not in records:
                issues.append(f"Untracked source parent {parent}")
    expected = {"jump", "land", "climb_start", "climb_end", "hurt", "dive", "surface", "gasp",
                "breath_low", "breath_run", "step_dry_tile", "step_wet_tile", "step_metal", "step_concrete",
                "swim", "swim_fast", "splash", "drip", "vent", "pipe", "stress", "valve", "valve_stop",
                "valve_done", "relay", "pump_start", "pump", "gate", "gate_stop", "pressure_ready",
                "ui_move", "ui_confirm", "ui_locked", "submerged", "heartbeat", "metal"}
    expected |= {"ambient_" + region for region in ("hall", "corridor", "mechanical", "archive", "reservoir", "egress")}
    expected |= {species + "_" + event for species in ("leviathan", "angler", "crab", "whale", "colossus", "hunter", "lurker", "drifter")
                 for event in ("omen", "windup", "hit")}
    for cue in sorted(expected - manifest["cues"].keys()):
        issues.append("Missing cue: " + cue)
    expected_music = {"base", "texture", "pulse", "title", "first_dive", "reservoir", "pump", "egress", "dead", "won"}
    for name in sorted(expected_music - manifest["music"].keys()):
        issues.append("Missing music: " + name)
    assets = []
    for cue, spec in manifest["cues"].items():
        if cue.startswith("step_") and len(spec["files"]) < 4:
            issues.append("Footstep requires four variants: " + cue)
        for reference in spec["files"]:
            if reference not in records:
                issues.append("Missing provenance: " + reference)
            asset = inspect(reference, spec["loop"])
            wanted = 2 if spec["category"] == "environment" else 1
            if asset["channels"] != wanted:
                asset["issues"].append(f"Expected {wanted} channels")
            assets.append(asset)
    for name, reference in manifest["music"].items():
        if reference not in records:
            issues.append("Missing provenance: " + reference)
        asset = inspect(reference, name in ("base", "texture", "pulse", "title", "pump"))
        if asset["channels"] != 2:
            asset["issues"].append("Music must be stereo")
        if name in ("base", "texture", "pulse") and abs(asset["duration"] - 96) > 1 / 48000:
            asset["issues"].append("Music layer must have exactly 96 seconds")
        assets.append(asset)
    for asset in assets:
        issues.extend(asset["file"] + ": " + problem for problem in asset["issues"])
    unique_count = len({asset["file"] for asset in assets})
    report = {"passed": not issues, "cue_count": len(manifest["cues"]), "asset_count": unique_count,
              "asset_reference_count": len(assets),
              "music_count": len(manifest["music"]), "source_count": len(records),
              "measurement": "48 kHz decoded PCM, 4x FFmpeg sinc resampling peak reconstruction",
              "issues": issues, "assets": assets}
    REPORT_PATH.parent.mkdir(exist_ok=True)
    REPORT_PATH.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Audio assets: {unique_count} files, {len(manifest['cues'])} cues, {len(manifest['music'])} music, "
          f"{len(records)} provenance records - {'PASS' if not issues else 'FAIL'}")
    for issue in issues:
        print(issue)
    return 0 if not issues else 1


if __name__ == "__main__":
    sys.exit(main())
