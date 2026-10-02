"""Exercise two independent radio channels through the x64 extension ABI."""

import argparse
import ctypes
import os
import time
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--extension",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "mod"
        / "@YouTube Player Music"
        / "youtube_player_music_x64.dll",
    )
    parser.add_argument(
        "--url", default="https://www.youtube.com/watch?v=f50r2QKdkus"
    )
    parser.add_argument("--timeout", type=int, default=60)
    args = parser.parse_args()
    dll_path = args.extension.resolve()
    os.chdir(dll_path.parent)
    dll = ctypes.WinDLL(str(dll_path))
    extension = dll.RVExtension
    extension.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p]
    extension.restype = None

    def call(command: str) -> str:
        output = ctypes.create_string_buffer(4096)
        extension(output, len(output), command.encode("utf-8"))
        result = output.value.decode("utf-8", errors="replace")
        print(f"{command} => {result}", flush=True)
        return result

    assert call("radiostatus|car_1") == "ok|radio|missing"
    try:
        assert call(f"radioplay|car_1|{args.url}|0") == "ok|radio_queued"
        assert call(f"radioplay|heli_2|{args.url}|5000") == "ok|radio_queued"
        assert call("radiovolume|car_1|0|-100") == "ok|radio_volume"
        assert call("radiovolume|heli_2|0|100") == "ok|radio_volume"
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            car = call("radiostatus|car_1")
            heli = call("radiostatus|heli_2")
            if car.startswith("ok|radio|playing|") and heli.startswith(
                "ok|radio|playing|"
            ):
                car_duration = int(car.rsplit("|", 1)[1])
                heli_duration = int(heli.rsplit("|", 1)[1])
                assert car_duration > 0 and heli_duration > 0
                assert abs(car_duration - heli_duration) < 1500, (
                    "Late listeners must receive the full track duration"
                )
                break
            if "|error|" in car or "|error|" in heli:
                raise AssertionError(f"Playback error: {car}; {heli}")
            time.sleep(2)
        else:
            raise AssertionError("Both channels did not reach playing state")
        assert call("radiostop|car_1") == "ok|radio_stopped"
        assert call("radiostatus|car_1") == "ok|radio|missing"
        assert call("radiostatus|heli_2").startswith("ok|radio|playing|")
        print("PASS: independent radio playback, volume/pan, and stop")
    finally:
        call("radiostop|car_1")
        call("radiostop|heli_2")


if __name__ == "__main__":
    main()
