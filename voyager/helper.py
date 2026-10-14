"""Speaks what the Voyager Access Lua mod writes to its speech file.

The mod appends one line per message to %LOCALAPPDATA%\\VoyagerAccess\\speech.txt:
"I|text" interrupts current speech, "Q|text" queues after it, and "C|x,y"
left-clicks at that screen pixel (the game ignores Enter, so the mod turns
Enter into a real click on the focused button). This helper
tails that file and sends each line to the running screen reader through Tolk
(SAPI if none is running). Start it before or after the game; Ctrl+C stops it.

    python tools\\speech_helper.py
"""
import argparse
import ctypes
import os
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_FILE = Path(os.environ.get("LOCALAPPDATA", ".")) / "VoyagerAccess" / "speech.txt"
# In the built exe, PyInstaller unpacks bundled files under sys._MEIPASS.
RESOURCES = Path(getattr(sys, "_MEIPASS", REPO))
DEFAULT_TOLK = RESOURCES / "tolk" if hasattr(sys, "_MEIPASS") else REPO / "vendor" / "tolk"
DATA_DIR = DEFAULT_FILE.parent


def parse_line(line):
    """Return (interrupt, text) for one protocol line, or None to skip it."""
    line = line.rstrip("\r\n")
    if len(line) < 3 or line[1] != "|" or line[0] not in "IQ":
        return None
    text = line[2:].strip()
    if not text:
        return None
    return line[0] == "I", text


def parse_click(line):
    """Return (x, y) screen pixels for a "C|x,y" line, or None."""
    line = line.rstrip("\r\n")
    if not line.startswith("C|"):
        return None
    parts = line[2:].split(",")
    if len(parts) != 2:
        return None
    try:
        return tuple(int(round(float(p))) for p in parts)
    except ValueError:
        return None


def is_center_mouse(line):
    """True for "M|center": put the cursor in the middle of the game window.

    The System Map's Set course takes its target from under the mouse
    cursor; the mod centres the camera on the chosen point, so the cursor
    must be in the middle too (2026-10-14).
    """
    return line.rstrip("\r\n") == "M|center"


def parse_ring(line):
    """Return (x, y) for "M|ring,x,y", an offset from the window centre in
    ring radii, or None. Radial menu details only show on mouse hover."""
    line = line.rstrip("\r\n")
    if not line.startswith("M|ring,"):
        return None
    parts = line[7:].split(",")
    if len(parts) != 2:
        return None
    try:
        return float(parts[0]), float(parts[1])
    except ValueError:
        return None


# The ring's radius as a share of the window's height: 350 pixels at 1080
# (measured on the build menu, 2026-10-14). Unreal scales the UI with height.
RING_RADIUS = 350 / 1080


def ring_mouse(nx, ny):
    """Move the cursor onto a radial menu segment (offset in ring radii)."""
    user32 = ctypes.windll.user32

    class _Rect(ctypes.Structure):
        _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                    ("right", ctypes.c_long), ("bottom", ctypes.c_long)]

    class _Point(ctypes.Structure):
        _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]

    hwnd = user32.GetForegroundWindow()
    rect = _Rect()
    if not hwnd or not user32.GetClientRect(hwnd, ctypes.byref(rect)):
        return
    h = rect.bottom - rect.top
    r = RING_RADIUS * h
    pt = _Point(int((rect.right - rect.left) / 2 + nx * r), int(h / 2 + ny * r))
    user32.ClientToScreen(hwnd, ctypes.byref(pt))
    user32.SetCursorPos(pt.x, pt.y)


def center_mouse():
    """Move the cursor to the centre of the foreground window's client area."""
    user32 = ctypes.windll.user32

    class _Rect(ctypes.Structure):
        _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                    ("right", ctypes.c_long), ("bottom", ctypes.c_long)]

    class _Point(ctypes.Structure):
        _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]

    hwnd = user32.GetForegroundWindow()
    rect = _Rect()
    if not hwnd or not user32.GetClientRect(hwnd, ctypes.byref(rect)):
        return
    pt = _Point((rect.right - rect.left) // 2, (rect.bottom - rect.top) // 2)
    user32.ClientToScreen(hwnd, ctypes.byref(pt))
    user32.SetCursorPos(pt.x, pt.y)


class _MouseInput(ctypes.Structure):
    _fields_ = [("dx", ctypes.c_long), ("dy", ctypes.c_long), ("mouseData", ctypes.c_ulong),
                ("dwFlags", ctypes.c_ulong), ("time", ctypes.c_ulong),
                ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong))]


class _Input(ctypes.Structure):
    # INPUT is a union of mouse, keyboard and hardware input; MOUSEINPUT is
    # the largest member on x64, so this layout has the right size.
    _fields_ = [("type", ctypes.c_ulong), ("mi", _MouseInput)]


def click(x, y):
    """Left-click at screen pixel (x, y) through the OS input queue."""
    user32 = ctypes.windll.user32
    user32.SetCursorPos(x, y)
    time.sleep(0.05)  # let the game see the hover before the press
    down, up = 0x0002, 0x0004  # MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP
    for flags in (down, up):
        inp = _Input(type=0, mi=_MouseInput(0, 0, 0, flags, 0, None))
        user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(inp))
        time.sleep(0.03)


class Tailer:
    """Reads complete new lines from a file that one writer appends to.

    Starts at the current end so old messages are not replayed, and starts
    over from the top when the file shrinks (the mod truncates it on load).
    """

    def __init__(self, path):
        self.path = Path(path)
        self.pos = self.path.stat().st_size if self.path.exists() else 0
        self.partial = b""

    def read_lines(self):
        try:
            size = self.path.stat().st_size
        except FileNotFoundError:
            return []
        if size < self.pos:
            self.pos, self.partial = 0, b""
        if size == self.pos:
            return []
        with open(self.path, "rb") as f:
            f.seek(self.pos)
            data = f.read()
        self.pos += len(data)
        data = self.partial + data
        *lines, self.partial = data.split(b"\n")
        return [line.decode("utf-8", errors="replace") for line in lines]


# Keys the mod acts on, read here and handed to the mod through keys.txt.
# UE4SS runs RegisterKeyBind callbacks on its own thread while game-thread
# loops run Lua unlocked (LuaMod.cpp process_delayed_actions), so a key press
# during a poll corrupted the Lua heap and crashed the game (crash inside
# luaH_setint, 2026-10-10 22:24). The mod now runs Lua on the game thread only.
VK = {"enter": 0x0D, "backspace": 0x08, "escape": 0x1B, "up": 0x26, "down": 0x28,
      "left": 0x25, "right": 0x27, "r": 0x52, "o": 0x4F, "l": 0x4C, "n": 0x4E, "grave": 0xC0, "f1": 0x70,
      "pageup": 0x21, "pagedown": 0x22, "home": 0x24, "end": 0x23, "c": 0x43, "v": 0x56, "j": 0x4A,
      "f12": 0x7B}   # F12 is the helper's own: check for an update, or restart to finish one
VK_SHIFT, VK_CONTROL, VK_MENU, VK_INSERT, VK_CAPITAL = 0x10, 0x11, 0x12, 0x2D, 0x14
# Insert and Caps Lock are NVDA and JAWS modifiers: NVDA+R never reaches the
# game, but the R key still shows as down here.
CHORD_KEYS = (VK_CONTROL, VK_MENU, VK_INSERT, VK_CAPITAL)
DEFAULT_KEYS = DEFAULT_FILE.parent / "keys.txt"
# The full game's exe has "Steam" in its name; the demo's does not.
GAME_EXES = ("stvoyagersteam-win64-shipping.exe", "stvoyager-win64-shipping.exe")


def is_game_exe(path):
    return Path(path).name.lower() in GAME_EXES


class KeyWatcher:
    """Reports each new press of a VK key while the game is in front.

    key_state(vk) behaves like GetAsyncKeyState: 0x8000 while down, 0x0001
    if pressed since the last read (catches a tap shorter than the poll).
    """

    def __init__(self, key_state, game_in_front):
        self.key_state = key_state
        self.game_in_front = game_in_front
        self.held = set()

    def poll(self):
        states = {vk: self.key_state(vk) for vk in VK.values()}
        down = {vk for vk, s in states.items() if s & 0x8000}
        if not self.game_in_front():
            self.held = down
            return []
        new = [vk for vk, s in states.items()
               if (s & 0x8000 and vk not in self.held) or (s & 0x0001 and not s & 0x8000)]
        self.held = down
        if not new:
            return []
        held = {m for m in CHORD_KEYS if self.key_state(m) & 0x8000}
        # Ctrl+F12 opens What's new (Casey, 2026-10-11); every other chord
        # stays ignored, so screen reader keys and Ctrl shortcuts never act.
        if held == {VK_CONTROL} and VK["f12"] in new:
            return ["ctrl+f12"]
        # Ctrl+F1 opens the list of every key (Casey, 2026-10-14).
        if held == {VK_CONTROL} and VK["f1"] in new:
            return ["ctrl+f1"]
        if held:
            return []
        shift = bool(self.key_state(VK_SHIFT) & 0x8000)
        names = []
        for name, vk in VK.items():
            if vk in new:
                names.append("shift+enter" if name == "enter" and shift else name)
        return names


def game_in_front():
    """True when the foreground window belongs to the game's process."""
    user32, kernel32 = ctypes.windll.user32, ctypes.windll.kernel32
    pid = ctypes.c_ulong()
    user32.GetWindowThreadProcessId(user32.GetForegroundWindow(), ctypes.byref(pid))
    h = kernel32.OpenProcess(0x1000, False, pid.value)  # QUERY_LIMITED_INFORMATION
    if not h:
        return False
    try:
        buf = ctypes.create_unicode_buffer(520)
        size = ctypes.c_ulong(len(buf))
        if not kernel32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size)):
            return False
        return is_game_exe(buf.value)
    finally:
        kernel32.CloseHandle(h)


class Tolk:
    def __init__(self, folder):
        ctypes.windll.kernel32.SetDllDirectoryW(str(folder))
        self.dll = ctypes.WinDLL(str(Path(folder) / "Tolk.dll"))
        self.dll.Tolk_DetectScreenReader.restype = ctypes.c_wchar_p
        self.dll.Tolk_Output.argtypes = [ctypes.c_wchar_p, ctypes.c_bool]
        self.dll.Tolk_TrySAPI.argtypes = [ctypes.c_bool]
        self.dll.Tolk_TrySAPI(True)
        self.dll.Tolk_Load()

    def name(self):
        return self.dll.Tolk_DetectScreenReader() or "none"

    def say(self, text, interrupt):
        self.dll.Tolk_Output(text, interrupt)

    def unload(self):
        self.dll.Tolk_Unload()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--file", type=Path, default=DEFAULT_FILE)
    ap.add_argument("--tolk", type=Path, default=DEFAULT_TOLK)
    args = ap.parse_args(argv)

    tolk = Tolk(args.tolk)
    try:
        print(f"Voyager Access speech helper running; screen reader: {tolk.name()}. Ctrl+C to stop.")
        tolk.say("Voyager Access speech helper running", True)
        serve(tolk, args.file, lambda: True)
    except KeyboardInterrupt:
        pass
    finally:
        tolk.unload()
    return 0


def serve(tolk, speech_file, keep_going, on_keys=None):
    """Speaks the mod's lines and hands it keys until keep_going() is false.

    keep_going is checked about once a second. on_keys, if given, also gets
    each batch of key names.
    """
    speech_file = Path(speech_file)
    speech_file.parent.mkdir(parents=True, exist_ok=True)
    tailer = Tailer(speech_file)
    keys_file = speech_file.parent / DEFAULT_KEYS.name
    keys_file.write_text("")
    user32 = ctypes.windll.user32
    user32.GetAsyncKeyState.restype = ctypes.c_ushort
    watcher = KeyWatcher(user32.GetAsyncKeyState, game_in_front)
    last_speech = last_check = 0.0
    while True:
        pressed = watcher.poll()
        if pressed:
            with open(keys_file, "a") as f:
                f.write("".join(name + "\n" for name in pressed))
            if on_keys:
                on_keys(pressed)
        now = time.monotonic()
        if now - last_check >= 1.0:
            last_check = now
            if not keep_going():
                return
        if now - last_speech < 0.03:
            time.sleep(0.01)
            continue
        last_speech = now
        for line in tailer.read_lines():
            parsed = parse_line(line)
            if parsed:
                tolk.say(parsed[1], parsed[0])
                continue
            point = parse_click(line)
            if point:
                click(*point)
                continue
            if is_center_mouse(line) and game_in_front():
                center_mouse()
                continue
            ring = parse_ring(line)
            if ring and game_in_front():
                ring_mouse(*ring)


if __name__ == "__main__":
    sys.exit(main())
