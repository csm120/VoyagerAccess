"""Runs the Voyager Access helper from the source tree (development).

    python tools\\speech_helper.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager.helper import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
