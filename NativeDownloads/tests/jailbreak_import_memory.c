#include "../jailbreak/ImportMemory.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    vm_address_t page = 0;
    assert(vm_allocate(mach_task_self(), &page, vm_page_size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS);
    uintptr_t *slot = (uintptr_t *)page;
    *slot = 123;
    assert(vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ) == KERN_SUCCESS);
    vm_prot_t original, current;
    assert(SAPJBPointerProtection(page, &original) && original == VM_PROT_READ);
    assert(SAPJBWritePointer(page, 456, original) && *slot == 456);
    assert(SAPJBPointerProtection(page, &current) && current == original);
    assert(SAPJBWritePointer(page, 123, original) && *slot == 123);
    assert(SAPJBPointerProtection(page, &current) && current == original);
    assert(!SAPJBWritePointer(page+1, 789, original) && *slot == 123);
    assert(!SAPJBWritePointer(0, 789, original));
    assert(!SAPJBWritePointer(page, 789, VM_PROT_READ | VM_PROT_EXECUTE) && *slot == 123);
    assert(vm_deallocate(mach_task_self(), page, vm_page_size) == KERN_SUCCESS);
    assert(!SAPJBWritePointer(page, 789, original));
    puts("Jailbreak import write/protection/restore tests passed");
}
