"""Run the DEB patch engine against private mappings of the actual Spotify image."""
import ctypes as C
import mmap
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import patch_native_restrictions as quota
import patch_key_request_mode as key
import patch_native_trace as trace
from build_debs import generate_header

fixture, build = map(Path, sys.argv[1:])
root = Path(__file__).resolve().parents[1]
generate_header(build)
library = build/'patch-tests.dylib'
subprocess.run(['xcrun','clang','-dynamiclib','-Wall','-Wextra','-Werror','-I'+str(root/'src'),
                '-I'+str(build),str(root/'src/JailbreakPatches.c'),'-o',str(library)],check=True)
engine = C.CDLL(str(library)).SAPJBApplyPatches
Writer = C.CFUNCTYPE(None,C.c_void_p,C.c_void_p,C.c_size_t,C.c_void_p)
engine.argtypes = [C.c_void_p,C.c_size_t,Writer,C.c_void_p,C.POINTER(C.c_char_p)]
engine.restype = C.c_bool
data = fixture.read_bytes()
_,_,segments,_ = quota.layout(data)
text_size = next(s[4] for s in segments if s[0]==b'__TEXT')
del data
setter, cave, call = quota.SETTER-quota.PREFERRED,quota.CAVE-quota.PREFERRED,key.CALL_SITE-quota.PREFERRED
key_cave=key.CAVE-quota.PREFERRED
key_thunk=key.trampoline()
spans = [(setter,len(quota.ORIGINAL)),(cave,len(quota.trampoline())),(call,4),(key_cave,len(key_thunk))]
for point in trace.POINTS:
    spans.extend([(point[1]-quota.PREFERRED, len(point[3])), (point[2]-quota.PREFERRED,len(trace.trampoline(point)))])

def case(name, edit=None, expected=True, write_fail=0, expected_writes=None, repeat=False):
    with fixture.open('rb') as source, mmap.mmap(source.fileno(),0,access=mmap.ACCESS_COPY) as image:
        if edit:edit(image)
        before = [image[a:a+n] for a,n in spans]
        address = C.addressof(C.c_char.from_buffer(image));writes=[]
        @Writer
        def writer(target, content, length, context):
            writes.append((target-address,length))
            if len(writes)!=write_fail:C.memmove(target,content,length)
        reason = C.c_char_p()
        result = engine(address,text_size,writer,None,C.byref(reason))
        assert result==expected,(name,result,reason.value)
        if expected_writes is not None:assert len(writes)==expected_writes,(name,writes)
        if result:
            assert image[setter:setter+4]==quota.branch(quota.SETTER,quota.CAVE).to_bytes(4,'little')
            assert image[cave:cave+len(quota.trampoline())]==quota.trampoline()
            for point in trace.POINTS:
                entry,body=point[1]-quota.PREFERRED,point[2]-quota.PREFERRED
                assert image[entry:entry+4]==quota.branch(point[1],point[2]).to_bytes(4,'little')
                assert image[body:body+len(trace.trampoline(point))]==trace.trampoline(point)
        elif write_fail:assert [image[a:a+n] for a,n in spans]==before,(name,'rollback')
        else:assert not writes,(name,'wrote before validation')
        if repeat:
            writes.clear();assert engine(address,text_size,writer,None,C.byref(reason))
            assert not writes and reason.value==b'already_applied'
        print('PASS:',name,reason.value.decode(),flush=True)

case('stock image + idempotence',expected_writes=8,repeat=True)
def wrong_uuid(b):
    at=32
    for _ in range(int.from_bytes(b[16:20],'little')):
        command=int.from_bytes(b[at:at+4],'little');length=int.from_bytes(b[at+4:at+8],'little')
        if command==0x1b:b[at+8]=b[at+8]^1;return
        at+=length
    raise AssertionError('Missing UUID')
case('unsupported UUID',wrong_uuid,False,expected_writes=0)
case('wrong setter',lambda b:b.__setitem__(setter, b[setter]^1),False,expected_writes=0)
case('occupied header padding',lambda b:b.__setitem__(cave,1),False,expected_writes=0)
case('occupied key-mode padding',lambda b:b.__setitem__(key_cave,1),False,expected_writes=0)
case('wrong key caller',lambda b:b.__setitem__(call,b[call]^1),False,expected_writes=0)
provider=key.PROVIDER-quota.PREFERRED
case('wrong key provider',lambda b:b.__setitem__(provider,b[provider]^1),False,expected_writes=0)
mapping=key.MAPPING-quota.PREFERRED
case('wrong key mapping',lambda b:b.__setitem__(mapping,b[mapping]^1),False,expected_writes=0)
stub=key.DLSYM_STUB-quota.PREFERRED
case('wrong dlsym stub',lambda b:b.__setitem__(stub,b[stub]^1),False,expected_writes=0)
for point in trace.POINTS:
    case('occupied '+point[0]+' observer padding',lambda b,p=point:b.__setitem__(p[2]-quota.PREFERRED,1),False,expected_writes=0)
for point in trace.POINTS[1:]:
    case('wrong '+point[0]+' callback',lambda b,p=point:b.__setitem__(p[1]-quota.PREFERRED,b[p[1]-quota.PREFERRED]^1),False,expected_writes=0)
for step in range(1,9):case('rollback after failed write '+str(step),expected=False,write_fail=step)
def guarded(b):
    b[cave:cave+len(quota.trampoline())]=quota.trampoline()
    b[setter:setter+4]=quota.branch(quota.SETTER,quota.CAVE).to_bytes(4,'little')
case('existing quota guard',guarded,expected_writes=6)
case('existing mode zero',lambda b:b.__setitem__(slice(call,call+4),bytes.fromhex('02008052')),expected_writes=8)
print('PASS: all DEB native patch guards, idempotence and rollback checks')

def runtime_mode(b):
    b[key_cave:key_cave+len(key_thunk)]=key_thunk
    b[call:call+4]=quota.branch(key.CALL_SITE,key.CAVE).to_bytes(4,'little')
case('upgrade old runtime selector to fixed traced mode zero',runtime_mode,expected_writes=8,repeat=True)
with fixture.open('rb') as source,mmap.mmap(source.fileno(),0,access=mmap.ACCESS_COPY) as image:
    address=C.addressof(C.c_char.from_buffer(image))
    @Writer
    def real_writer(target,content,length,context):C.memmove(target,content,length)
    reason=C.c_char_p();assert engine(address,text_size,real_writer,None,C.byref(reason))
    expected,_=quota.patch(fixture.read_bytes());expected,_=key.patch(expected,runtime_selectable=False);expected,_=trace.patch(expected)
    assert image[:]==expected
print('PASS: DEB in-memory native patches exactly match the current IPA patches; fixed mode zero and three diagnostic boundaries')
