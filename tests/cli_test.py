# SPDX-License-Identifier: MIT
"""Exercise the real CLI, reject malformed input and restore the initial settings."""
import json
import subprocess
import sys

binary = sys.argv[1]


def command(*args, expected=0):
    result = subprocess.run([binary, *args], capture_output=True, text=True, timeout=10)
    assert result.returncode == expected, (args, result.returncode, result.stderr)
    return result.stdout


def status():
    return json.loads(command("--status"))


initial = status()
try:
    for args in [("--unknown",), ("--pause", "extra"), ("--status", "extra"),
                 ("--enable-login", "--disable-login"), ("--delay-ms",),
                 *(("--delay-ms", value) for value in
                   ("", "99", "1001", "-300", "+300", "3e2", "300x", "9" * 100))]:
        command(*args, expected=2)
    assert status()["delayMS"] == initial["delayMS"]
    assert status()["enabled"] == initial["enabled"]
    command("--delay-ms", "1000")
    assert status()["delayMS"] == 1000
    command("--pause")
    assert not status()["enabled"]
    command("--resume")
    assert status()["enabled"]
finally:
    command("--delay-ms", str(initial["delayMS"]))
    command("--resume" if initial["enabled"] else "--pause")
print("CLI validation and settings restoration: PASS")
