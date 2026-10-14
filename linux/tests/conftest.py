import os
from pathlib import Path
import sys

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ['LANG'] = 'de_CH.UTF-8'
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import opencommander  # Initialize the platform's libarchive runtime before collection.
