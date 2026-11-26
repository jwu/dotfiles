#!/usr/bin/env python3
"""Update the SSH machines registered with Herdr Core."""

import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
from threading import Lock


STEPS = ("dotfiles", "pi", "magpie", "herdr")
EXCLUDED = {"martin-vps", "martin-vps-us"}
DIRECTORY = Path(__file__).resolve().parent
OUTPUT_LOCK = Lock()


def log(message):
    with OUTPUT_LOCK:
        print(message, flush=True)


def is_excluded(machine):
    return any(
        value.lower().split("@")[-1].split(".")[0] in EXCLUDED
        for value in (machine.get("name", ""), machine.get("host", ""), machine.get("target", ""))
        if value
    )


@lru_cache(maxsize=4)
def herdr_release(architecture, proxy_port, download):
    curl = ["curl", "-fsSL", "--retry", "2", "--max-time", "30", "--proxy", f"http://127.0.0.1:{proxy_port}"]
    manifest = json.loads(subprocess.check_output([*curl, "https://releases.herdr.dev/core/latest.json"]))
    version = manifest["version"]
    if not download:
        return version, None
    artifact = manifest["targets"][f"linux-{architecture}"]
    archive = subprocess.check_output([*curl, artifact["url"]])
    if hashlib.sha256(archive).hexdigest() != artifact["sha256"]:
        raise ValueError("Herdr download checksum mismatch")
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        return version, bundle.extractfile("herdr-core").read()


def update_without_forwarding(ssh, options, name, results):
    # Some NAS SSH servers refuse reverse forwards. Relay only the standalone Core release.
    probe = """
        PATH="$HOME/.local/bin:$HOME/.pi/agent/bin:$HOME/bin:$PATH"
        for tool in chezmoi pi magpie; do command -v "$tool" >/dev/null && exit 1; done
        for pi in "$HOME"/.nvm/versions/node/*/bin/pi; do [ ! -x "$pi" ] || exit 1; done
        [ ! -d "$HOME/bin/dotfiles/.git" ] || exit 1
        uname -m && herdr-core --version
    """
    detected = subprocess.run([*ssh, probe], capture_output=True, text=True, timeout=15)
    lines = detected.stdout.strip().splitlines()
    if detected.returncode or len(lines) != 2 or lines[0] not in {"x86_64", "aarch64"} or not lines[1].startswith("hc "):
        return results
    for step in STEPS[:-1]:
        results[step] = "ABSENT"
    version, _ = herdr_release(lines[0], options.proxy_port, False)
    if options.mode == "check":
        results["herdr"] = "READY"
    elif lines[1] == f"hc {version}":
        log(f"[{name}] {lines[1]} is current")
        results["herdr"] = "OK"
    else:
        version, binary = herdr_release(lines[0], options.proxy_port, True)
        install = """
            set -eu
            PATH="$HOME/.local/bin:$PATH"
            staged=$(mktemp "$HOME/.local/bin/herdr-fleet.XXXXXXXX")
            trap 'rm -f "$staged"' EXIT
            cat > "$staged"
            chmod 755 "$staged"
            candidate=$("$staged" --version)
            herdr-core update --from "$staged"
            [ "$(herdr-core --version)" = "$candidate" ]
        """
        done = subprocess.run([*ssh, install], input=binary, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        log(f"[{name}] {done.stdout.decode(errors='replace').strip()}")
        results["herdr"] = "OK" if done.returncode == 0 else f"FAILED ({done.returncode})"
    return results


def update_machine(machine, options):
    name = machine["name"]
    results = {step: "NO RESULT" for step in STEPS}
    target = machine.get("target") or ""
    if machine.get("via") or not target or target.startswith("-"):
        return {step: "NO SSH TARGET" for step in STEPS}

    ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=15",
           "-o", "ServerAliveCountMax=3", target]
    try:
        probe = subprocess.run([*ssh, "uname -s"], capture_output=True, text=True, timeout=15)
        if probe.returncode == 255:
            log(f"[{name}] {probe.stderr.strip()}")
            return {step: "UNREACHABLE" for step in STEPS}
        if probe.stdout.strip() in {"Linux", "Darwin"}:
            command = "sh -s"
            source = DIRECTORY / "fleet-update.sh"
            setup = f"mode={options.mode}\nproxy=http://127.0.0.1:{options.remote_port}\n"
        else:
            loader = "& ([ScriptBlock]::Create([Console]::In.ReadToEnd()))"
            encoded = base64.b64encode(loader.encode("utf-16le")).decode("ascii")
            command = f"pwsh.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand {encoded}"
            source = DIRECTORY / "fleet-update.ps1"
            setup = f"$mode = '{options.mode}'\n$proxy = 'http://127.0.0.1:{options.remote_port}'\n"
        forwarded = [*ssh[:-1], "-o", "ExitOnForwardFailure=yes", "-R",
                     f"127.0.0.1:{options.remote_port}:127.0.0.1:{options.proxy_port}", ssh[-1]]
        forwarding_failed = False
        with tempfile.TemporaryFile() as payload:
            payload.write((setup + source.read_text(encoding="utf-8")).encode())
            payload.seek(0)
            with subprocess.Popen([*forwarded, command], stdin=payload, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace") as process:
                for line in process.stdout:
                    if "remote port forwarding failed" in line.lower():
                        forwarding_failed = True
                    parts = line.strip().split(maxsplit=2)
                    if len(parts) == 3 and parts[0] == "FLEET_RESULT" and parts[1] in results:
                        results[parts[1]] = parts[2]
                    else:
                        log(f"[{name}] {line.rstrip()}")
                status = process.wait()
        if forwarding_failed and status == 255 and probe.stdout.strip() == "Linux":
            log(f"[{name}] Checking whether the Herdr-only fallback applies")
            return update_without_forwarding(ssh, options, name, results)
        log(f"[{name}] SSH exit {status}")
        if status and all(value in {"OK", "ABSENT", "READY"} for value in results.values()):
            results["ssh"] = f"EXIT {status}"
    except (OSError, ValueError, KeyError, subprocess.SubprocessError, tarfile.TarError) as error:
        log(f"[{name}] {error}")
    return results


def port(value):
    number = int(value)
    if not 1 <= number <= 65535:
        raise argparse.ArgumentTypeError("expected a TCP port from 1 to 65535")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("machines", nargs="*", help="exact Herdr machine names (default: all registered SSH machines)")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", dest="mode", action="store_const", const="check", help="probe SSH, proxy and installed tools")
    mode.add_argument("--apply", dest="mode", action="store_const", const="apply", help="run all four updates")
    parser.set_defaults(mode="check")
    parser.add_argument("--proxy-port", type=port, default=7890, help="local HTTP proxy port (default: 7890)")
    parser.add_argument("--remote-port", type=port, default=17897, help="temporary remote loopback port (default: 17897)")
    parser.add_argument("--jobs", type=int, default=3, help="parallel SSH sessions (default: 3)")
    options = parser.parse_args()
    if options.jobs < 1:
        parser.error("--jobs must be positive")
    try:
        inventory = json.loads(subprocess.check_output(["hc", "machine", "ls", "--json"], timeout=15))["machines"]
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Could not read the Herdr machine inventory: {error}\n")
    machines = {entry["name"]: entry for entry in inventory if not is_excluded(entry)}
    missing = set(options.machines) - machines.keys()
    if missing:
        parser.error("unknown or excluded machine: " + ", ".join(sorted(missing)))
    names = list(dict.fromkeys(options.machines)) or list(machines)
    if not names:
        parser.error("no registered machines in scope")
    with ThreadPoolExecutor(max_workers=options.jobs) as pool:
        results = list(pool.map(lambda name: update_machine(machines[name], options), names))
    log("\nMachine | " + " | ".join(STEPS))
    for name, result in zip(names, results):
        log(f"{name} | " + " | ".join(result[step] for step in STEPS) + (f" | SSH {result['ssh']}" if "ssh" in result else ""))
    return int(any(value not in {"OK", "ABSENT", "READY"} for result in results for value in result.values()))


if __name__ == "__main__":
    sys.exit(main())
