"""Adds and removes a game's Steam launch option, such as -dx11.

Steam keeps launch options per account in userdata/<id>/config/
localconfig.vdf, under UserLocalConfigStore > Software > Valve > Steam >
apps > <appid> > LaunchOptions. (The same app id also appears under a
top-level "apps" block for overlay settings; that one is left alone.)
The file is edited as text, changing only that one value, so everything
else Steam wrote stays byte for byte. Steam rewrites the file while it
runs, so it must be closed first.
"""
import re
from pathlib import Path

_TOKEN = re.compile(r'"((?:[^"\\]|\\.)*)"|([{}])')
APPS = ("userlocalconfigstore", "software", "valve", "steam", "apps")


def _scan(text):
    """Blocks as path -> (open brace index, close brace index) and values as
    path -> (start, end) of the quoted value's contents."""
    stack, blocks, values = [], {}, {}
    key = None
    for m in _TOKEN.finditer(text):
        quoted, brace = m.groups()
        if brace == "{":
            stack.append(((key or "").lower(), m.start()))
            key = None
        elif brace == "}":
            if stack:
                name, opened = stack.pop()
                path = tuple(s[0] for s in stack) + (name,)
                blocks.setdefault(path, (opened, m.start()))
        elif key is None:
            key = quoted
        else:
            path = tuple(s[0] for s in stack) + (key.lower(),)
            values.setdefault(path, (m.start(1), m.end(1)))
            key = None
    return blocks, values


def _indent_at(text, index):
    start = text.rfind("\n", 0, index) + 1
    return re.match(r"[ \t]*", text[start:]).group(0)


def get_option(text, appid):
    """The game's launch options, or None when it has none set."""
    _, values = _scan(text)
    span = values.get(APPS + (str(appid), "launchoptions"))
    return text[span[0]:span[1]] if span else None


def add_option(text, appid, option):
    """Returns text with option added to the game's launch options."""
    blocks, values = _scan(text)
    appid = str(appid)
    span = values.get(APPS + (appid, "launchoptions"))
    if span:
        current = text[span[0]:span[1]]
        if option in current.split():
            return text
        return text[:span[0]] + (current + " " + option).strip() + text[span[1]:]
    line = '"LaunchOptions"\t\t"%s"' % option
    app = blocks.get(APPS + (appid,))
    if app:
        indent = _indent_at(text, app[0]) + "\t"
        return text[:app[0] + 1] + "\n" + indent + line + text[app[0] + 1:]
    apps = blocks.get(APPS)
    if not apps:
        raise ValueError("no Software/Valve/Steam/apps block in localconfig.vdf")
    indent = _indent_at(text, apps[0]) + "\t"
    block = "\n%s\"%s\"\n%s{\n%s\t%s\n%s}" % (indent, appid, indent, indent, line, indent)
    return text[:apps[0] + 1] + block + text[apps[0] + 1:]


def remove_option(text, appid, option, drop_empty=False):
    """Returns text with option taken out of the game's launch options.

    drop_empty: the LaunchOptions line (and an app block left empty) was
    created by add_option, so remove it rather than leave '"LaunchOptions"
    ""' behind, which the VM uninstall test found (2026-10-11).
    """
    appid = str(appid)
    _, values = _scan(text)
    span = values.get(APPS + (appid, "launchoptions"))
    if not span:
        return text
    words = text[span[0]:span[1]].split()
    if option not in words:
        return text
    kept = " ".join(w for w in words if w != option)
    if kept or not drop_empty:
        return text[:span[0]] + kept + text[span[1]:]
    # Remove the whole line: from the newline before it to its closing quote.
    line_start = text.rfind("\n", 0, span[0])
    text = text[:line_start] + text[span[1] + 1:]
    blocks, _ = _scan(text)
    app = blocks.get(APPS + (appid,))
    if app and not text[app[0] + 1:app[1]].strip():
        key = text.rfind('"%s"' % appid, 0, app[0])
        start = text.rfind("\n", 0, key)
        text = text[:start] + text[app[1] + 1:]
    return text


def read_file(path):
    """The file's text exactly as stored (no newline translation)."""
    return Path(path).read_bytes().decode("utf-8", errors="surrogateescape")


def edit_file(path, change):
    """Applies change(text) -> text to the file, keeping its own line endings:
    Steam writes LF, and a text-mode write on Windows made every line CRLF
    (VM uninstall test, 2026-10-11). Returns True when the file changed."""
    text = read_file(path)
    new = change(text)
    if new == text:
        return False
    Path(path).write_bytes(new.encode("utf-8", errors="surrogateescape"))
    return True


def config_files(steam):
    """Every Steam account's localconfig.vdf on this computer."""
    if steam is None:
        return []
    return sorted(Path(steam).glob("userdata/*/config/localconfig.vdf"))
