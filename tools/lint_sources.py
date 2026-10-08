"""Small repository style lint; Godot itself provides the language/type validator."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
issues = []
for folder in ("scripts", "tests", "shaders", "scenes", "tools"):
    for path in (root / folder).rglob("*"):
        if path.suffix not in {".gd", ".gdshader", ".tscn", ".py", ".ps1"}:
            continue
        data = path.read_text(encoding="utf-8")
        for number, line in enumerate(data.splitlines(), 1):
            if line.rstrip() != line:
                issues.append(f"{path.relative_to(root)}:{number}: trailing whitespace")
            if path.parent.name == "scripts" and re.match(r"\s*print\s*\(", line):
                issues.append(f"{path.relative_to(root)}:{number}: production debug print")
            if re.search(r"(?:sk-|api[_-]?key\s*=)\w{16}", line, re.I):
                issues.append(f"{path.relative_to(root)}:{number}: possible embedded credential")
        if not data.endswith("\n"):
            issues.append(f"{path.relative_to(root)}: missing final newline")
if issues:
    print("\n".join(issues))
    sys.exit(1)
print("PASS source style / whitespace / debug-output lint")
