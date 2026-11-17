"""Reuse the IPA patchers to generate a guarded, version-specific memory plan.

Only patch bytes and import-slot offsets are retained, never the app executable.
The jailbreak loader supplies the dependency instead of editing LC_LOAD_DYLIB;
resolved import slots replace the IPA path's chained-import ordinal edits.
"""
import struct

from pixie_target import PROFILE
from patch_imports import SYMBOLS, patch as patch_imports
from patch_native_restrictions import layout, patch as patch_limits
from patch_key_request_mode import patch as patch_key
from patch_native_trace import patch as patch_trace
from patch_export import patch as patch_export


def import_slots(data):
    # Validate the same five symbols and providers as the normal IPA builder.
    _, report = patch_imports(data)
    wanted = {change['import_index']: change['symbol'][1:] for change in report['changes']}
    segments, fixups = [], None
    cursor = 32
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, size = struct.unpack_from('<II', data, cursor)
        if command == 0x19:
            segments.append(struct.unpack_from('<QQQQ', data, cursor+24))
        elif command == 0x80000034:
            fixups = struct.unpack_from('<II', data, cursor+8)
        cursor += size
    base, length = fixups
    _, starts, _, _, _, _, _ = struct.unpack_from('<7I', data, base)
    starts += base
    count = struct.unpack_from('<I', data, starts)[0]
    if count != len(segments):
        raise ValueError('Unexpected chained-fixups segment count')
    found = []
    for i, (vm, vmsize, fileoff, filesize) in enumerate(segments):
        relative = struct.unpack_from('<I', data, starts+4+4*i)[0]
        if not relative:
            continue
        at = starts+relative
        size, page_size, pointer_format, segment_offset, _, pages = struct.unpack_from('<IHHQIH', data, at)
        if pointer_format != 6 or segment_offset != vm-int(PROFILE['preferred_address'], 16):
            raise ValueError('Only the verified arm64 OFFSET chained-pointer format is supported')
        if at+size > base+length or 22+pages*2 > size:
            raise ValueError('Invalid chained page table')
        for page in range(pages):
            start = struct.unpack_from('<H', data, at+22+2*page)[0]
            if start == 0xffff:
                continue
            if start & 0x8000:
                raise ValueError('Unverified multi-start chained page')
            offset, seen = page*page_size+start, set()
            while True:
                if offset in seen or offset+8 > filesize or offset//page_size != page:
                    raise ValueError('Invalid chained pointer')
                seen.add(offset)
                value = struct.unpack_from('<Q', data, fileoff+offset)[0]
                if value >> 63 and (value & 0xffffff) in wanted:
                    # A nonzero addend would not be a direct function import.
                    if (value >> 24) & 0xff:
                        raise ValueError('Audio import has an unexpected addend')
                    found.append((segment_offset+offset, wanted[value & 0xffffff]))
                next_delta = ((value >> 51) & 0xfff)*4
                if not next_delta:
                    break
                offset += next_delta
    if {symbol for _, symbol in found} != {s[1:] for s in SYMBOLS}:
        raise ValueError('Not all IPA audio imports have verified runtime slots')
    return sorted(found)


def make_plan(original):
    _, _, segments, uuid = layout(original)
    if uuid.hex() != PROFILE['uuid']:
        raise ValueError('Unsupported Spotify UUID')
    patched, _ = patch_limits(original)
    patched, _ = patch_key(patched, runtime_selectable=False)
    patched, _ = patch_trace(patched)
    patched, _ = patch_export(patched)
    text = next(s for s in segments if s[0] == b'__TEXT')
    _, vm, _, fileoff, filesize, protection = text
    if protection & 5 != 5 or fileoff or vm != int(PROFILE['preferred_address'], 16):
        raise ValueError('Unexpected executable mapping')
    # Include full original guard windows, not just the changed instruction.
    ranges = []
    def guard(address, count):
        start = int(address, 16)-vm
        ranges.append((start, start+count))
    native = PROFILE['native']
    for name, key in [('setter','setter_original'), ('window','window_original'),
                      ('provider','provider_head'), ('mapping','mapping_original'),
                      ('dlsym_stub','dlsym_stub_head')]:
        guard(native[name], len(bytes.fromhex(native[key])))
    for point in [*PROFILE['trace_points'], *PROFILE['export']['points'].values()]:
        guard(point['address'], len(bytes.fromhex(point['original'])))
    for window in PROFILE['export']['windows'].values():
        guard(window['address'], len(bytes.fromhex(window['bytes'])))
    # Word alignment preserves every ARM64 instruction, including zero bytes.
    for start in range(0, filesize, 4):
        if original[start:start+4] != patched[start:start+4]:
            ranges.append((start, start+4))
    merged = []
    for start, end in sorted(ranges):
        if not 0 <= start < end <= filesize:
            raise ValueError('Patch outside executable text')
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
        else:
            merged.append((start, end))
    plan = []
    check = bytearray(original)
    for start, end in merged:
        before, after = original[start:end], patched[start:end]
        if end-start > 1024:
            raise ValueError('Patch exceeds runtime validation buffer')
        plan.append((start, before, after, 1 if any(before) else 0))
        check[start:end] = after
    if check != patched:
        raise ValueError('Runtime plan differs from IPA native patches')
    return plan, import_slots(original)


def header(plan, imports):
    lines = ['// Generated from the supplied, verified clean Spotify executable.',
             '#pragma once', '#include "GuardedPatches.h"']
    def array(blob):
        return ','.join(f'0x{byte:02x}' for byte in blob)
    for i, (_, before, after, _) in enumerate(plan):
        lines += [f'static const uint8_t SAPJBBefore{i}[]={{{array(before)}}};',
                  f'static const uint8_t SAPJBAfter{i}[]={{{array(after)}}};']
    lines += ['static const SAPJBPatch SAPJBNativePatches[]={']
    for i, (offset, before, _, phase) in enumerate(plan):
        lines += [f'{{0x{offset:x},{len(before)},SAPJBBefore{i},SAPJBAfter{i},{phase}}},']
    lines += ['};', 'static const struct {uintptr_t offset; const char *symbol;} SAPJBImports[]={']
    for offset, symbol in imports:
        lines += [f'{{0x{offset:x},"{symbol}"}},']
    return '\n'.join([*lines, '};', ''])
