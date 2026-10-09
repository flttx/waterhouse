"""Measure the actual Godot mixer capture; manual listening remains separate."""
import json
from pathlib import Path
import subprocess
import sys

from check_audio_assets import inspect

root = Path(__file__).resolve().parents[1]


def main():
    report = inspect("res://artifacts/audio-mix-preview.wav")
    if report["duration"] < 35 or report["channels"] != 2:
        report["issues"].append("Expected a complete stereo native mixer capture")
    (root / "artifacts/audio-mix-report.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    if report["issues"]:
        print("FAIL mixer capture: " + "; ".join(report["issues"]))
        return 1
    print(f"PASS actual mixer: {report['duration']:.2f}s / "
          f"{report['true_peak_dbtp_4x']:.2f} dBTP / RMS {report['rms']:.5f}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"FAIL mixer analysis: {error}")
        sys.exit(1)
