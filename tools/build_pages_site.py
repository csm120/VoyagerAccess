"""Builds the small GitHub Pages site: the instructions (README.md) as
index.html and What's new (docs/WHATS_NEW.md) as changelog.html, so players
get a plain page with nothing else on it (Casey, 2026-10-14, like KeyQuest's
site; adapted from KeyQuest's tools/dev/build_pages_site.py).

Usage: python tools/build_pages_site.py   (writes site/)
"""
import html
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "site"
GITHUB = "https://github.com/csm120/VoyagerAccess/blob/main/"
# Links in the Markdown that point at other files in the repository.
LOCAL_LINKS = {"docs/WHATS_NEW.md": "changelog.html", "README.md": "index.html"}


def _link(target):
    if target in LOCAL_LINKS:
        return LOCAL_LINKS[target]
    if re.match(r"^[a-z]+:", target) or target.startswith("#"):
        return target
    return GITHUB + target


def _inline(text):
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)",
                 lambda m: f'<a href="{html.escape(_link(m.group(2)))}">{m.group(1)}</a>', out)
    return out


def markdown_to_html(text):
    parts, para = [], []
    lst = None   # "ul" or "ol" while a list is open

    def flush():
        if para:
            parts.append(f"<p>{_inline(' '.join(para))}</p>")
            para.clear()

    def close():
        nonlocal lst
        if lst:
            parts.append(f"</{lst}>")
            lst = None

    def item(kind, body):
        nonlocal lst
        flush()
        if lst != kind:
            close()
            parts.append(f"<{kind}>")
            lst = kind
        parts.append(f"<li>{_inline(body)}</li>")

    for line in text.splitlines():
        s = line.strip()
        if not s:
            flush()
            close()
            continue
        m = re.match(r"^(#{1,6})\s+(.*)$", s)
        if m:
            flush()
            close()
            level = len(m.group(1))
            parts.append(f"<h{level}>{_inline(m.group(2))}</h{level}>")
            continue
        m = re.match(r"^-\s+(.*)$", s)
        if m:
            item("ul", m.group(1))
            continue
        m = re.match(r"^\d+\.\s+(.*)$", s)
        if m:
            item("ol", m.group(1))
            continue
        close()
        para.append(s)
    flush()
    close()
    return "\n".join(parts)


STYLE = """
    body { font-family: Arial, sans-serif; font-size: 18px; line-height: 1.6;
           color: #111; background: #fff; margin: 0; }
    .block { max-width: 75ch; margin: 0 auto; padding: 0 16px; }
    main { padding: 16px 0; }
    a { color: #0b57d0; }
    a:focus-visible { outline: 3px solid #111; outline-offset: 2px; }
    .skip { position: absolute; left: 8px; top: -48px; background: #fff; color: #111;
            border: 2px solid #111; padding: 8px 10px; }
    .skip:focus { top: 8px; }
    h1, h2, h3 { line-height: 1.3; }
    code { font-family: Consolas, "Courier New", monospace; }
    @media (prefers-color-scheme: dark) {
      body { color: #eee; background: #121212; }
      a { color: #8ab4f8; }
      a:focus-visible { outline-color: #eee; }
      .skip { background: #121212; color: #eee; border-color: #eee; }
    }
"""


def page(title, body, nav):
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>{STYLE}</style>
</head>
<body>
  <a class="skip" href="#main">Skip to main content</a>
  <header><div class="block"><p>{nav}</p></div></header>
  <main id="main"><div class="block">
{body}
  </div></main>
</body>
</html>
"""


def main():
    OUT.mkdir(exist_ok=True)
    (OUT / ".nojekyll").write_text("", encoding="utf-8")
    readme = markdown_to_html((REPO / "README.md").read_text(encoding="utf-8"))
    news = markdown_to_html((REPO / "docs" / "WHATS_NEW.md").read_text(encoding="utf-8"))
    (OUT / "index.html").write_text(page(
        "Voyager Access", readme,
        '<a href="changelog.html">New in Voyager Access</a>'), encoding="utf-8")
    (OUT / "changelog.html").write_text(page(
        "New in Voyager Access", news,
        '<a href="index.html">Back to the Voyager Access instructions</a>'), encoding="utf-8")


if __name__ == "__main__":
    main()
