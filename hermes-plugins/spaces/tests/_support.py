"""Test helpers: import the plugin as the ``spaces`` package from its parent
directory, the way the Hermes loader does, against a throwaway database."""

from __future__ import annotations

import atexit
import importlib
import os
import shutil
import sys
import tempfile
from pathlib import Path

PLUGIN_DIR = Path(__file__).resolve().parents[1]
if str(PLUGIN_DIR.parent) not in sys.path:
    sys.path.insert(0, str(PLUGIN_DIR.parent))


def package():
    return importlib.import_module(PLUGIN_DIR.name)


def module(name: str):
    return importlib.import_module(f"{PLUGIN_DIR.name}.{name}")


def temp_db() -> Path:
    directory = tempfile.mkdtemp(prefix="spaces-test-")
    # Throwaway databases go when the test run ends.
    atexit.register(shutil.rmtree, directory, ignore_errors=True)
    return Path(directory) / "spaces.db"


def store():
    return module("spaces_store").SpacesStore(path=temp_db())


def isolate_default_db() -> Path:
    path = temp_db()
    os.environ["HERMES_SPACES_DB"] = str(path)
    return path
