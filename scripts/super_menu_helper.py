#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

HOME = str(Path.home())
TOKEN_CACHE = Path("/tmp/qs_spotify_token.json")
SEARCH_CACHE = Path("/tmp/qs_spotify_search_cache.json")
QUEUE_FILE = Path(HOME) / ".cache" / "qs_spotify_queue.json"
DAEMON_PID_FILE = Path("/tmp/qs_spotify_queue_daemon.pid")

# Extracted directly from local /opt/spotify/Apps/xpui/xpui-routes-search.js
SPOTIFY_SEARCH_TRACKS_HASH = "b02683192a98dde7966b5e6655a79eeb62713eab703eda9902c932818dd52751"


def notify(title: str, body: str, icon: str = "spotify"):
    try:
        subprocess.Popen(
            ["notify-send", "-a", "Spotify", "-i", icon, title, body],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


# ============================================================================
# 3. ZEN BROWSER HISTORY & LAUNCHER ACTIVITY HISTORY (SMART SUGGESTIONS)
# ============================================================================

HISTORY_FILE = Path(HOME) / ".cache" / "qs_launcher_history.json"
ZEN_PLACES_GLOB = os.path.expanduser("~/.config/zen/*/places.sqlite")


def record_history(item_type: str, text: str, data: str = ""):
    text = text.strip()
    if not text:
        return
    HISTORY_FILE.parent.mkdir(parents=True, exist_ok=True)
    history = []
    if HISTORY_FILE.exists():
        try:
            history = json.loads(HISTORY_FILE.read_text())
        except Exception:
            history = []

    # Update or insert
    updated = False
    for item in history:
        if item.get("type") == item_type and item.get("text") == text:
            item["count"] = item.get("count", 1) + 1
            item["ts"] = time.time()
            if data:
                item["data"] = data
            updated = True
            break
    if not updated:
        history.append({
            "type": item_type,
            "text": text,
            "data": data,
            "count": 1,
            "ts": time.time(),
        })

    # Keep history sorted by ts desc, max 200 items
    history.sort(key=lambda x: x.get("ts", 0), reverse=True)
    history = history[:200]
    try:
        HISTORY_FILE.write_text(json.dumps(history, ensure_ascii=False))
    except Exception:
        pass


def search_zen_history(query: str, limit: int = 5) -> list[dict]:
    import glob
    import sqlite3

    query = query.strip()
    if not query:
        return []

    db_paths = glob.glob(ZEN_PLACES_GLOB)
    if not db_paths:
        return []

    results = []
    try:
        uri = f"file:{db_paths[0]}?immutable=1"
        conn = sqlite3.connect(uri, uri=True, timeout=2)
        cur = conn.cursor()
        like_q = f"%{query}%"
        cur.execute(
            """
            SELECT url, title, visit_count
            FROM moz_places
            WHERE url LIKE 'http%' AND (url LIKE ? OR title LIKE ?)
            ORDER BY visit_count DESC LIMIT ?
            """,
            (like_q, like_q, limit),
        )
        for url, title, count in cur.fetchall():
            results.append({
                "type": "zen_history",
                "url": url,
                "title": title or url,
                "count": count,
            })
    except Exception:
        pass
    return results


def get_spotify_history(is_play: bool = True, query: str = "") -> list[dict]:
    target_type = "spotify_play" if is_play else "spotify_queue"
    items = []
    if not HISTORY_FILE.exists():
        return items
    try:
        history = json.loads(HISTORY_FILE.read_text())
        q = query.strip().lower()
        for h in history:
            if h.get("type") == target_type:
                text = h.get("text", "")
                if not q or q in text.lower():
                    items.append({
                        "text": text,
                        "uri": h.get("data", ""),
                        "count": h.get("count", 1),
                        "ts": h.get("ts", 0),
                    })
    except Exception:
        pass
    items.sort(key=lambda x: (x.get("count", 1), x.get("ts", 0)), reverse=True)
    return items[:10]


def search_suggestions(raw_query: str) -> list[dict]:
    q = raw_query.strip()
    if not q:
        return []
    low_q = q.lower()

    suggestions = []
    seen = set()

    # 1. Check local Launcher history (Spotify song commands, URLs, web searches, shell commands)
    if HISTORY_FILE.exists():
        try:
            history = json.loads(HISTORY_FILE.read_text())
            for h in history:
                text = h.get("text", "")
                htype = h.get("type", "")
                hdata = h.get("data", "")
                if low_q in text.lower() or (hdata and low_q in hdata.lower()):
                    key = (htype, text)
                    if key not in seen:
                        seen.add(key)
                        suggestions.append({
                            "type": htype,
                            "text": text,
                            "data": hdata,
                            "count": h.get("count", 1),
                            "ts": h.get("ts", 0),
                        })
        except Exception:
            pass

    # Sort launcher history matches by count and recency
    suggestions.sort(key=lambda x: (x.get("count", 1), x.get("ts", 0)), reverse=True)

    # 2. Add Zen Browser history matching query
    zen_items = search_zen_history(q, limit=6)
    for z in zen_items:
        key = ("url", z["url"])
        if key not in seen:
            seen.add(key)
            suggestions.append({
                "type": "zen_url",
                "text": z["url"],
                "data": z["title"],
                "count": z["count"],
            })

    return suggestions[:8]


def open_zen_url(url: str):
    record_history("url", url, url)
    subprocess.Popen(["/home/halil/.local/bin/zen-browser", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def open_zen_search(query: str):
    record_history("search", query)
    url = f"https://www.google.com/search?q={urllib.parse.quote(query)}"
    subprocess.Popen(["/home/halil/.local/bin/zen-browser", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def run_shell_command(cmd: str):
    record_history("command", cmd)
    subprocess.Popen(["bash", "-c", cmd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


SHORTCUT_DIRS = {
    "home": "/home/halil",
    "tmp": "/tmp",
    "documents": "/home/halil/Documents",
    "belgeler": "/home/halil/Documents",
    "desktop": "/home/halil/Desktop",
    "masaustu": "/home/halil/Desktop",
    "masaüstü": "/home/halil/Desktop",
    "downloads": "/home/halil/Downloads",
    "indirilenler": "/home/halil/Downloads",
    "windows": "/mnt/windows",
    "config": "/home/halil/.config",
    "obsidian": "/home/halil/Documents/Obsidian/AVDS",
}


def make_file_entry(path_str: str) -> dict | None:
    try:
        p = Path(path_str)
        if not p.exists():
            return None
        is_dir = p.is_dir()
        abs_path = str(p.resolve() if not p.is_symlink() else p)
        display_name = abs_path if abs_path in ("/", "/home", "/tmp", "/mnt") else p.name or abs_path
        return {
            "path": abs_path,
            "name": display_name,
            "is_dir": is_dir,
            "comment": f"📁 {abs_path} — Klasörü Dolphin'de Aç"
            if is_dir
            else f"📄 {abs_path} — Klasöründe Göster (Dolphin)",
            "verb": "Aç" if is_dir else "Klasörde Göster",
        }
    except Exception:
        return None


def search_files(raw_query: str) -> list[dict]:
    q = raw_query.strip()
    if not q.startswith("/"):
        return []

    results = []
    seen = set()

    def add_path(p_str: str):
        norm = os.path.normpath(p_str)
        if norm in seen:
            return
        entry = make_file_entry(norm)
        if entry:
            seen.add(norm)
            results.append(entry)

    stripped = q.lstrip("/").strip()

    # Case 0: Just "/" -> show common directories
    if stripped == "":
        for d in ["/home/halil", "/home", "/tmp", "/home/halil/Documents", "/home/halil/Downloads", "/home/halil/Desktop", "/mnt/windows"]:
            add_path(d)
        return results

    # Case 1: Named shortcut like /home, /tmp, /documents, /downloads, /desktop
    low = stripped.lower()
    if low in SHORTCUT_DIRS:
        # If exact system path like /home or /tmp exists, add it first
        if os.path.exists(q):
            add_path(q)
        add_path(SHORTCUT_DIRS[low])

    # Case 2: Exact filesystem path exists (e.g., /home, /tmp, /mnt/windows, /home/halil/...)
    expanded = os.path.expanduser("~" + q) if not os.path.exists(q) and os.path.exists(os.path.expanduser("~" + q)) else q
    if os.path.exists(expanded):
        add_path(expanded)
        if os.path.isdir(expanded):
            try:
                children = sorted(
                    os.listdir(expanded),
                    key=lambda name: (not os.path.isdir(os.path.join(expanded, name)), name.lower()),
                )
                for child in children:
                    if child.startswith("."):
                        continue
                    add_path(os.path.join(expanded, child))
                    if len(results) >= 12:
                        break
            except Exception:
                pass

    # Case 3: Partial path where parent dir exists (e.g., /home/ha, /mnt/win, /home/halil/Doc)
    for candidate_path in (q, os.path.expanduser("~" + q)):
        parent_dir = os.path.dirname(candidate_path)
        partial_name = os.path.basename(candidate_path).lower()
        if parent_dir and os.path.isdir(parent_dir):
            try:
                children = sorted(
                    os.listdir(parent_dir),
                    key=lambda name: (
                        not name.lower().startswith(partial_name),
                        not os.path.isdir(os.path.join(parent_dir, name)),
                        name.lower(),
                    ),
                )
                for child in children:
                    if not partial_name.startswith(".") and child.startswith("."):
                        continue
                    if partial_name in child.lower():
                        add_path(os.path.join(parent_dir, child))
                        if len(results) >= 12:
                            break
            except Exception:
                pass

    # Case 4: Deep search in /home/halil via `fd` if single token or remaining slots
    if len(results) < 10 and "/" not in stripped and len(stripped) >= 2:
        try:
            fd_out = subprocess.check_output(
                [
                    "fd",
                    "--follow",
                    "--max-depth",
                    "4",
                    "--max-results",
                    "12",
                    "--color",
                    "never",
                    "-i",
                    stripped,
                    HOME,
                ],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=1.5,
            )
            # Prioritize directories first, then files
            lines = [line.strip() for line in fd_out.splitlines() if line.strip()]
            lines.sort(key=lambda p: (not os.path.isdir(p), len(p)))
            for line in lines:
                add_path(line)
                if len(results) >= 12:
                    break
        except Exception:
            pass

    return results[:12]


def open_in_dolphin(target: str):
    target = target.strip()
    if not os.path.exists(target):
        matches = search_files(target if target.startswith("/") else "/" + target)
        if matches:
            target = matches[0]["path"]
        else:
            notify("Dolphin", f"Bulunamadı: {target}", "system-file-manager")
            return

    if os.path.isdir(target):
        subprocess.Popen(["dolphin", target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.Popen(["dolphin", "--select", target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ============================================================================
# 2. SPOTIFY SEARCH, PLAY & QUEUE
# ============================================================================

def get_spotify_token(force_refresh: bool = False) -> str:
    if not force_refresh and TOKEN_CACHE.exists():
        try:
            data = json.loads(TOKEN_CACHE.read_text())
            if time.time() - data.get("ts", 0) < 1800 and data.get("token"):
                return data["token"]
        except Exception:
            pass

    req = urllib.request.Request(
        "https://open.spotify.com/embed/track/2sLAykCWyB1VA5hXDjU59T",
        headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"},
    )
    html = urllib.request.urlopen(req, timeout=5).read().decode("utf-8", errors="ignore")
    m = re.search(r'"accessToken":"([^"]+)"', html)
    if not m:
        raise RuntimeError("Could not obtain Spotify embed token")
    token = m.group(1)
    try:
        TOKEN_CACHE.write_text(json.dumps({"token": token, "ts": time.time()}))
    except Exception:
        pass
    return token


def search_spotify_tracks(song_query: str, limit: int = 6) -> list[dict]:
    song_query = song_query.strip()
    if not song_query:
        return []

    # Check local search cache
    cache = {}
    if SEARCH_CACHE.exists():
        try:
            cache = json.loads(SEARCH_CACHE.read_text())
        except Exception:
            cache = {}

    cache_key = f"{song_query.lower()}:{limit}"
    if cache_key in cache and time.time() - cache[cache_key].get("ts", 0) < 3600:
        return cache[cache_key]["items"]

    tracks = []
    for attempt in range(2):
        try:
            token = get_spotify_token(force_refresh=(attempt == 1))
            variables = {
                "searchTerm": song_query,
                "offset": 0,
                "limit": limit,
                "numberOfTopResults": limit,
                "includeAudiobooks": False,
                "includePreReleases": False,
            }
            extensions = {
                "persistedQuery": {
                    "version": 1,
                    "sha256Hash": SPOTIFY_SEARCH_TRACKS_HASH,
                }
            }
            url = (
                "https://api-partner.spotify.com/pathfinder/v1/query?operationName=searchTracks&variables="
                + urllib.parse.quote(json.dumps(variables))
                + "&extensions="
                + urllib.parse.quote(json.dumps(extensions))
            )
            req = urllib.request.Request(
                url,
                headers={
                    "Authorization": f"Bearer {token}",
                    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0",
                },
            )
            res = json.loads(urllib.request.urlopen(req, timeout=4).read().decode("utf-8"))
            items = res.get("data", {}).get("searchV2", {}).get("tracksV2", {}).get("items", [])
            for it in items:
                tdata = it.get("item", {}).get("data", {})
                uri = tdata.get("uri", "")
                name = tdata.get("name", "")
                if not uri.startswith("spotify:track:") or not name:
                    continue
                artists = ", ".join(
                    a.get("profile", {}).get("name", "")
                    for a in tdata.get("artists", {}).get("items", [])
                    if a.get("profile", {}).get("name")
                )
                album = tdata.get("albumOfTrack", {}).get("name", "")
                tracks.append(
                    {
                        "uri": uri,
                        "name": name,
                        "artists": artists,
                        "album": album,
                        "display": f"{name} — {artists}" if artists else name,
                    }
                )
            break
        except Exception:
            if attempt == 1:
                break

    if tracks:
        try:
            # Keep cache compact
            if len(cache) > 100:
                cache = {}
            cache[cache_key] = {"ts": time.time(), "items": tracks}
            SEARCH_CACHE.write_text(json.dumps(cache))
        except Exception:
            pass

    return tracks


def ensure_spotify_running() -> bool:
    try:
        subprocess.check_output(["pgrep", "-x", "spotify"])
        return True
    except subprocess.CalledProcessError:
        subprocess.Popen(["spotify"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(25):
            time.sleep(0.3)
            try:
                subprocess.check_output(
                    [
                        "dbus-send",
                        "--print-reply",
                        "--dest=org.mpris.MediaPlayer2.spotify",
                        "/org/mpris/MediaPlayer2",
                        "org.freedesktop.DBus.Peer.Ping",
                    ],
                    stderr=subprocess.DEVNULL,
                )
                time.sleep(0.5)
                return True
            except Exception:
                pass
        return False


def spotify_open_uri(uri: str):
    ensure_spotify_running()
    subprocess.run(
        [
            "dbus-send",
            "--print-reply",
            "--dest=org.mpris.MediaPlayer2.spotify",
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player.OpenUri",
            f"string:{uri}",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def play_track(uri: str, display_name: str = ""):
    if display_name:
        record_history("spotify_play", display_name, uri)
    spotify_open_uri(uri)
    if display_name:
        notify("🎵 Şimdi Çalınıyor", display_name)


def ensure_queue_daemon():
    if DAEMON_PID_FILE.exists():
        try:
            pid = int(DAEMON_PID_FILE.read_text().strip())
            os.kill(pid, 0)
            return
        except Exception:
            pass
    subprocess.Popen(
        [sys.executable, __file__, "queue-daemon"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def queue_track(uri: str, display_name: str = ""):
    if display_name:
        record_history("spotify_queue", display_name, uri)
    QUEUE_FILE.parent.mkdir(parents=True, exist_ok=True)
    queue = []
    if QUEUE_FILE.exists():
        try:
            queue = json.loads(QUEUE_FILE.read_text())
        except Exception:
            queue = []
    queue.append({"uri": uri, "display": display_name, "ts": time.time()})
    QUEUE_FILE.write_text(json.dumps(queue))
    ensure_queue_daemon()
    if display_name:
        notify("➕ Sıraya Eklendi", display_name)


def run_queue_daemon():
    import http.server
    import threading

    DAEMON_PID_FILE.write_text(str(os.getpid()))
    lock = threading.Lock()

    class QueueHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def do_GET(self):
            if self.path.startswith("/pop"):
                items = []
                with lock:
                    if QUEUE_FILE.exists():
                        try:
                            items = json.loads(QUEUE_FILE.read_text())
                            if items:
                                QUEUE_FILE.write_text("[]")
                        except Exception:
                            items = []
                payload = json.dumps(items).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            else:
                self.send_response(404)
                self.end_headers()

    try:
        server = http.server.HTTPServer(("127.0.0.1", 29584), QueueHandler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
    except Exception:
        pass

    last_track_id = None
    last_length_sec = 0.0
    last_pos_sec = 0.0
    triggered_for_track = None
    idle_ticks = 0

    while True:
        try:
            with lock:
                if not QUEUE_FILE.exists():
                    queue = []
                else:
                    queue = json.loads(QUEUE_FILE.read_text())

            if not queue:
                idle_ticks += 1
                if idle_ticks > 50:  # Exit after ~30s of empty queue
                    break
                time.sleep(0.6)
                continue
            idle_ticks = 0

            # Read current Spotify status, trackid, length, and position
            out = subprocess.check_output(
                [
                    "playerctl",
                    "-p",
                    "spotify",
                    "metadata",
                    "--format",
                    "{{status}}|{{mpris:trackid}}|{{mpris:length}}|{{position}}",
                ],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
            parts = out.split("|")
            if len(parts) == 4:
                status, track_id, length_us, pos_us = parts
                length_sec = int(length_us) / 1_000_000.0 if length_us.isdigit() else 0.0
                pos_sec = int(pos_us) / 1_000_000.0 if pos_us.isdigit() else 0.0

                should_play_next = False
                # Condition A: Current track is within 1.4s of finishing
                if (
                    status == "Playing"
                    and length_sec > 5.0
                    and (length_sec - pos_sec) <= 1.4
                    and triggered_for_track != track_id
                ):
                    should_play_next = True
                # Condition B: Track automatically changed to another track while we were near the end of previous track
                elif (
                    last_track_id
                    and track_id != last_track_id
                    and last_length_sec > 5.0
                    and (last_length_sec - last_pos_sec) <= 4.0
                    and triggered_for_track != last_track_id
                ):
                    should_play_next = True

                if should_play_next:
                    next_item = None
                    with lock:
                        queue = json.loads(QUEUE_FILE.read_text()) if QUEUE_FILE.exists() else []
                        if queue:
                            next_item = queue.pop(0)
                            QUEUE_FILE.write_text(json.dumps(queue))
                    if next_item:
                        triggered_for_track = next_item["uri"].split(":")[-1]
                        spotify_open_uri(next_item["uri"])
                        if next_item.get("display"):
                            notify("🎵 Sıradaki Şarkı Çalınıyor", next_item["display"])
                        time.sleep(2.5)
                        last_track_id = None
                        continue

                last_track_id = track_id
                last_length_sec = length_sec
                last_pos_sec = pos_sec
        except Exception:
            pass
        time.sleep(0.6)

    try:
        DAEMON_PID_FILE.unlink(missing_ok=True)
    except Exception:
        pass


def main():
    if len(sys.argv) < 2:
        print("[]")
        return

    cmd = sys.argv[1]
    arg = sys.argv[2] if len(sys.argv) > 2 else ""
    arg2 = sys.argv[3] if len(sys.argv) > 3 else ""

    if cmd == "file-search":
        print(json.dumps(search_files(arg), ensure_ascii=False))
    elif cmd == "file-open":
        open_in_dolphin(arg)
    elif cmd == "spotify-search":
        print(json.dumps(search_spotify_tracks(arg), ensure_ascii=False))
    elif cmd == "spotify-play":
        play_track(arg, arg2)
    elif cmd == "spotify-play-query":
        tracks = search_spotify_tracks(arg, limit=1)
        if tracks:
            play_track(tracks[0]["uri"], tracks[0]["display"])
        else:
            notify("Spotify", f"Şarkı bulunamadı: {arg}")
    elif cmd == "spotify-queue":
        queue_track(arg, arg2)
    elif cmd == "spotify-queue-query":
        tracks = search_spotify_tracks(arg, limit=1)
        if tracks:
            queue_track(tracks[0]["uri"], tracks[0]["display"])
        else:
            notify("Spotify", f"Şarkı bulunamadı: {arg}")
    elif cmd == "queue-daemon":
        run_queue_daemon()
    elif cmd == "spotify-history":
        is_play = (arg == "play" or arg == "p")
        print(json.dumps(get_spotify_history(is_play, arg2), ensure_ascii=False))
    elif cmd == "warm-token":
        try:
            get_spotify_token()
        except Exception:
            pass
    elif cmd == "suggestions":
        print(json.dumps(search_suggestions(arg), ensure_ascii=False))
    elif cmd == "record":
        record_history(arg, arg2, sys.argv[4] if len(sys.argv) > 4 else "")
    elif cmd == "open-zen-url":
        open_zen_url(arg)
    elif cmd == "open-zen-search":
        open_zen_search(arg)
    elif cmd == "run-shell":
        run_shell_command(arg)


if __name__ == "__main__":
    main()
