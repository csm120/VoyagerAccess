"""PyInstaller entry point for VoyagerAccess.exe."""
import sys

from voyager.app import main

if __name__ == "__main__":
    sys.exit(main())
