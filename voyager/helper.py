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
import logging
import os
import sys
import time
from pathlib import Path

log = logging.getLogger("voyager.helper")


def enable_dpi_awareness(user32=None):
    """Make window sizes and cursor positions real pixels on every monitor.

    A forum player's Set course never selected its target on a 2560-wide
    game (2026-10-15, "selected=none" twice, windowed and full screen): a
    DPI-unaware helper gets scaled sizes from the game window and scaled
    cursor positions, and with monitors at different scales Windows maps
    them with the wrong factor. Per-monitor awareness (v2) removes the
    scaling; on one monitor at 150 percent the old path also worked (VM).
    Returns the way that took, or None."""
    user32 = user32 or ctypes.windll.user32
    try:
        if user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4)):  # PER_MONITOR_AWARE_V2
            return "per-monitor v2"
    except (AttributeError, OSError):
        pass
    try:
        if ctypes.windll.shcore.SetProcessDpiAwareness(2) == 0:  # PROCESS_PER_MONITOR_DPI_AWARE
            return "per-monitor"
    except (AttributeError, OSError):
        pass
    return None


def _log_mouse(what, hwnd, width, height, x, y):
    """One line per cursor move, so a player's report shows where it went."""
    try:
        user32 = ctypes.windll.user32

        class _P(ctypes.Structure):
            _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]

        got = _P()
        user32.GetCursorPos(ctypes.byref(got))
        dpi = user32.GetDpiForWindow(hwnd) if hasattr(user32, "GetDpiForWindow") else 0
        log.info("mouse %s: window %dx%d dpi %d, to %d,%d, cursor at %d,%d",
                 what, width, height, dpi, x, y, got.x, got.y)
    except Exception:  # logging must never stop the helper
        pass

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


def parse_ring_click(line):
    """Return (x, y) for "M|ringclick,x,y": the same offset as M|ring, then a
    real left click. A map point next to Voyager takes Set course only once
    a click has selected it (demo, 2026-10-15)."""
    line = line.rstrip("\r\n")
    if not line.startswith("M|ringclick,"):
        return None
    parts = line[12:].split(",")
    if len(parts) != 2:
        return None
    try:
        return float(parts[0]), float(parts[1])
    except ValueError:
        return None


# The ring's radius as a share of the window's height: 350 pixels at 1080
# (measured on the build menu, 2026-10-14). Unreal scales the UI with height.
RING_RADIUS = 350 / 1080


def ring_mouse(nx, ny, then_click=False):
    """Move the cursor onto a radial menu segment (offset in ring radii),
    and left-click there when asked."""
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
    if then_click:
        click(pt.x, pt.y)
    else:
        user32.SetCursorPos(pt.x, pt.y)
    _log_mouse("ring click" if then_click else "ring", hwnd,
               rect.right - rect.left, h, pt.x, pt.y)


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
    _log_mouse("center", hwnd, rect.right - rect.left, rect.bottom - rect.top, pt.x, pt.y)


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
      "left": 0x25, "right": 0x27, "r": 0x52, "o": 0x4F, "i": 0x49, "n": 0x4E, "grave": 0xC0, "f1": 0x70,
      "pageup": 0x21, "pagedown": 0x22, "home": 0x24, "end": 0x23, "c": 0x43, "v": 0x56, "j": 0x4A, "h": 0x48,
      "f12": 0x7B}   # F12 is the helper's own: check for an update, or restart to finish one
VK_SHIFT, VK_CONTROL, VK_MENU, VK_INSERT, VK_CAPITAL = 0x10, 0x11, 0x12, 0x2D, 0x14
VK_F11 = 0x7A   # with Ctrl only: the input log on or off (mod_keys)
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
        # F11 too, for Ctrl+F11 (the input log switch), now that the mod's
        # keys always come from here.
        states = {vk: self.key_state(vk) for vk in list(VK.values()) + [VK_F11]}
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
        return mod_keys(set(new), held, bool(self.key_state(VK_SHIFT) & 0x8000))


def mod_keys(new, held_modifiers, shift):
    """The mod's key names for the VK codes just pressed (new), given the
    chord modifiers held (VK_CONTROL, VK_MENU, VK_INSERT, VK_CAPITAL) and
    whether Shift is down. Shared by KeyWatcher and KeyEvents."""
    held = set(held_modifiers)
    # Ctrl+F12 opens What's new (Casey, 2026-10-11); every other chord
    # stays ignored, so screen reader keys and Ctrl shortcuts never act.
    if held == {VK_CONTROL} and VK["f12"] in new:
        return ["ctrl+f12"]
    # Ctrl+F1 opens the list of every key (Casey, 2026-10-14).
    if held == {VK_CONTROL} and VK["f1"] in new:
        return ["ctrl+f1"]
    # Ctrl+F11 switches the input log on and off (the helper's own, see
    # serve; firefly82, 2026-10-21: whoever has trouble with it can turn it
    # off).
    if held == {VK_CONTROL} and VK_F11 in new:
        return ["ctrl+f11"]
    if held:
        return []
    names = []
    for name, vk in VK.items():
        if vk in new:
            names.append("shift+enter" if name == "enter" and shift else name)
    return names


# Windows reports left and right modifier keys apart in its keyboard events.
SIDED = {0xA0: VK_SHIFT, 0xA1: VK_SHIFT, 0xA2: VK_CONTROL, 0xA3: VK_CONTROL,
         0xA4: VK_MENU, 0xA5: VK_MENU}

KEY_NAMES = {0x08: "Backspace", 0x09: "Tab", 0x0D: "Enter", 0x10: "Shift", 0x11: "Ctrl", 0x12: "Alt",
             0x13: "Pause", 0x14: "Caps Lock", 0x1B: "Escape", 0x20: "Space", 0x21: "Page Up",
             0x22: "Page Down", 0x23: "End", 0x24: "Home", 0x25: "Left", 0x26: "Up", 0x27: "Right",
             0x28: "Down", 0x2C: "Print Screen", 0x2D: "Insert", 0x2E: "Delete", 0x5B: "Left Windows",
             0x5C: "Right Windows", 0x5D: "Menu", 0x6A: "Numpad *", 0x6B: "Numpad +", 0x6D: "Numpad -",
             0x6E: "Numpad .", 0x6F: "Numpad /", 0x90: "Num Lock", 0x91: "Scroll Lock",
             0xA0: "Left Shift", 0xA1: "Right Shift", 0xA2: "Left Ctrl", 0xA3: "Right Ctrl",
             0xA4: "Left Alt", 0xA5: "Right Alt", 0xBA: "OEM 1", 0xBB: "Plus", 0xBC: "Comma",
             0xBD: "Minus", 0xBE: "Period", 0xBF: "OEM 2", 0xC0: "Grave", 0xDB: "OEM 4",
             0xDC: "OEM 5", 0xDD: "OEM 6", 0xDE: "OEM 7", 0xE2: "OEM 102"}


def key_name(vk):
    """A key's name for the log, the same on every keyboard layout."""
    if 0x30 <= vk <= 0x39 or 0x41 <= vk <= 0x5A:
        return chr(vk)
    if 0x60 <= vk <= 0x69:
        return "Numpad " + str(vk - 0x60)
    if 0x70 <= vk <= 0x87:
        return "F" + str(vk - 0x6F)
    return KEY_NAMES.get(vk, "key 0x%02X" % vk)


# Keys named in the input log although they type a character: E, F and T
# (the game's quick actions, the presses firefly82 measured) and the mod's
# own letters, which UE4SS.log has had since 0.3.x ("key: j").
NAMED_CHARACTER_KEYS = {0x45, 0x46, 0x54} | {vk for vk in VK.values() if 0x41 <= vk <= 0x5A}


def log_name(vk):
    """key_name for the input log, except that any other key that types a
    character is only "a character key": profile and save names, or the
    Steam overlay over the game, went letter by letter into UE4SS.log, which
    players paste into public bug reports (review of firefly82's patch,
    2026-10-21)."""
    typing = (0x30 <= vk <= 0x39 or 0x41 <= vk <= 0x5A or 0x60 <= vk <= 0x6F
              or 0xBA <= vk <= 0xC0 or 0xDB <= vk <= 0xDF or vk == 0xE2)
    if typing and vk not in NAMED_CHARACTER_KEYS:
        return "a character key"
    return key_name(vk)


MOUSE_BUTTONS = {0x201: ("left", True), 0x202: ("left", False), 0x204: ("right", True),
                 0x205: ("right", False), 0x207: ("middle", True), 0x208: ("middle", False),
                 0x20B: ("side", True), 0x20C: ("side", False)}
WM_MOUSEMOVE, WM_MOUSEWHEEL, WM_MOUSEHWHEEL = 0x200, 0x20A, 0x20E


class KeyEvents:
    """Turns the keyboard and mouse events Windows reports into the mod's
    key names and into log lines, while the game is in front.

    Every key the player presses is logged, not only the mod's: E, F and T
    are the game's keys, and an E that did nothing could not be told from
    one never pressed (firefly82, 2026-10-21; rule: the log shows what the
    player did). Down and up are logged with how long the key was held,
    since some of the game's actions need a hold. Auto-repeat is counted
    and reported with the release, not logged line by line. Mouse buttons
    and the wheel are logged with the pointer's place; moves are not.
    Events Windows marks as injected came from software (the helper's own
    clicks for the mod, or a test tool), and the log says so.

    Nothing here decides what reaches the game: every event is passed on.
    """

    def __init__(self, game_in_front, now=None):
        self.game_in_front = game_in_front
        self.now = now or (lambda: time.strftime("%H:%M:%S") + ".%03d" % (int(time.time() * 1000) % 1000))
        self.down = {}      # vk -> [event time ms, logged, repeats]
        self.buttons = {}   # button -> event time ms

    def _held(self):
        held = {SIDED.get(vk, vk) for vk in self.down}
        return {m for m in CHORD_KEYS if m in held}, VK_SHIFT in held

    def _modifier_words(self, vk):
        words = []
        for v in sorted(self.down):
            base = SIDED.get(v, v)
            if v != vk and base in (VK_SHIFT, VK_CONTROL, VK_MENU, VK_INSERT, VK_CAPITAL):
                name = KEY_NAMES[base]
                if name not in words:
                    words.append(name)
        return words

    def key(self, vk, is_down, ms, injected):
        """One keyboard event. Returns (mod key names, log line or None)."""
        front = self.game_in_front()
        tag = ", injected" if injected else ""
        if is_down:
            if vk in self.down:
                self.down[vk][2] += 1
                return [], None
            mods = self._modifier_words(vk)
            self.down[vk] = [ms, front, 0]
            if not front:
                return [], None
            held, shift = self._held()
            base = SIDED.get(vk, vk)
            names = mod_keys({base}, held - {base}, shift) if (base in VK.values() or base == VK_F11) else []
            line = "%s %s down%s%s" % (self.now(), log_name(vk),
                                       (" with " + "+".join(mods)) if mods else "", tag)
            if names:
                line += " (mod key: %s)" % ",".join(names)
            return names, line
        was = self.down.pop(vk, None)
        # A key held while switching away is let go outside the game: not
        # logged (GPT review, 2026-10-21).
        if not (was and was[1]) or not front:
            return [], None
        line = "%s %s up after %d ms%s%s" % (self.now(), log_name(vk), max(ms - was[0], 0),
                                            (", %d repeats" % was[2]) if was[2] else "", tag)
        return [], line

    def mouse(self, msg, x, y, ms, injected, wheel=0):
        """One mouse event. Returns a log line or None."""
        if msg == WM_MOUSEMOVE:
            return None
        who = "by the mod" if injected else "by the player"
        if msg in (WM_MOUSEWHEEL, WM_MOUSEHWHEEL):
            if not self.game_in_front():
                return None
            return "%s mouse %s %+d at %d,%d, %s" % (
                self.now(), "wheel" if msg == WM_MOUSEWHEEL else "tilt", wheel, x, y, who)
        button = MOUSE_BUTTONS.get(msg)
        if not button:
            return None
        name, is_down = button
        if is_down:
            if not self.game_in_front():
                return None
            self.buttons[name] = ms
            return "%s mouse %s down at %d,%d, %s" % (self.now(), name, x, y, who)
        was = self.buttons.pop(name, None)
        if was is None or not self.game_in_front():
            return None
        return "%s mouse %s up after %d ms at %d,%d, %s" % (self.now(), name, max(ms - was, 0), x, y, who)


def player_press(names, line):
    """True for a press (key, mouse button or wheel) by the player of
    something the mod does not handle: what a bare "press" stands for. It
    ends the mod's speech hold, so a release must not count (Enter's release
    cut a room window off, Casey, 2026-10-26), nor the mod's own clicks; the
    mod's keys are sent by name and end it themselves."""
    if names or not line:
        return False
    # Nor a screen reader's own command: Insert or Caps Lock, alone or held
    # with another key (NVDA+Up to hear a line again would otherwise end the
    # hold on what is being read; Fable review, 2026-10-26).
    held = line.split(" down with ", 1)[1] if " down with " in line else ""
    if (" Insert down" in line or " Caps Lock down" in line
            or "Insert" in held.split(" (")[0] or "Caps Lock" in held.split(" (")[0]):
        return False
    return " up after " not in line and "by the mod" not in line


class InputHooks:
    """Windows' own keyboard and mouse events (low-level hooks), read on a
    thread of their own, instead of asking for 21 keys every 10 ms.

    The callbacks only note the event and always pass it on
    (CallNextHookEx), so no key is ever kept from the game or the screen
    reader. Results wait in a queue for the helper's loop: (names, line,
    ms Windows took to call the hook, perf_counter when it was called).
    """

    def __init__(self, events):
        import queue
        import threading
        self.events = events
        self.queue = queue.Queue()
        self.ready = threading.Event()
        self.ok = False
        self._thread = threading.Thread(target=self._run, name="input hooks", daemon=True)

    def start(self, wait=2.0):
        """Installs the hooks; True when both are in."""
        self._thread.start()
        self.ready.wait(wait)
        return self.ok

    def drain(self):
        out = []
        while True:
            try:
                out.append(self.queue.get_nowait())
            except Exception:
                return out

    def _run(self):
        from ctypes import wintypes
        user32, kernel32 = ctypes.windll.user32, ctypes.windll.kernel32
        LRESULT = ctypes.c_ssize_t
        PROC = ctypes.WINFUNCTYPE(LRESULT, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM)
        user32.SetWindowsHookExW.argtypes = [ctypes.c_int, PROC, wintypes.HINSTANCE, wintypes.DWORD]
        user32.SetWindowsHookExW.restype = wintypes.HHOOK
        user32.CallNextHookEx.argtypes = [wintypes.HHOOK, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM]
        user32.CallNextHookEx.restype = LRESULT
        kernel32.GetModuleHandleW.restype = wintypes.HMODULE

        class KBD(ctypes.Structure):
            _fields_ = [("vkCode", wintypes.DWORD), ("scanCode", wintypes.DWORD), ("flags", wintypes.DWORD),
                        ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t)]

        class MSLL(ctypes.Structure):
            _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long), ("mouseData", wintypes.DWORD),
                        ("flags", wintypes.DWORD), ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t)]

        kernel32.GetTickCount.restype = wintypes.DWORD

        # How long Windows took to hand the event to this hook: its own
        # time stamp against the clock now (both in ms since start-up). E
        # pressed in the game was sometimes lost, and those presses reached
        # the mod 210 to 370 ms late, down and up together (firefly82,
        # 2026-10-21): this tells where the time goes.
        def since(event_ms):
            return (kernel32.GetTickCount() - event_ms) & 0xFFFFFFFF

        def on_key(code, wparam, lparam):
            if code >= 0:
                try:
                    k = ctypes.cast(lparam, ctypes.POINTER(KBD)).contents
                    is_down = wparam in (0x100, 0x104)       # WM_KEYDOWN, WM_SYSKEYDOWN
                    names, line = self.events.key(k.vkCode, is_down, k.time, bool(k.flags & 0x10))
                    if names or line:
                        self.queue.put((names, line, since(k.time), time.perf_counter()))
                except Exception:   # the hook must never fail the key
                    pass
            return user32.CallNextHookEx(None, code, wparam, lparam)

        def on_mouse(code, wparam, lparam):
            if code >= 0 and wparam != WM_MOUSEMOVE:
                try:
                    m = ctypes.cast(lparam, ctypes.POINTER(MSLL)).contents
                    wheel = ctypes.c_short(m.mouseData >> 16).value
                    line = self.events.mouse(wparam, m.x, m.y, m.time, bool(m.flags & 0x01), wheel)
                    if line:
                        self.queue.put(([], line, since(m.time), time.perf_counter()))
                except Exception:
                    pass
            return user32.CallNextHookEx(None, code, wparam, lparam)

        self._procs = (PROC(on_key), PROC(on_mouse))   # kept alive for the hooks
        module = kernel32.GetModuleHandleW(None)
        kb = user32.SetWindowsHookExW(13, self._procs[0], module, 0)    # WH_KEYBOARD_LL
        ms = user32.SetWindowsHookExW(14, self._procs[1], module, 0)    # WH_MOUSE_LL
        self.ok = bool(kb and ms)
        log.info("input hooks: keyboard %s, mouse %s", "in" if kb else "failed", "in" if ms else "failed")
        self.ready.set()
        if not self.ok:
            return
        msg = wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))


class FrontWindow:
    """game_in_front, asked again only when the foreground window changes:
    the input hooks ask on every key and mouse button."""

    def __init__(self):
        self.hwnd, self.front = None, False

    def __call__(self):
        hwnd = ctypes.windll.user32.GetForegroundWindow()
        if hwnd != self.hwnd:
            self.hwnd, self.front = hwnd, game_in_front()
        return self.front


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


_hooks = None


def _input_hooks():
    """The input hooks, installed once per helper process (serve can run
    more than once), or None when Windows would not take them."""
    global _hooks
    if _hooks is None:
        h = InputHooks(KeyEvents(FrontWindow()))
        _hooks = h if h.start() else False
    return _hooks or None


def serve(tolk, speech_file, keep_going, on_keys=None):
    """Speaks the mod's lines and hands it keys until keep_going() is false.

    keep_going is checked about once a second. on_keys, if given, also gets
    each batch of key names.
    """
    speech_file = Path(speech_file)
    speech_file.parent.mkdir(parents=True, exist_ok=True)
    log.info("DPI awareness: %s", enable_dpi_awareness() or "not set")
    tailer = Tailer(speech_file)
    keys_file = speech_file.parent / DEFAULT_KEYS.name
    keys_file.write_text("")
    # The mod's keys always come from the 10 ms check (KeyWatcher; its
    # GetAsyncKeyState bit 0 also catches a tap shorter than the check).
    # Windows' own events (InputHooks) only write the input log: Windows
    # removes a low-level hook without telling anyone when its callback is
    # slow, and with the mod's keys on the hooks every key would then stop
    # mid-game (Casey's review of firefly82's patch, 2026-10-21).
    hooks = _input_hooks()
    if hooks:
        hooks.drain()   # events from before this game session
    else:
        log.info("input hooks not installed: no input log")
    user32 = ctypes.windll.user32
    user32.GetAsyncKeyState.restype = ctypes.c_ushort
    watcher = KeyWatcher(user32.GetAsyncKeyState, game_in_front)
    # The input log is OFF unless switched on with Ctrl+F11 (firefly82's
    # idea, 2026-10-21), kept across runs in a file: it names keys pressed in
    # the game, and players paste UE4SS.log into public bug reports, so it
    # is for a troubleshooting session, not every game (GPT review of the
    # patch, 2026-10-21). The mod's keys go to the mod either way.
    log_on_file = speech_file.parent / "input-log-on"
    log_on = [log_on_file.exists()]

    # keys.txt is written by the key thread below and by note() on this
    # thread, so writes share a lock.
    import queue
    import threading
    write_lock = threading.Lock()

    def append(lines):
        with write_lock:
            with open(keys_file, "a", encoding="utf-8") as f:
                f.write("".join(s + "\n" for s in lines))

    def note(text):
        """A line for UE4SS.log through the mod (with the hooks only)."""
        if hooks and log_on[0]:
            append(["log:%s %s" % (hooks.events.now(), text)])

    def timed(what, fn, *a):
        """Runs one of the loop's own jobs and logs how long it held the
        loop: while it runs, no key reaches keys.txt (a lost E reached the
        mod 210 to 370 ms late, firefly82, 2026-10-21)."""
        t = time.perf_counter()
        fn(*a)
        note("helper: %s took %d ms" % (what, (time.perf_counter() - t) * 1000))

    # Keys on a thread of their own, every 10 ms, so speech and the mod's
    # mouse clicks (click sleeps 110 ms) never hold a key back: a lost E
    # reached the mod 210 to 370 ms late while this loop was busy (firefly82,
    # 2026-10-21; idea from the outside reviews of that patch). on_keys
    # stays on the main thread, which also speaks through Tolk.
    pressed_queue = queue.Queue()
    stop = threading.Event()

    def key_loop():
        errors = 0
        while not stop.is_set():
            try:
                key_step()
            except Exception:
                # Logged the first three times only: a lasting fault would
                # otherwise write a traceback every 10 ms (Fable review).
                errors += 1
                if errors <= 3:
                    log.exception("key thread (error %d)", errors)
            time.sleep(0.01)

    def key_step():
        out = []
        if hooks:
            written = time.perf_counter()
            seen = press = False
            for names, line, lag, at in hooks.drain():
                # Every event as a "log:" line, which the mod writes to
                # UE4SS.log between the game's own lines and otherwise
                # ignores. Each says how long Windows took to report it and
                # how long it waited here before being written.
                if line and log_on[0]:
                    out.append("log:%s [Windows to helper %d ms, helper to file %d ms]"
                               % (line, lag, (written - at) * 1000))
                seen = seen or bool(line)
                press = press or player_press(names, line)
            # With the log off, a key or mouse button in the game still
            # tells the mod that input happened (a bare "seen", no key
            # name): Tab or a mouse click can move focus with no window
            # event, and the mod looks only after input (GPT review,
            # 2026-10-21). "press" too when the player pressed something
            # the mod does not handle: only that ends the mod's speech hold
            # (a release did, 2026-10-26). With the log on, the mod tells
            # the lines apart itself (keys.lua).
            if seen and not log_on[0]:
                out.append("seen")
            if press and not log_on[0]:
                out.append("press")
        pressed = watcher.poll()
        out += pressed
        if "ctrl+f11" in pressed:
            log_on[0] = not log_on[0]
            try:
                if log_on[0]:
                    log_on_file.write_text("on\n")
                else:
                    log_on_file.unlink(missing_ok=True)
            except OSError:
                pass
            # The mod says it (keys.lua reads the file), in the game's
            # language like its other words.
            log.info("input log %s", "on" if log_on[0] else "off")
        # A session that has ended writes nothing more (GPT review,
        # 2026-10-21: a late write could reach the next session's file).
        if stop.is_set():
            return
        if out:
            append(out)
        if pressed:
            pressed_queue.put(pressed)

    keys_thread = threading.Thread(target=key_loop, name="keys", daemon=True)
    keys_thread.start()
    try:
        _serve_loop(tolk, tailer, keep_going, on_keys, note, timed, pressed_queue)
    finally:
        stop.set()
        keys_thread.join(1.0)


def _serve_loop(tolk, tailer, keep_going, on_keys, note, timed, pressed_queue):
    """serve's main loop: speech, clicks and the session check; keys come
    from the key thread through pressed_queue."""
    last_speech = last_check = 0.0
    while True:
        while True:
            try:
                pressed = pressed_queue.get_nowait()
            except Exception:
                break
            if on_keys:
                on_keys(pressed)
        now = time.monotonic()
        if now - last_check >= 1.0:
            last_check = now
            t = time.perf_counter()
            going = keep_going()
            took = (time.perf_counter() - t) * 1000
            # Logged only when it held the loop for a whole tick or more:
            # once a second, it would bury the other lines.
            if took >= 10:
                note("helper: session check took %d ms" % took)
            if not going:
                return
        if now - last_speech < 0.03:
            time.sleep(0.01)
            continue
        last_speech = now
        for line in tailer.read_lines():
            parsed = parse_line(line)
            if parsed:
                timed("speech (%s, %d characters)" % ("interrupting" if parsed[0] else "queued", len(parsed[1])),
                      tolk.say, parsed[1], parsed[0])
                continue
            point = parse_click(line)
            if point:
                timed("click", click, *point)
                continue
            if is_center_mouse(line) and game_in_front():
                timed("mouse to centre", center_mouse)
                continue
            ring = parse_ring(line)
            if ring and game_in_front():
                timed("mouse move", ring_mouse, *ring)
                continue
            ring = parse_ring_click(line)
            if ring and game_in_front():
                timed("mouse move and click", ring_mouse, *ring, True)


if __name__ == "__main__":
    sys.exit(main())
