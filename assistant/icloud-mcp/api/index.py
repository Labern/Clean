# Vercel entry point: every path is rewritten here (see vercel.json).
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from icloud_mcp.server import app  # noqa: E402,F401
