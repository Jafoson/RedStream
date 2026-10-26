"""Clicks through the Android app on the CI emulator and takes screenshots.

Talks to the emulator with adb (uiautomator dumps to find things by their
text / content description). The demo backend (demo_server.py) runs on the
CI host, which the emulator reaches as 10.0.2.2.

    RS_HOME=<server HOME> python android/ci/drive.py <out-dir>
"""

import os
import re
import subprocess
import sys
import time
import traceback
import xml.etree.ElementTree as ET
from pathlib import Path

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "shots")
OUT.mkdir(parents=True, exist_ok=True)
SERVER = "http://10.0.2.2:8080"
PKG = "de.redstream.app"
failures = []


def adb(*args, capture=False, check=False):
    cmd = ["adb", *args]
    if capture:
        return subprocess.run(cmd, capture_output=True, check=check).stdout
    subprocess.run(cmd, check=check)


def nodes():
    for _ in range(3):
        adb("shell", "uiautomator", "dump", "/sdcard/ui.xml", capture=True)
        raw = adb("exec-out", "cat", "/sdcard/ui.xml", capture=True)
        try:
            root = ET.fromstring(raw)
            break
        except ET.ParseError:
            time.sleep(1)
    else:
        return []
    out = []
    for n in root.iter("node"):
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds", ""))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        out.append({
            "text": n.get("text", ""), "desc": n.get("content-desc", ""), "cls": n.get("class", ""),
            "x": (x1 + x2) // 2, "y": (y1 + y2) // 2, "area": (x2 - x1) * (y2 - y1),
        })
    return out


def visible_texts():
    return [n["text"] or n["desc"] for n in nodes() if n["text"] or n["desc"]]


def find(label, exact=False, cls=None):
    for n in nodes():
        if cls and n["cls"] != cls:
            continue
        for value in (n["text"], n["desc"]):
            if value and (value == label if exact else label.lower() in value.lower()):
                return n
    return None


def wait_for(label, timeout=30, exact=False):
    end = time.time() + timeout
    while time.time() < end:
        n = find(label, exact=exact)
        if n:
            return n
        time.sleep(1)
    raise RuntimeError(f"'{label}' not on screen after {timeout}s; visible: {visible_texts()[:40]}")


def tap(n):
    adb("shell", "input", "tap", str(n["x"]), str(n["y"]))


def tap_text(label, timeout=20, exact=False):
    tap(wait_for(label, timeout, exact))


def type_text(text):
    adb("shell", "input", "text", text.replace(" ", "%s"))


def key(code):
    adb("shell", "input", "keyevent", str(code))


def swipe_up():
    adb("shell", "input", "swipe", "540", "1700", "540", "700", "400")


def shot(name):
    data = adb("exec-out", "screencap", "-p", capture=True)
    (OUT / f"{name}.png").write_bytes(data)
    print(f"screenshot {name} ({len(data)} bytes)", flush=True)


def step(name, fn):
    print(f"--- {name}", flush=True)
    try:
        fn()
    except Exception as e:
        failures.append(f"{name}: {e}")
        print(f"FAILED {name}: {e}", flush=True)
        traceback.print_exc()
        shot(f"zz_error_{name}")


def cli(*args):
    env = {**os.environ, "HOME": os.environ["RS_HOME"]}
    return subprocess.run(["aniworld", *args], capture_output=True, text=True, env=env).stdout


# ── the walk-through ─────────────────────────────────────────────────────────

def setup():
    # Android's one-time "Viewing full screen" hint would cover the player.
    adb("shell", "settings", "put", "secure", "immersive_mode_confirmations", "confirmed")
    adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    wait_for("Verbinden", 60)
    time.sleep(1)
    shot("01_einrichtung")
    tap(wait_for("Server-Adresse"))
    time.sleep(1)
    type_text(SERVER)
    key(111)  # hide keyboard (ESC)
    time.sleep(1)
    tap_text("Verbinden", exact=True)
    wait_for("Zugriff angefragt", 30)
    time.sleep(1)
    shot("02_freigabe_code")


def approve():
    listing = cli("--web-requests")
    print(listing, flush=True)
    pending = [line.split()[0] for line in listing.splitlines() if " pending " in f" {line} " and line.split()[0].isdigit()]
    if not pending:
        raise RuntimeError("no pending request")
    print(cli("--web-approve", pending[0]), flush=True)
    wait_for("Wer schaut?", 30)
    time.sleep(1)
    shot("03_profilauswahl")
    tap_text("Standard", exact=True)


def home():
    wait_for("Weiterschauen", 30)
    time.sleep(4)  # posters
    shot("04_start")
    swipe_up()
    time.sleep(2)
    shot("05_start_leisten")


def detail():
    tap_text("Start", exact=True)
    time.sleep(1)
    tap_text("Dandadan", exact=True)
    wait_for("Staffel 1", 30)
    time.sleep(3)
    shot("06_detail")
    swipe_up()
    time.sleep(2)
    shot("07_detail_folgen")


def player():
    tap_text("Folge 4", exact=True)
    time.sleep(12)
    hint = find("Got it", exact=True)
    if hint:
        tap(hint)
        time.sleep(1)
    shot("08_player")
    adb("shell", "input", "tap", "1000", "500")
    time.sleep(1)
    shot("09_player_steuerung")
    key(4)  # back
    time.sleep(3)


def browse():
    tap_text("Entdecken", exact=True)
    time.sleep(4)
    shot("10_entdecken")
    tap_text("Serien", exact=True)
    time.sleep(3)
    shot("11_entdecken_serien")


def search():
    tap_text("Suche", exact=True)
    time.sleep(1)
    tap(wait_for("Titel suchen"))
    type_text("o")
    key(66)  # enter
    time.sleep(4)
    shot("12_suche")


def watchlist():
    tap_text("Meine Liste", exact=True)
    time.sleep(4)
    shot("13_meine_liste")


def cast():
    tap_text("Start", exact=True)
    time.sleep(1)
    tap(wait_for("Auf TV abspielen"))
    wait_for("TV Wohnzimmer", 20)
    time.sleep(1)
    shot("14_tv_auswahl")
    tap_text("TV Wohnzimmer")
    time.sleep(4)
    shot("15_fernbedienung")
    tap_text("Breaking Bad", exact=True)
    wait_for("Staffel 1", 30)
    time.sleep(2)
    swipe_up()
    time.sleep(1)
    tap_text("Folge 3", exact=True)
    time.sleep(2)
    shot("16_auf_tv_gestartet")


def more():
    tap_text("Mehr", exact=True)
    time.sleep(2)
    shot("17_mehr")


for name, fn in [("setup", setup), ("approve", approve), ("home", home), ("detail", detail), ("player", player),
                 ("browse", browse), ("search", search), ("watchlist", watchlist), ("cast", cast), ("more", more)]:
    step(name, fn)

print("FAILURES:", failures if failures else "none", flush=True)
