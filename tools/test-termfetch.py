#!/usr/bin/env python3
"""Exercise the actual WASI binary under terminalOS's wasm3 harness."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

runner, binary = map(os.path.abspath, sys.argv[1:])
env = {"TERM": "xterm-color", "COLUMNS": "40", "LINES": "24",
       "USER": 'a"b\\c', "TERMFETCH_DEVICE": "phone\x1b[31m\nspoof"}
with tempfile.TemporaryDirectory() as directory:
    def run(*args, **kwargs):
        return subprocess.run([runner, binary, *args], cwd=directory, env=env,
                              capture_output=True, text=True, **kwargs)

    result = run("--json", check=True)
    data = json.loads(result.stdout)
    assert data["Session"] == "terminalOS"
    assert data["User"] == env["USER"]
    assert data["Device"] == "phone?[31m?spoof"
    assert data["Size"] == "40 x 24"
    assert "CPU" not in data and "Git" not in data
    assert "\x1b" not in result.stdout
    host_fields = {"OS": "OS", "KERNEL": "Kernel", "CPU": "CPU",
                   "MEMORY": "Memory", "APP_MEMORY": "App memory", "UPTIME": "Uptime",
                   "DISK": "Disk", "DISPLAY": "Display", "BATTERY": "Battery",
                   "THERMAL": "Thermal", "PACKAGES": "Packages", "APP": "App"}
    for key in host_fields:
        env["TERMFETCH_" + key] = "sample " + key
    data = json.loads(run("--json", check=True).stdout)
    for key, label in host_fields.items():
        assert data[label] == "sample " + key
    git = Path(directory) / ".git"
    git.mkdir()
    (git / "HEAD").write_text("ref: refs/heads/feature/fetch\n")
    assert json.loads(run("--json", check=True).stdout)["Git"] == "feature/fetch"
    (git / "HEAD").write_text("abcdef0123456789abcdef0123456789abcdef01\n")
    assert json.loads(run("--json", check=True).stdout)["Git"] == "abcdef012345 (detached)"
    (git / "HEAD").write_text("ref: refs/heads/bad\x1b[31m\n")
    plain = run("--no-logo", "--no-color", check=True).stdout
    assert "\x1b" not in plain and ">_" not in plain
    assert "Git: bad?[31m" in plain
    assert "\x1b[1;36m" in run("--color", check=True).stdout
    assert "\x1b" not in run(check=True).stdout  # redirected output
    env["NO_COLOR"] = ""
    assert "\x1b" not in run(check=True).stdout
    assert "\x1b" not in run("--color", "--json", check=True).stdout
    assert run("--version", check=True).stdout.strip() == "termfetch 1.0.0"
    assert "Usage:" in run("--help", check=True).stdout
    assert run("--bogus").returncode != 0
    env["SHELL"] = "x" * 10000
    assert len(json.loads(run("--json", check=True).stdout)["Shell"]) == 255
    env.clear()
    assert json.loads(run("--json", check=True).stdout)["Session"] == "terminalOS"

repo = Path(__file__).resolve().parent.parent
entry = next(p for p in json.loads((repo / "index.json").read_text())["packages"]
             if p["name"] == "termfetch")
archive = repo / entry["archive"]
assert entry["sha256"] == hashlib.sha256(archive.read_bytes()).hexdigest()
assert entry["size"] == archive.stat().st_size
with tarfile.open(archive) as tar:
    assert tar.getnames() == entry["files"] == ["termfetch.wasm"]
    member = tar.getmembers()[0]
    assert member.isfile() and member.mode & 0o111
    assert tar.extractfile(member).read() == Path(binary).read_bytes()
print("termfetch: runtime, environment, Git, escaping, CLI and package checks passed")
