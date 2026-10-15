"""Nothing runs the mod's Lua outside the game, so a call to a function that
does not exist fails only when that line runs in play. popups.lua called a
missing text_of() from 0.3.0 to 0.3.4, and a side mission offer with an
option you cannot take was never read (found in a Q Trial, 2026-10-14).

This is a rough text check, not a Lua parser: a bare call to a name that the
module does not define, that is not a Lua built-in and not a UE4SS global."""
import re
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

BUILTINS = set("""assert error ipairs pairs next pcall xpcall print require select setmetatable
getmetatable tonumber tostring type rawget rawset rawequal rawlen load loadfile dofile
collectgarbage unpack""".split())
UE4SS = set("""FindAllOf FindFirstOf StaticFindObject LoopAsync LoopInGameThreadWithDelay
ExecuteInGameThread ExecuteInGameThreadWithDelay ExecuteWithDelay RegisterKeyBind RegisterHook
NotifyOnNewObject RestartCurrentMod StaticConstructObject FName FText ForEachUObject
CreateInvalidObject RegisterCustomEvent IterateGameDirectories""".split())
KEYWORDS = set("""and or not if then elseif else end for while do repeat until function local
return in break goto nil true false""".split())


def undefined_calls(src):
    code = re.sub(r"--\[\[.*?\]\]", "", src, flags=re.S)
    code = re.sub(r"--[^\n]*", "", code)
    code = re.sub(r'"(?:\\.|[^"\\])*"', '""', code)
    code = re.sub(r"'(?:\\.|[^'\\])*'", "''", code)
    defined = set(re.findall(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", code))
    defined |= set(re.findall(r"\blocal\s+function\s+([A-Za-z_]\w*)", code))
    for m in re.finditer(r"\blocal\s+([A-Za-z_][\w\s,]*?)(?:=|\n|$)", code):
        defined |= {n.strip() for n in m.group(1).split(",") if n.strip()}
    for g in re.findall(r"\bfor\s+([\w\s,]+?)\s+in\b", code):
        defined |= {n.strip() for n in g.split(",") if n.strip()}
    for g in re.findall(r"function\s*[\w.:]*\s*\(([^)]*)\)", code):
        defined |= {n.strip() for n in g.split(",") if n.strip()}
    defined |= set(re.findall(r"^\s*([A-Za-z_]\w*)\s*=", code, flags=re.M))
    libs = {"string", "table", "math", "os", "io", "coroutine", "utf8", "debug"}
    found = set()
    for m in re.finditer(r"(?<![\w.:])([A-Za-z_]\w*)\s*\(", code):
        n = m.group(1)
        if n not in KEYWORDS | BUILTINS | UE4SS | defined | libs:
            found.add(n)
    return found


class LuaCallTests(unittest.TestCase):
    def test_no_calls_to_undefined_functions(self):
        problems = {}
        for f in sorted(SCRIPTS.glob("*.lua")):
            bad = undefined_calls(f.read_text(encoding="utf-8"))
            if bad:
                problems[f.name] = sorted(bad)
        self.assertEqual(problems, {})

    def test_no_unchecked_brush_reads(self):
        # Brush.ResourceObject:GetFName() with no IsValid() check is an
        # access violation when the image has no asset, and pcall cannot
        # catch it: it crashed the game on a Q Trial's Repair Station
        # (2026-10-14), and the night before it stopped the mod twice.
        problems = []
        for f in sorted(SCRIPTS.glob("*.lua")):
            for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
                if re.search(r"ResourceObject\s*:", line) and not line.lstrip().startswith("--"):
                    problems.append(f"{f.name}:{n}")
        self.assertEqual(problems, [])

    def test_no_doubled_condition_lines(self):
        # A doubled "elseif cls == ... then" line gives the first copy an
        # empty body: incoming calls were read as nothing from 0.3.4 to
        # 0.3.6 (found 2026-10-14).
        problems = []
        for f in sorted(SCRIPTS.glob("*.lua")):
            lines = f.read_text(encoding="utf-8").splitlines()
            for n in range(1, len(lines)):
                a, b = lines[n - 1].strip(), lines[n].strip()
                if a == b and re.match(r"^(elseif|if)\b.*\bthen$", a):
                    problems.append(f"{f.name}:{n + 1}")
        self.assertEqual(problems, [])

    def test_the_check_catches_a_missing_function(self):
        src = "local function plain(s) return s end\nlocal x = plain(text_of(t))\n"
        self.assertEqual(undefined_calls(src), {"text_of"})


if __name__ == "__main__":
    unittest.main()
