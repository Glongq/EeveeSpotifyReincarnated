"""Compatibility wrapper: input IPA, rootless core, output IPA."""
from pathlib import Path
import subprocess
import sys
if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit('usage: build_ipa.py input.ipa EeveeSpotify.dylib output.ipa')
    tool = Path(__file__).resolve().parents[1] / 'tools/prepare_ipa.py'
    subprocess.run([sys.executable, str(tool), sys.argv[1], sys.argv[3], '--core', sys.argv[2]], check=True)
