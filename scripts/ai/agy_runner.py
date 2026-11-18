#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from pathlib import Path

AGY_BIN = "/home/halil/.local/bin/agy"
STATE_DIR = Path("/tmp/quickshell/ai")
CONV_FILE = STATE_DIR / "agy_conversation_id.txt"


def list_models():
    """Return all models from `agy models` as JSON array."""
    try:
        out = subprocess.check_output([AGY_BIN, "models"], text=True, stderr=subprocess.DEVNULL, timeout=5)
        models = []
        for line in out.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split(None, 1)
            model_id = parts[0]
            display_name = parts[1].strip() if len(parts) > 1 else model_id
            models.append({"id": model_id, "name": display_name})
        print(json.dumps(models, ensure_ascii=False))
    except Exception:
        print("[]")


def run_prompt(model: str, prompt: str, attached_file: str = ""):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if attached_file and os.path.exists(attached_file):
        prompt = f"[Ekli Dosya: {attached_file}]\n\n{prompt}"

    conv_id = ""
    if CONV_FILE.exists():
        try:
            conv_id = CONV_FILE.read_text().strip()
        except Exception:
            conv_id = ""

    def spawn_agy(use_conv: str):
        cmd = [
            AGY_BIN,
            "--model",
            model,
            "--output-format",
            "stream-json",
            "--dangerously-skip-permissions",
            "--disable-slash-commands",
        ]
        if use_conv:
            cmd.extend(["--conversation", use_conv])
        cmd.extend(["-p", prompt])
        return subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            cwd=str(Path.home()),
        )

    proc = spawn_agy(conv_id)
    got_output = False
    for raw_line in proc.stdout:
        line = raw_line.strip()
        if not line:
            continue
        got_output = True
        try:
            ev = json.loads(line)
            if ev.get("event") == "init" and ev.get("conversation_id"):
                CONV_FILE.write_text(ev["conversation_id"])
        except Exception:
            pass
        print(line, flush=True)

    ret = proc.wait()
    # If resuming an old conversation_id failed without output, retry fresh
    if ret != 0 and conv_id and not got_output:
        try:
            CONV_FILE.unlink(missing_ok=True)
        except Exception:
            pass
        proc2 = spawn_agy("")
        for raw_line in proc2.stdout:
            line = raw_line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
                if ev.get("event") == "init" and ev.get("conversation_id"):
                    CONV_FILE.write_text(ev["conversation_id"])
            except Exception:
                pass
            print(line, flush=True)
        proc2.wait()


def main():
    if len(sys.argv) < 2:
        return
    cmd = sys.argv[1]
    if cmd == "models":
        list_models()
    elif cmd == "reset":
        try:
            CONV_FILE.unlink(missing_ok=True)
        except Exception:
            pass
    elif cmd == "run":
        model = sys.argv[2] if len(sys.argv) > 2 else "gemini-4-argon-medium"
        prompt = sys.argv[3] if len(sys.argv) > 3 else ""
        attached = sys.argv[4] if len(sys.argv) > 4 else ""
        run_prompt(model, prompt, attached)


if __name__ == "__main__":
    main()
