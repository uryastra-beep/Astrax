#!/usr/bin/env python3
"""Translator backend for the island (Super+T): translate-shell (`trans`, soimort/translate-shell), no AI.

usage: translate.py <target-lang-code> < text      ->  one JSON line {"ok", "text", "engine"} or {"ok": false, "error"}
Engines are tried in order (google, bing); yandex and apertium failed in testing. Text goes through a temp
file (-i) so a leading "-" can never be read as an option. Input is capped at 2000 characters.
"""
import json, os, subprocess, sys, tempfile

ENGINES = ["google", "bing"]


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "usage"})); return
    target = sys.argv[1]
    text = sys.stdin.read().strip()[:2000]
    if not text:
        print(json.dumps({"ok": False, "error": "empty"})); return
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
        f.write(text)
        path = f.name
    try:
        for engine in ENGINES:
            try:
                r = subprocess.run(["trans", "-e", engine, "-b", "-no-autocorrect", "-t", target, "-i", path],
                                   capture_output=True, text=True, timeout=10)
            except Exception:
                continue
            out = r.stdout.strip()
            if r.returncode == 0 and out and "[ERROR]" not in out and "Oops" not in out:
                print(json.dumps({"ok": True, "text": out, "engine": engine})); return
        print(json.dumps({"ok": False, "error": "no engine answered"}))
    finally:
        os.unlink(path)


main()
