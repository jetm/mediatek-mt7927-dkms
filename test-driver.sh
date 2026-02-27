#!/usr/bin/env bash
# Quick validation script for mediatek-mt7927-dkms.
# Runs in <30 seconds. Non-destructive - does not change WiFi config.
# Paste the output block into GitHub issues for structured reporting.
#
# Usage:
#   ./test-driver.sh            # auto-detect interface
#   ./test-driver.sh wlp9s0     # specify interface

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
ok()   { echo "OK${1:+ ($1)}"; }
fail() { echo "FAIL${1:+ ($1)}"; }
skip() { echo "SKIP${1:+ ($1)}"; }
na()   { echo "N/A${1:+ ($1)}"; }

# grep wrapper: avoids SIGPIPE with pipefail by not using -q
has_match() { grep "$@" > /dev/null 2>&1; }

join_parts() {
    local IFS=','
    local joined="${*}"
    # Insert space after each comma
    echo "${joined//,/, }"
}

# ---------------------------------------------------------------------------
# 1. Package version
# ---------------------------------------------------------------------------
get_package_version() {
    if command -v pacman &>/dev/null; then
        pacman -Q mediatek-mt7927-dkms 2>/dev/null | awk '{print $2}' || echo "not installed"
    else
        echo "unknown (no pacman)"
    fi
}

# ---------------------------------------------------------------------------
# 2. Kernel version
# ---------------------------------------------------------------------------
get_kernel_version() {
    uname -r
}

# ---------------------------------------------------------------------------
# 3. PCI ID
# ---------------------------------------------------------------------------
get_pci_id() {
    local id=""
    for dev in /sys/bus/pci/drivers/mt7925e/*/vendor; do
        if [[ -f "$dev" ]]; then
            local dir
            dir="$(dirname "$dev")"
            local vendor device
            vendor="$(cat "$dir/vendor" 2>/dev/null | sed 's/^0x//')"
            device="$(cat "$dir/device" 2>/dev/null | sed 's/^0x//')"
            id="${vendor}:${device}"
            break
        fi
    done
    echo "${id:-not found}"
}

# ---------------------------------------------------------------------------
# 4. Module loading
# ---------------------------------------------------------------------------
check_modules() {
    local expected=(mt7925e mt76 mt76_connac_lib mt792x_lib)
    local loaded=()
    local missing=()

    local lsmod_out
    lsmod_out="$(lsmod)"

    for mod in "${expected[@]}"; do
        if echo "$lsmod_out" | has_match -w "$mod"; then
            loaded+=("$mod")
        else
            missing+=("$mod")
        fi
    done

    if (( ${#missing[@]} == 0 )); then
        ok "$(join_parts "${loaded[@]}")"
    else
        fail "missing: $(join_parts "${missing[@]}")"
    fi
}

# ---------------------------------------------------------------------------
# 5. DKMS build status
# ---------------------------------------------------------------------------
check_dkms() {
    if ! command -v dkms &>/dev/null; then
        skip "dkms not found"
        return
    fi

    local status
    status="$(dkms status mediatek-mt7927 2>/dev/null)" || true

    if [[ -z "$status" ]]; then
        fail "not in DKMS tree"
        return
    fi

    # Check for "installed" status for current kernel
    if echo "$status" | has_match "installed"; then
        local ver
        ver="$(echo "$status" | grep -oP 'mediatek-mt7927[,/]\s*\K[0-9.]+' | head -1 || true)"
        ok "${ver:+v${ver}, }$(echo "$status" | grep -oP 'installed' | head -1)"
    else
        fail "$(echo "$status" | head -1)"
    fi
}

# ---------------------------------------------------------------------------
# 6. Module source (DKMS vs built-in)
# ---------------------------------------------------------------------------
check_module_source() {
    local mod_path
    mod_path="$(modinfo -n mt7925e 2>/dev/null)" || true

    if [[ -z "$mod_path" ]]; then
        skip "mt7925e not found"
        return
    fi

    if echo "$mod_path" | has_match "updates/dkms"; then
        ok "DKMS"
    elif echo "$mod_path" | has_match "kernel/"; then
        fail "built-in (DKMS module not loaded)"
    else
        ok "$mod_path"
    fi
}

# ---------------------------------------------------------------------------
# 7. Firmware loading from dmesg
# ---------------------------------------------------------------------------
check_firmware() {
    local dmesg_out=""
    dmesg_out="$(dmesg 2>/dev/null || sudo dmesg 2>/dev/null || true)"

    if [[ -z "$dmesg_out" ]]; then
        skip "dmesg not accessible (try with sudo)"
        return
    fi

    local mt_dmesg
    mt_dmesg="$(echo "$dmesg_out" | grep -E 'mt7925e|MT6639' || true)"

    local hw_ver=""
    local wm_ver=""

    hw_ver="$(echo "$mt_dmesg" | grep -oP 'HW/SW Version:\s*\K[^,]+' | tail -1 || true)"
    wm_ver="$(echo "$mt_dmesg" | grep -oP 'WM Firmware Version:\s*\K[^,]+' | tail -1 || true)"

    if [[ -n "$hw_ver" || -n "$wm_ver" ]]; then
        ok "HW ${hw_ver:-?}, WM ${wm_ver:-?}"
    else
        fail "no firmware version in dmesg"
    fi
}

# ---------------------------------------------------------------------------
# 8. Interface detection (auto via sysfs)
# ---------------------------------------------------------------------------
detect_interface() {
    local iface=""

    # Method 1: sysfs driver binding
    for dev_path in /sys/bus/pci/drivers/mt7925e/*/net/*; do
        if [[ -d "$dev_path" ]]; then
            iface="$(basename "$dev_path")"
            break
        fi
    done

    # Method 2: fallback via /sys/class/net
    if [[ -z "$iface" ]]; then
        for net in /sys/class/net/*; do
            local driver_link="${net}/device/driver"
            if [[ -L "$driver_link" ]]; then
                local driver_name
                driver_name="$(basename "$(readlink "$driver_link")")"
                if [[ "$driver_name" == "mt7925e" ]]; then
                    iface="$(basename "$net")"
                    break
                fi
            fi
        done
    fi

    echo "$iface"
}

# ---------------------------------------------------------------------------
# 9. WiFi scan - report available bands
# ---------------------------------------------------------------------------
check_scan() {
    local iface="$1"

    if [[ -z "$iface" ]]; then
        skip "no interface"
        return
    fi

    local scan_out=""
    scan_out="$(iw dev "$iface" scan 2>/dev/null || sudo iw dev "$iface" scan 2>/dev/null || true)"

    if [[ -z "$scan_out" ]]; then
        skip "scan failed (interface down or needs sudo)"
        return
    fi

    local count_2g=0 count_5g=0 count_6g=0
    local freqs
    freqs="$(echo "$scan_out" | grep -oP 'freq:\s*\K[0-9]+' || true)"

    while IFS= read -r freq; do
        [[ -z "$freq" ]] && continue
        if (( freq >= 2400 && freq <= 2500 )); then
            count_2g=$(( count_2g + 1 ))
        elif (( freq >= 5150 && freq <= 5900 )); then
            count_5g=$(( count_5g + 1 ))
        elif (( freq >= 5925 )); then
            count_6g=$(( count_6g + 1 ))
        fi
    done <<< "$freqs"

    local total=$(( count_2g + count_5g + count_6g ))
    if (( total > 0 )); then
        ok "2.4 GHz: ${count_2g}, 5 GHz: ${count_5g}, 6 GHz: ${count_6g}"
    else
        fail "no APs found"
    fi
}

# ---------------------------------------------------------------------------
# 10. Connection status
# ---------------------------------------------------------------------------
check_connection() {
    local iface="$1"

    if [[ -z "$iface" ]]; then
        skip "no interface"
        return
    fi

    local link_out
    link_out="$(iw dev "$iface" link 2>/dev/null)" || true

    if echo "$link_out" | has_match "Not connected"; then
        na "not connected"
        return
    fi

    local ssid freq signal tx_bitrate
    ssid="$(echo "$link_out" | grep -oP 'SSID:\s*\K.*' || true)"
    freq="$(echo "$link_out" | grep -oP 'freq:\s*\K[0-9]+' || true)"
    signal="$(echo "$link_out" | grep -oP 'signal:\s*\K-?[0-9]+' || true)"
    tx_bitrate="$(echo "$link_out" | grep -oP 'tx bitrate:\s*\K[0-9.]+\s*\S+' || true)"

    # Get auth type: try nmcli first (works with NM), fall back to wpa_cli
    local auth=""
    if command -v nmcli &>/dev/null; then
        local active_uuid
        active_uuid="$(nmcli -t -f UUID,TYPE connection show --active 2>/dev/null \
            | grep '802-11-wireless' | head -1 | cut -d: -f1 || true)"
        if [[ -n "$active_uuid" ]]; then
            auth="$(nmcli -g 802-11-wireless-security.key-mgmt connection show "$active_uuid" 2>/dev/null || true)"
        fi
    fi
    if [[ -z "$auth" ]]; then
        auth="$(wpa_cli -i "$iface" status 2>/dev/null | grep -oP 'key_mgmt=\K.*' || true)"
    fi

    local parts=()
    [[ -n "$ssid" ]] && parts+=("$ssid")
    [[ -n "$freq" ]] && parts+=("${freq} MHz")
    [[ -n "$auth" ]] && parts+=("$auth")
    [[ -n "$signal" ]] && parts+=("${signal} dBm")
    [[ -n "$tx_bitrate" ]] && parts+=("TX ${tx_bitrate}")

    if (( ${#parts[@]} > 0 )); then
        ok "$(join_parts "${parts[@]}")"
    else
        ok ""
    fi
}

# ---------------------------------------------------------------------------
# 11. Quick data path test (3 pings to gateway)
# ---------------------------------------------------------------------------
check_data_path() {
    local iface="$1"

    if [[ -z "$iface" ]]; then
        skip "no interface"
        return
    fi

    # Check if connected first
    local link_out
    link_out="$(iw dev "$iface" link 2>/dev/null)" || true
    if echo "$link_out" | has_match "Not connected"; then
        skip "not connected"
        return
    fi

    # Find gateway
    local gw=""
    gw="$(ip route show default dev "$iface" 2>/dev/null \
        | grep -oP 'via \K[0-9.]+' | head -1 || true)"
    if [[ -z "$gw" ]]; then
        gw="$(ip route show default 2>/dev/null \
            | grep -oP 'via \K[0-9.]+' | head -1 || true)"
    fi

    if [[ -z "$gw" ]]; then
        skip "no gateway"
        return
    fi

    local ping_out
    ping_out="$(ping -c 3 -W 3 "$gw" 2>&1)" || true

    local received
    received="$(echo "$ping_out" | grep -oP '[0-9]+(?= received)' || echo "0")"
    local avg
    avg="$(echo "$ping_out" | grep -oP 'rtt min/avg/max/mdev = [0-9.]+/\K[0-9.]+' || true)"

    if (( received > 0 )); then
        ok "${received}/3 pings${avg:+, avg ${avg}ms}"
    else
        fail "0/3 pings to ${gw}"
    fi
}

# ---------------------------------------------------------------------------
# 12. Error pattern check in dmesg
# ---------------------------------------------------------------------------
check_errors() {
    local dmesg_out=""
    dmesg_out="$(dmesg 2>/dev/null || sudo dmesg 2>/dev/null || true)"

    if [[ -z "$dmesg_out" ]]; then
        skip "dmesg not accessible"
        return
    fi

    local mt_dmesg
    mt_dmesg="$(echo "$dmesg_out" | grep -iE 'mt76|mt7925|mt7927|mt6639|mt792x' || true)"

    # Look for known bad patterns
    local errors=""
    errors="$(echo "$mt_dmesg" | grep -iE 'error 65539|reason=15|timeout|reset|fail' \
        | grep -ivE 'ASPM|disabling' || true)"

    if [[ -z "$errors" ]]; then
        echo "NONE"
    else
        local count
        count="$(echo "$errors" | wc -l)"
        echo "${count} error(s) found"
        echo "$errors" | tail -5 | while IFS= read -r line; do
            echo "    $line"
        done
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local iface="${1:-}"

    # Auto-detect interface if not specified
    if [[ -z "$iface" ]]; then
        iface="$(detect_interface)"
    fi

    local pkg_ver kernel_ver pci_id
    local modules dkms_status mod_source firmware
    local scan_result conn_result data_result errors_result

    # Gather results
    pkg_ver="$(get_package_version)"
    kernel_ver="$(get_kernel_version)"
    pci_id="$(get_pci_id)"
    modules="$(check_modules)"
    dkms_status="$(check_dkms)"
    mod_source="$(check_module_source)"
    firmware="$(check_firmware)"
    scan_result="$(check_scan "$iface")"
    conn_result="$(check_connection "$iface")"
    data_result="$(check_data_path "$iface")"
    errors_result="$(check_errors)"

    # Print structured report
    cat <<EOF
## Driver Validation Report
- Package: mediatek-mt7927-dkms ${pkg_ver}
- Kernel: ${kernel_ver}
- PCI ID: ${pci_id}
- Modules: ${modules}
- DKMS: ${dkms_status}
- Module source: ${mod_source}
- Firmware: ${firmware}
- Interface: ${iface:-not found}
- Scan: ${scan_result}
- Connection: ${conn_result}
- Data path: ${data_result}
- Errors: ${errors_result}
EOF
}

main "$@"
