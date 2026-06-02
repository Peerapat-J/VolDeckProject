#include <stdint.h>
#include <stdatomic.h>

uint64_t VolDeckAudioBridgeAtomicLoadUInt64(const uint64_t *value)
{
    return atomic_load_explicit((const _Atomic uint64_t *)value, memory_order_acquire);
}

void VolDeckAudioBridgeAtomicStoreUInt64(uint64_t *value, uint64_t newValue)
{
    atomic_store_explicit((_Atomic uint64_t *)value, newValue, memory_order_release);
}

uint64_t VolDeckAudioBridgeAtomicFetchAddUInt64(uint64_t *value, uint64_t amount)
{
    return atomic_fetch_add_explicit((_Atomic uint64_t *)value, amount, memory_order_acq_rel);
}
