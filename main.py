#!/usr/bin/env python3
"""Run GigDownloader straight from a clone:  python main.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gigdownloader.cli import main  # noqa: E402

if __name__ == "__main__":
    main()
