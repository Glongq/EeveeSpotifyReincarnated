"""Portable checks using synthetic binaries; no Spotify code or credentials."""
from pathlib import Path
import hashlib
import json
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import patch_key_request_mode as keys
import patch_native_restrictions as restrictions
import patch_offline as reminder


def macho(segments, size):
    commands = struct.pack('<II16s', 0x1b, 24, restrictions.UUID)
    for vm, fileoff, filesize in segments:
        commands += struct.pack('<II16sQQQQiiII', 0x19, 72, b'__TEXT', vm,
                                filesize, fileoff, filesize, 5, 5, 0, 0)
    result = bytearray(size)
    result[:32] = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2,
                              len(segments) + 1, len(commands), 0, 0)
    result[32:32 + len(commands)] = commands
    return result


def key_fixture():
    segments = [(0x103a65000, 0x1000, 0x1000), (0x108fa7800, 0x2000, 0x1000)]
    data = macho(segments, 0x4000)
    for address, code in [(keys.WINDOW, keys.ORIGINAL),
                          (keys.PROVIDER, keys.PROVIDER_HEAD),
                          (keys.MAPPING, keys.MAPPING_BYTES)]:
        vm, offset, _ = next(s for s in segments if s[0] <= address < s[0] + s[2])
        at = offset + address - vm
        data[at:at + len(code)] = code
    return bytes(data)


class ProvenanceTests(unittest.TestCase):
    def test_v7_runtime_snapshot_and_preserved_v4_backend(self):
        previous = json.loads((ROOT / 'provenance.json').read_text())
        provenance = json.loads((ROOT / 'provenance-ui-v7.json').read_text())
        self.assertEqual(previous['release'], 'spotify-ui-v4')
        self.assertEqual(provenance['release'], 'spotify-ui-v7')
        self.assertFalse(provenance['wav_capture_enabled'])
        expected = provenance['source_sha256_by_file']
        actual_names = {'src/' + p.name for p in (ROOT / 'src').iterdir() if p.is_file()}
        self.assertEqual(actual_names, set(expected))
        for name, digest in expected.items():
            with self.subTest(file=name):
                self.assertEqual(hashlib.sha256((ROOT / name).read_bytes()).hexdigest(), digest)
                if name != 'src/DownloadSettingsUI.m':
                    self.assertEqual(digest, previous['source_sha256_by_file'][name])
        for name, digest in provenance['eevee_source_sha256_by_file'].items():
            with self.subTest(file=name):
                self.assertEqual(hashlib.sha256((ROOT.parent / name).read_bytes()).hexdigest(), digest)

    def test_generated_headers(self):
        self.assertEqual((ROOT / 'src/NativeRestrictionsPatch.h').read_text(), restrictions.guard_header())
        self.assertEqual((ROOT / 'src/OfflineLimits.h').read_text(), restrictions.limits_header())

    def test_python_sources_compile(self):
        for path in (ROOT / 'tools').glob('*.py'):
            compile(path.read_text(), str(path), 'exec')


class KeyPatchTests(unittest.TestCase):
    def test_exact_mode_change_and_repeat_rejection(self):
        original = key_fixture()
        patched, report = keys.patch(original)
        at = 0x1000 + keys.CALL_SITE - 0x103a65000
        self.assertEqual(patched[at:at + 4], bytes.fromhex('02008052'))
        self.assertEqual(original[:at] + original[at + 4:], patched[:at] + patched[at + 4:])
        self.assertEqual(len(original), len(patched))
        self.assertEqual(report['original_mode'], 1)
        self.assertEqual(report['request_mode'], 0)
        with self.assertRaises(ValueError):
            keys.patch(patched)

    def test_wrong_uuid_rejected(self):
        data = bytearray(key_fixture()); data[40] ^= 1
        with self.assertRaises(ValueError):
            keys.patch(bytes(data))

    def test_changed_provider_rejected(self):
        data = bytearray(key_fixture()); data[0x2000 + keys.PROVIDER - 0x108fa7800] ^= 1
        with self.assertRaises(ValueError):
            keys.patch(bytes(data))


class RestrictionPatchTests(unittest.TestCase):
    def fixture(self):
        data = macho([(restrictions.PREFERRED, 0, 0x4000)], 0x4000)
        data[0x3000:0x3010] = restrictions.ORIGINAL
        return bytes(data)

    def test_guarded_patch_preserves_length(self):
        original = self.fixture()
        patched, report = restrictions.patch_at(original, restrictions.PREFERRED + 0x3000,
                                                 restrictions.PREFERRED + 0x1000,
                                                 restrictions.ORIGINAL)
        self.assertEqual(len(original), len(patched))
        self.assertEqual(report['minimum_tracks'], 1000000)
        self.assertEqual(report['minimum_music_duration_seconds'], 2147483647)
        self.assertEqual(patched[0x1000:0x1000 + report['trampoline_bytes']],
                         restrictions.trampoline(restrictions.PREFERRED + 0x1000,
                                                 restrictions.PREFERRED + 0x3000))

    def test_occupied_padding_rejected(self):
        data = bytearray(self.fixture()); data[0x1000] = 1
        with self.assertRaises(ValueError):
            restrictions.patch_at(bytes(data), restrictions.PREFERRED + 0x3000,
                                   restrictions.PREFERRED + 0x1000, restrictions.ORIGINAL)

    def test_wrong_prologue_rejected(self):
        data = bytearray(self.fixture()); data[0x3000] ^= 1
        with self.assertRaises(ValueError):
            restrictions.patch_at(bytes(data), restrictions.PREFERRED + 0x3000,
                                   restrictions.PREFERRED + 0x1000, restrictions.ORIGINAL)


class ReminderTests(unittest.TestCase):
    def test_one_byte_change(self):
        original = b'prefix\0' + reminder.TARGET + b'\0suffix'
        patched, _ = reminder.patch_reminder(original)
        self.assertEqual(len(original), len(patched))
        self.assertEqual(sum(a != b for a, b in zip(original, patched)), 1)
        self.assertIn(reminder.DISABLED, patched)

    def test_ambiguous_or_missing_target_rejected(self):
        for data in [b'unknown', reminder.TARGET + reminder.TARGET]:
            with self.assertRaises(ValueError):
                reminder.patch_reminder(data)


if __name__ == '__main__':
    unittest.main(verbosity=2)
