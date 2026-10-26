"""Guard the exact 9.1.90 runtime selector and its code-cave placement."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import patch_imports
import patch_native_restrictions as limits
import patch_key_request_mode as key

ORIGINAL = ROOT / 'build/key-flow-audit/Spotify-original'


@unittest.skipUnless(ORIGINAL.is_file(), 'exact Spotify binary fixture absent')
class KeyModeRuntime(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        raw = ORIGINAL.read_bytes()
        with_imports, _ = patch_imports.patch(raw)
        cls.before, _ = limits.patch(with_imports)

    def test_only_caller_and_verified_cave_change(self):
        after, report = key.patch(self.before)
        self.assertTrue(report['runtime_selectable'])
        self.assertEqual(len(after), len(self.before))
        changed = {i for i, (old, new) in enumerate(zip(self.before, after)) if old != new}
        allowed = set(range(key.CALL_SITE - key.PREFERRED, key.CALL_SITE - key.PREFERRED + 4))
        allowed.update(range(key.CAVE - key.PREFERRED, key.CAVE - key.PREFERRED + len(key.trampoline())))
        self.assertTrue(changed)
        self.assertTrue(changed <= allowed)
        self.assertEqual(after[key.CAVE - key.PREFERRED:key.CAVE - key.PREFERRED + len(key.trampoline())],
                         key.trampoline())
        with self.assertRaises(ValueError):
            key.patch(after)

    def test_wrong_caller_and_occupied_cave_rejected(self):
        for address in (key.CALL_SITE, key.PROVIDER, key.MAPPING, key.DLSYM_STUB, key.CAVE):
            changed = bytearray(self.before)
            changed[address - key.PREFERRED] ^= 1
            with self.subTest(address=hex(address)), self.assertRaises(ValueError):
                key.patch(changed)

    def test_generated_header_and_symbol_binding(self):
        self.assertEqual((ROOT / 'src/NativeKeyModePatch.h').read_text(), key.key_header())
        key._verify_dlsym_binding(self.before)


if __name__ == '__main__':
    unittest.main(verbosity=2)
