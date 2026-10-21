"""Use the native playback key request mode for offline-track requests.

Only the immediate w2 at the verified offline caller changes. The requester,
file identifier, callbacks, C++ returned handle and native persistence stay on
Spotify's existing path. mode0 is also used by native key consumers; mode1 is
used by the offline plugin and mode2 by native prefetch. Device testing required.
"""
import struct
from patch_native_restrictions import layout, UUID

CALL_SITE=0x103a6565c
WINDOW=0x103a65650
ORIGINAL=bytes.fromhex('e4e30191e5c30091e00317aa2200805220013fd6a18301d1')
PROVIDER=0x108fa7878
PROVIDER_HEAD=bytes.fromhex('ff0306d1fc6f12a9fa6713a9f85f14a9f65715a9f44f16a9fd7b17a9fdc30591f50305aaf40300aaf70308aa08404239')
MAPPING=0x108fa7960
MAPPING_BYTES=bytes.fromhex('f60301aa5f080071480080520815881a5f0000711c159f1a')

def patch(data):
    _,_,segments,uuid=layout(data)
    if uuid!=UUID:raise ValueError('Unsupported Spotify UUID')
    def offset(address,size):
        for name,vm,vmsize,fileoff,filesize,prot in segments:
            if name==b'__TEXT' and vm<=address and address+size<=vm+filesize and prot&5==5:
                return fileoff+address-vm
        raise ValueError('Expected executable file-backed text')
    for address,expected in [(WINDOW,ORIGINAL),(PROVIDER,PROVIDER_HEAD),(MAPPING,MAPPING_BYTES)]:
        at=offset(address,len(expected))
        if data[at:at+len(expected)]!=expected:raise ValueError(f'Key requester code differs at {address:#x}')
    out=bytearray(data);at=offset(CALL_SITE,4)
    struct.pack_into('<I',out,at,0x52800002) # mov w2,#0; preserve all other registers
    assert len(out)==len(data) and out[at:at+4]==bytes.fromhex('02008052')
    return bytes(out),{'caller':hex(CALL_SITE),'provider':hex(PROVIDER),'original_mode':1,'request_mode':0,
        'original_instruction':data[at:at+4].hex(),'replacement_instruction':out[at:at+4].hex(),
        'native_callbacks_and_persistence_unchanged':True}


DLSYM_STUB=0x10a16f0cc
DLSYM_STUB_HEAD=bytes.fromhex('503801f010c245f900021fd6')

def _verify_dlsym_binding(data):
    cursor = 32
    symtab = dysym = stubs = None
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, length = struct.unpack_from('<II', data, cursor)
        if command == 2:
            symtab = struct.unpack_from('<IIII', data, cursor + 8)
        elif command == 0xB:
            dysym = struct.unpack_from('<IIIIIIIIIIIIIIIIII', data, cursor + 8)
        elif command == 0x19:
            for index in range(struct.unpack_from('<I', data, cursor + 64)[0]):
                section = cursor + 72 + index * 80
                if data[section:section + 16].split(b'\0')[0] == b'__stubs':
                    address, size = struct.unpack_from('<QQ', data, section + 32)
                    first, width = struct.unpack_from('<II', data, section + 68)
                    if address <= DLSYM_STUB < address + size:
                        stubs = (address, first, width)
        cursor += length
    if not symtab or not dysym or not stubs:
        raise ValueError('Cannot verify dlsym import binding')
    address, first, width = stubs
    if width != 12 or (DLSYM_STUB - address) % width:
        raise ValueError('dlsym stub layout changed')
    index = struct.unpack_from('<I', data, dysym[12] + 4 * (first + (DLSYM_STUB - address) // width))[0]
    if index >= symtab[1]:
        raise ValueError('dlsym indirect symbol index invalid')
    string = symtab[2] + struct.unpack_from('<I', data, symtab[0] + 16 * index)[0]
    if data[string:data.index(b'\0', string)] != b'_dlsym':
        raise ValueError('Expected dlsym stub is bound to another symbol')
