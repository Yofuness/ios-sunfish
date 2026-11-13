#!/bin/bash
# sunfish (patches-12377 0002): stage the firehose compatibility header IOS-26-Hot's 0134 patches.
# IOS-26-Hot builds with darwin-xnu-build bd88697, whose patches/26.0/00_setup_coreentitlements.sh wrote this
# stub into EXTERNAL_HEADERS/os (0000 then keeps it). Our dxb 6639065 drops that stub (it uses libdispatch's
# header from the fakeroot) and KDK_MODE=fake removes 00_setup, so 0000 leaves only a 6-line typedef stub, which
# shadows the real header (INCFLAGS_EXTERN precedes INCFLAGS_SDK) and 0134 does not apply. Write dxb bd88697's
# stub (MIT, blacktop) verbatim, as Hot's CI had it. Runs from the XNU source root after 0000.
# Off: SWEET_FIREHOSE_STUB=0 in the build environment (then also drop 0134 from the series).
set -euo pipefail

[[ "${MACHINE_CONFIG:-}" == SWEET ]] || exit 0
[[ "${SWEET_FIREHOSE_STUB:-1}" == 0 ]] && exit 0
[[ -d EXTERNAL_HEADERS ]] || exit 1

mkdir -p EXTERNAL_HEADERS/os
cat > EXTERNAL_HEADERS/os/firehose_buffer_private.h <<'EOF'
#ifndef _OS_FIREHOSE_BUFFER_PRIVATE_H_
#define _OS_FIREHOSE_BUFFER_PRIVATE_H_

#include <stdbool.h>
#include <stdint.h>
#include <mach/vm_types.h>
#include <firehose/firehose_types_private.h>

struct firehose_buffer_range_s {
    uint16_t fbr_offset;
    uint16_t fbr_length;
};

#define FIREHOSE_BUFFER_KERNEL_CHUNK_COUNT 1
#define FIREHOSE_BUFFER_KERNEL_DEFAULT_CHUNK_COUNT 64
#define FIREHOSE_BUFFER_KERNEL_DEFAULT_IO_PAGES 0

__BEGIN_DECLS

firehose_tracepoint_t __firehose_buffer_tracepoint_reserve(uint64_t timestamp,
    firehose_stream_t stream,
    uint16_t pub_size,
    uint16_t priv_size,
    uint8_t **priv_data_out);

void __firehose_buffer_tracepoint_flush(firehose_tracepoint_t ft,
    firehose_tracepoint_id_u ftid);

void __firehose_buffer_push_to_logd(firehose_buffer_t fb, bool for_io);
void __firehose_allocate(vm_offset_t *addr, vm_size_t size);
void __firehose_critical_region_enter(void);
void __firehose_critical_region_leave(void);

bool __firehose_kernel_configuration_valid(uint32_t chunk_count, uint32_t io_pages);
firehose_buffer_t __firehose_buffer_create(size_t *size);
bool __firehose_merge_updates(firehose_push_reply_t reply);

__END_DECLS

#endif /* _OS_FIREHOSE_BUFFER_PRIVATE_H */
EOF
echo "Staged the dxb bd88697 firehose_buffer_private.h stub for SWEET (IOS-26-Hot 0134 base)"
