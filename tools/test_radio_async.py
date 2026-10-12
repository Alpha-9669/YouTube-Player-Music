"""Test the built DLL ABI: importing radio music never waits for the network."""
import ctypes
import os
from pathlib import Path
import time
import sys

sys.stdout.reconfigure(encoding="utf-8")

root = Path(__file__).resolve().parents[1]
mod = root / "mod" / "@YouTube Player Music"
os.chdir(mod)
dll = ctypes.WinDLL(str(mod / "youtube_player_music_x64.dll"))
extension = dll.RVExtension
extension.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p]
latencies = []

def call(command):
    output = ctypes.create_string_buffer(4096)
    before = time.perf_counter()
    extension(output, len(output), command.encode())
    elapsed = time.perf_counter() - before
    latencies.append(elapsed)
    assert elapsed < 0.250, f"Main-thread call blocked for {elapsed:.3f}s: {command}"
    return output.value.decode("utf-8")

def start(url, playlist=False):
    response = call(f"radioload|{url}|{int(playlist)}")
    assert response.startswith("ok|radioloadqueued|"), response
    return response.rsplit("|", 1)[1]

urls = ["https://www.youtube.com/watch?v=f50r2QKdkus", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"]
tokens = []
try:
    tokens = [start(url) for url in urls]
    playlist = start("https://www.youtube.com/playlist?list=PLgULlLHTSGISMiG9fB3jIEOabgXOZNAB6", True)
    tokens.append(playlist)
    cancelled = start(urls[0])
    assert call(f"radioloadrelease|{cancelled}") == "ok|radioloadreleased"
    assert call(f"radioloadstatus|{cancelled}") == "err|radio_load_missing"
    assert call("radioloadstatus|garbage") == "err|invalid_radio_load_token"
    pending = set(tokens)
    deadline = time.monotonic() + 90
    counts = {}
    while pending and time.monotonic() < deadline:
        for token in list(pending):
            response = call(f"radioloadstatus|{token}")
            if response.startswith("ok|radioload|ready|"):
                counts[token] = int(response.rsplit("|", 1)[1])
                pending.remove(token)
            else:
                assert response == "ok|radioload|pending", response
            assert call("radiostatus|async_probe") == "ok|radio|missing"
        time.sleep(0.2)
    assert not pending, f"Metadata timeout: {pending}"
    for token, url in zip(tokens[:2], urls):
        response = call(f"radioloaditem|{token}|0").split("|")
        assert response[:3] == ["ok", "radioloaditem", url], response
        assert response[3] and response[3] != url, response
        assert counts[token] == 1
        print("Title:", response[3])
    assert 1 <= counts[playlist] <= 32, counts
    for index in range(counts[playlist]):
        item = call(f"radioloaditem|{playlist}|{index}").split("|")
        assert item[:2] == ["ok", "radioloaditem"] and item[2].startswith("https://") and item[3], item
    assert call(f"radioloaditem|{playlist}|999") == "err|radio_load_item_missing"
    print(f"PASS: concurrent titles + {counts[playlist]} playlist tracks, cancellation, isolated requests; max ABI latency {max(latencies)*1000:.1f} ms")
finally:
    for token in tokens:
        call(f"radioloadrelease|{token}")
