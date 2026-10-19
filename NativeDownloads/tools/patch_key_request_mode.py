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
