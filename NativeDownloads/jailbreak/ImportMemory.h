#pragma once
#include <mach/mach.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

// Import slots are data, not executable code. Restore their original protection
// after the aligned pointer write; code patches use the jailbreak backend.
static inline bool SAPJBPointerProtection(uintptr_t address, vm_prot_t *protection) {
    if (!address || address % sizeof(uintptr_t) || address > UINTPTR_MAX-sizeof(uintptr_t)) return false;
    vm_address_t region = address;
    vm_size_t length = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t result = vm_region_64(mach_task_self(), &region, &length, VM_REGION_BASIC_INFO_64,
        (vm_region_info_64_t)&info, &count, &object);
    if (MACH_PORT_VALID(object)) mach_port_deallocate(mach_task_self(), object);
    if (result != KERN_SUCCESS || region > address || address-region > length ||
        sizeof(uintptr_t) > length-(address-region) || !(info.protection & VM_PROT_READ) ||
        (info.protection & VM_PROT_EXECUTE)) return false;
    *protection = info.protection;
    return true;
}

static inline bool SAPJBWritePointer(uintptr_t address, uintptr_t value, vm_prot_t original) {
    vm_prot_t observed;
    if (!SAPJBPointerProtection(address, &observed) || !(original & VM_PROT_READ) ||
        (original & VM_PROT_EXECUTE)) return false;
    vm_address_t page = address & ~((uintptr_t)vm_page_size-1);
    if (vm_protect(mach_task_self(), page, vm_page_size, FALSE,
        original | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) return false;
    atomic_store_explicit((_Atomic(uintptr_t) *)address, value, memory_order_release);
    return vm_protect(mach_task_self(), page, vm_page_size, FALSE, original) == KERN_SUCCESS;
}
