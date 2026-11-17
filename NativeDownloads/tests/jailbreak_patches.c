#include "../jailbreak/GuardedPatches.h"
#include <assert.h>
#include <stdio.h>

static const uint8_t zero[4]={0}, entry[4]={1,2,3,4}, payload[4]={5,6,7,8}, branch[4]={9,10,11,12};
static const uint8_t importBefore[4]={13,14,15,16}, importAfter[4]={17,18,19,20}, guard[4]={21,22,23,24};
static const SAPJBPatch patches[]={
    {0,4,entry,branch,1}, {8,4,zero,payload,0},
    {16,4,importBefore,importAfter,2}, {24,4,guard,guard,1}
};
typedef struct {uint8_t memory[32], original[32];unsigned writes,failAt;bool persistent,readFailure;uintptr_t order[16];} State;
static State fresh(void) {
    State state={0};
    for(size_t i=0;i<4;i++)memcpy(state.memory+patches[i].offset,patches[i].before,4);
    memcpy(state.original,state.memory,32);return state;
}
static bool readBytes(void *context,uintptr_t offset,void *out,size_t size) {
    State *state=context;
    if(state->readFailure||offset>32||size>32-offset)return false;
    memcpy(out,state->memory+offset,size);return true;
}
static bool writeBytes(void *context,uintptr_t offset,const void *bytes,size_t size) {
    State *state=context;assert(state->writes<16);state->order[state->writes++]=offset;
    bool fail=state->failAt&&(state->writes==state->failAt||(state->persistent&&state->writes>state->failAt));
    if(fail){if(!state->persistent)memcpy(state->memory+offset,bytes,size/2);return false;}
    memcpy(state->memory+offset,bytes,size);return true;
}
static SAPJBResult apply(State *state) {return SAPJBApply(state,readBytes,writeBytes,patches,4);}
int main(void) {
    State state=fresh();assert(apply(&state)==SAPJBInstalled);
    assert(state.writes==3&&state.order[0]==8&&state.order[1]==0&&state.order[2]==16);
    assert(apply(&state)==SAPJBAlreadyInstalled&&state.writes==3);
    for(unsigned fail=1;fail<=3;fail++){
        state=fresh();state.failAt=fail;assert(apply(&state)==SAPJBWriteFailed);
        assert(!memcmp(state.memory,state.original,32));
    }
    // Refuse any mismatch before writing, including a supposedly unchanged guard.
    for(unsigned offset=0;offset<28;offset+=8){state=fresh();state.memory[offset]^=0xff;assert(apply(&state)==SAPJBConflict&&state.writes==0);}
    state=fresh();memcpy(state.memory+8,payload,4);assert(apply(&state)==SAPJBConflict&&state.writes==0);
    state=fresh();state.readFailure=true;assert(apply(&state)==SAPJBConflict&&state.writes==0);
    // If an entry cannot be restored, leave its executable payload in place.
    state=fresh();state.failAt=3;state.persistent=true;assert(apply(&state)==SAPJBRollbackFailed);
    assert(!memcmp(state.memory,branch,4)&&!memcmp(state.memory+8,payload,4));
    puts("Guarded jailbreak patch transaction tests passed");
}
