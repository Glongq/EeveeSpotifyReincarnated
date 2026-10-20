"""Validate/apply the two guarded native patches, also on a prepared input.

Normalizes ONLY exact known patch bytes and then runs both original patchers.
Unknown code, UUIDs, partial trampolines and occupied padding remain errors.
"""
import struct
import patch_native_restrictions as limits
import patch_key_request_mode as keys


def prepare(data):
    _, _, segments, uuid = limits.layout(data)
    if uuid != limits.UUID:
        raise ValueError('Unsupported Spotify UUID')

    def offset(address, size):
        for name, vm, _, fileoff, filesize, prot in segments:
            if name == b'__TEXT' and vm <= address and address + size <= vm + filesize and prot & 5 == 5:
                return fileoff + address - vm
        raise ValueError('Patch outside executable file-backed text')

    original = bytearray(data)
    setter = offset(limits.SETTER, len(limits.ORIGINAL))
    cave = offset(limits.CAVE, len(limits.trampoline()))
    key = offset(keys.CALL_SITE, 4)
    branch = struct.pack('<I', limits.branch(limits.SETTER, limits.CAVE))
    quota_patched = data[setter:setter+4] == branch
    key_patched = data[key:key+4] == bytes.fromhex('02008052')
    if quota_patched:
        if data[setter+4:setter+len(limits.ORIGINAL)] != limits.ORIGINAL[4:] or data[cave:cave+len(limits.trampoline())] != limits.trampoline():
            raise ValueError('Incomplete or unknown native quota patch')
        original[setter:setter+4] = limits.ORIGINAL[:4]
        original[cave:cave+len(limits.trampoline())] = bytes(len(limits.trampoline()))
    if key_patched:
        original[key:key+4] = bytes.fromhex('22008052')
    # All original guard windows/provider/mapping checks run even for patched input.
    result, quota_report = limits.patch(bytes(original))
    result, key_report = keys.patch(result)
    if quota_patched and key_patched and result != data:
        raise ValueError('Prepared image did not round-trip exactly')
    return result, {'quota': quota_report, 'key': key_report,
                    'input_quota_patched': quota_patched, 'input_key_patched': key_patched,
                    'executable_patches_ready': True}
