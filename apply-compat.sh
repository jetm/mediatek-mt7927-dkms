#!/bin/bash
# Apply kernel compatibility fixes for building mt76 6.19 source against older kernels.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <kernel-headers-dir> <mt76-source-dir>" >&2
    exit 1
fi

KHEADERS="$1"
MT76_SRC="$2"

if [[ ! -d "${KHEADERS}" ]]; then
    echo "ERROR: kernel headers directory not found: ${KHEADERS}" >&2
    exit 1
fi

if [[ ! -d "${MT76_SRC}" ]]; then
    echo "ERROR: mt76 source directory not found: ${MT76_SRC}" >&2
    exit 1
fi

# Fix 1: airoha_offload.h (introduced in Linux 6.19, required by mt76 wed.c)
# Add a recursive include flag so both mt76 and mt792{1,5} subdirs
# can find the header extracted from the kernel tarball at build time.
AIROHA_SYS="${KHEADERS}/include/linux/soc/airoha/airoha_offload.h"
if [[ ! -f "${AIROHA_SYS}" ]]; then
    AIROHA_COMPAT="${MT76_SRC}/compat/include/linux/soc/airoha/airoha_offload.h"
    KBUILD="${MT76_SRC}/Kbuild"
    FLAG='subdir-ccflags-y += -I$(src)/compat/include'

    if [[ ! -f "${AIROHA_COMPAT}" ]]; then
        echo "ERROR: compat header not found: ${AIROHA_COMPAT}" >&2
        exit 1
    fi

    if [[ -f "${KBUILD}" ]] && ! grep -qF "${FLAG}" "${KBUILD}"; then
        sed -i "1i ${FLAG}" "${KBUILD}"
        echo "compat: added recursive compat include path to mt76 Kbuild for airoha_offload.h"
    else
        echo "compat: recursive compat include path already in Kbuild, skipped"
    fi
else
    echo "compat: airoha_offload.h already present in kernel headers, skipped"
fi

