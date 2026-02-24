#!/usr/bin/env bash
# MT7927 WiFi stability test - safe to run on a machine actively using WiFi.
# Monitors connection health, signal, kernel logs, and latency without
# touching the interface or disconnecting.
#
# Usage:
#   ./stability-test.sh                  # 8-hour test, auto-detect interface
#   ./stability-test.sh -d 2h            # 2-hour test
#   ./stability-test.sh -d 30m           # 30-minute test
#   ./stability-test.sh -i wlp4s0        # specify interface
#   ./stability-test.sh -s 192.168.1.50  # iperf3 server for throughput tests

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DURATION_SECONDS=$((8 * 3600))  # 8 hours
IFACE=""
IPERF_SERVER=""
PING_INTERVAL=1        # seconds between pings
STATION_INTERVAL=60    # seconds between station dumps
LINK_LOG_INTERVAL=300  # seconds between full link status logs (5 min)
IPERF_INTERVAL=1800    # seconds between iperf3 tests (30 min)
DMESG_INTERVAL=30      # seconds between dmesg checks

# ---------------------------------------------------------------------------
# Globals filled at runtime
# ---------------------------------------------------------------------------
LOG_DIR=""
GATEWAY=""
START_EPOCH=""
PIDS=()
SUMMARY_PRINTED=0

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<'EOF'
MT7927 WiFi Stability Test

Options:
  -d DURATION   Test duration (e.g. 8h, 30m, 3600). Default: 8h
  -i IFACE      WiFi interface name. Default: auto-detect from mt7925e
  -s SERVER     iperf3 server address (optional)
  -h            Show this help

The test is non-disruptive - it will NOT disconnect or reconfigure WiFi.
It monitors: ping latency, signal strength, kernel errors, connection state.
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Parse duration string (e.g. "8h", "30m", "3600") into seconds
# ---------------------------------------------------------------------------
parse_duration() {
    local input="$1"
    local num
    if [[ "$input" =~ ^([0-9]+)h$ ]]; then
        num="${BASH_REMATCH[1]}"
        echo $(( num * 3600 ))
    elif [[ "$input" =~ ^([0-9]+)m$ ]]; then
        num="${BASH_REMATCH[1]}"
        echo $(( num * 60 ))
    elif [[ "$input" =~ ^([0-9]+)s?$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "ERROR: invalid duration '$input' (use e.g. 8h, 30m, 3600)" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Auto-detect WiFi interface bound to mt7925e
# ---------------------------------------------------------------------------
detect_interface() {
    local iface=""

    # Method 1: find net interface under mt7925e PCI device via sysfs
    for dev_path in /sys/bus/pci/drivers/mt7925e/*/net/*; do
        if [[ -d "$dev_path" ]]; then
            iface="$(basename "$dev_path")"
            break
        fi
    done

    # Method 2: fallback - check /sys/class/net/*/device/driver -> mt7925e
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

    if [[ -z "$iface" ]]; then
        echo "ERROR: no WiFi interface found for mt7925e driver." >&2
        echo "Is the mt7925e module loaded? Check: lsmod | grep mt7925e" >&2
        exit 1
    fi

    echo "$iface"
}

# ---------------------------------------------------------------------------
# Timestamp helper
# ---------------------------------------------------------------------------
ts() {
    date '+%Y-%m-%d %H:%M:%S'
}

# ---------------------------------------------------------------------------
# Log to file and stdout
# ---------------------------------------------------------------------------
log() {
    echo "[$(ts)] $*" | tee -a "${LOG_DIR}/main.log"
}

# ---------------------------------------------------------------------------
# Check elapsed time; return 1 if duration exceeded
# ---------------------------------------------------------------------------
time_remaining() {
    local now
    now="$(date +%s)"
    local elapsed=$(( now - START_EPOCH ))
    if (( elapsed >= DURATION_SECONDS )); then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Continuous ping to a target, logging to a file
# ---------------------------------------------------------------------------
run_ping() {
    local target="$1"
    local label="$2"
    local logfile="${LOG_DIR}/ping-${label}.log"

    echo "# Ping to ${target} (${label}), started $(ts)" > "$logfile"

    # ping runs until killed; -D prints timestamps
    ping -D -i "$PING_INTERVAL" -W 3 "$target" >> "$logfile" 2>&1 || true
}

# ---------------------------------------------------------------------------
# Periodic station dump (signal, bitrate, rx/tx stats)
# ---------------------------------------------------------------------------
run_station_monitor() {
    local logfile="${LOG_DIR}/station.log"
    echo "# Station dump every ${STATION_INTERVAL}s, started $(ts)" > "$logfile"

    while time_remaining; do
        {
            echo "--- $(ts) ---"
            iw dev "$IFACE" station dump 2>&1 || echo "(station dump failed)"
            echo ""
        } >> "$logfile"
        sleep "$STATION_INTERVAL" || true
    done
}

# ---------------------------------------------------------------------------
# Periodic link status log (channel, freq, signal, noise, bitrate)
# ---------------------------------------------------------------------------
run_link_monitor() {
    local logfile="${LOG_DIR}/link.log"
    echo "# Link status every ${LINK_LOG_INTERVAL}s, started $(ts)" > "$logfile"

    while time_remaining; do
        {
            echo "--- $(ts) ---"
            # iw link - current connection info
            iw dev "$IFACE" link 2>&1 || echo "(link query failed)"
            echo ""
            # iw info - channel, freq, txpower
            iw dev "$IFACE" info 2>&1 || echo "(info query failed)"
            echo ""
        } >> "$logfile"
        sleep "$LINK_LOG_INTERVAL" || true
    done
}

# ---------------------------------------------------------------------------
# Periodic iperf3 throughput test (only if server specified)
# ---------------------------------------------------------------------------
run_iperf_monitor() {
    local logfile="${LOG_DIR}/iperf3.log"
    echo "# iperf3 to ${IPERF_SERVER} every ${IPERF_INTERVAL}s, started $(ts)" > "$logfile"

    if ! command -v iperf3 &>/dev/null; then
        echo "WARNING: iperf3 not installed, skipping throughput tests" >> "$logfile"
        log "WARNING: iperf3 not found, skipping throughput tests"
        return
    fi

    while time_remaining; do
        {
            echo "--- $(ts) ---"
            # Short 10-second test, TCP, with JSON summary
            iperf3 -c "$IPERF_SERVER" -t 10 --connect-timeout 5000 2>&1 || echo "(iperf3 failed)"
            echo ""
        } >> "$logfile"
        sleep "$IPERF_INTERVAL" || true
    done
}

# ---------------------------------------------------------------------------
# Monitor dmesg for mt76/mt7925 kernel warnings and errors
# ---------------------------------------------------------------------------
run_dmesg_monitor() {
    local logfile="${LOG_DIR}/dmesg-errors.log"
    local seen_file="${LOG_DIR}/.dmesg-seen-lines"
    echo "# Kernel errors/warnings for mt76/mt7925, started $(ts)" > "$logfile"
    echo "0" > "$seen_file"

    while time_remaining; do
        # Grab new dmesg lines related to mt76/mt7925/mt7927/mt6639
        local new_lines
        new_lines="$(dmesg --time-format iso 2>/dev/null || dmesg)" || true
        local filtered
        filtered="$(echo "$new_lines" \
            | grep -iE 'mt76|mt7925|mt7927|mt6639|mt792x' \
            | grep -iE 'error|warn|fail|bug|oops|panic|timeout|reset|unable|fault' \
            || true)"

        if [[ -n "$filtered" ]]; then
            local prev_count
            prev_count="$(cat "$seen_file")"
            local total_count
            total_count="$(echo "$filtered" | wc -l)"
            if (( total_count > prev_count )); then
                # Log only new lines
                echo "$filtered" | tail -n $(( total_count - prev_count )) >> "$logfile"
                echo "$total_count" > "$seen_file"
            fi
        fi

        sleep "$DMESG_INTERVAL" || true
    done
}

# ---------------------------------------------------------------------------
# Track connection drops by watching iw link status
# ---------------------------------------------------------------------------
run_drop_monitor() {
    local logfile="${LOG_DIR}/connection-drops.log"
    echo "# Connection drop monitor, started $(ts)" > "$logfile"

    local was_connected=1
    local drop_count=0

    while time_remaining; do
        local link_output
        link_output="$(iw dev "$IFACE" link 2>&1)" || true

        if echo "$link_output" | grep -q "Not connected"; then
            if (( was_connected )); then
                drop_count=$(( drop_count + 1 ))
                echo "[$(ts)] CONNECTION LOST (drop #${drop_count})" >> "$logfile"
                log "CONNECTION DROP #${drop_count} detected"
                was_connected=0
            fi
        else
            if (( ! was_connected )); then
                echo "[$(ts)] CONNECTION RESTORED" >> "$logfile"
                log "Connection restored after drop #${drop_count}"
                was_connected=1
            fi
        fi

        sleep 5 || true
    done

    echo "total_drops=${drop_count}" >> "$logfile"
}

# ---------------------------------------------------------------------------
# Parse ping log and extract stats
# ---------------------------------------------------------------------------
parse_ping_stats() {
    local logfile="$1"

    if [[ ! -f "$logfile" ]]; then
        echo "  (no data)"
        return
    fi

    local total=0
    local received=0
    local latencies=()

    while IFS= read -r line; do
        # Match lines like: [1234567890.123456] 64 bytes from ... time=12.3 ms
        if [[ "$line" =~ time=([0-9.]+) ]]; then
            total=$(( total + 1 ))
            received=$(( received + 1 ))
            latencies+=("${BASH_REMATCH[1]}")
        # Match timeout/unreachable indicators
        elif [[ "$line" =~ "no answer" || "$line" =~ "unreachable" || "$line" =~ "Request timeout" ]]; then
            total=$(( total + 1 ))
        fi
    done < "$logfile"

    # Also check for ping's own summary if it exited cleanly
    local ping_summary
    ping_summary="$(grep -E 'packets transmitted' "$logfile" 2>/dev/null || true)"
    if [[ -n "$ping_summary" ]]; then
        echo "  $ping_summary"
        local rtt_line
        rtt_line="$(grep -E 'rtt min/avg/max' "$logfile" 2>/dev/null || true)"
        if [[ -n "$rtt_line" ]]; then
            echo "  $rtt_line"
        fi
        return
    fi

    # Manual calculation from parsed lines
    if (( total == 0 )); then
        echo "  (no ping responses recorded)"
        return
    fi

    local lost=$(( total - received ))
    local loss_pct
    if (( total > 0 )); then
        loss_pct="$(awk "BEGIN { printf \"%.1f\", (${lost}/${total})*100 }")"
    else
        loss_pct="0.0"
    fi

    echo "  Sent: ${total}, Received: ${received}, Lost: ${lost} (${loss_pct}%)"

    if (( ${#latencies[@]} > 0 )); then
        local min max sum avg
        min="${latencies[0]}"
        max="${latencies[0]}"
        sum=0
        for lat in "${latencies[@]}"; do
            sum="$(awk "BEGIN { print ${sum} + ${lat} }")"
            if awk "BEGIN { exit (${lat} < ${min}) ? 0 : 1 }"; then
                min="$lat"
            fi
            if awk "BEGIN { exit (${lat} > ${max}) ? 0 : 1 }"; then
                max="$lat"
            fi
        done
        avg="$(awk "BEGIN { printf \"%.2f\", ${sum} / ${#latencies[@]} }")"
        echo "  Latency min/avg/max: ${min}/${avg}/${max} ms"
    fi
}

# ---------------------------------------------------------------------------
# Extract signal strength range from station dumps
# ---------------------------------------------------------------------------
parse_signal_range() {
    local logfile="${LOG_DIR}/station.log"

    if [[ ! -f "$logfile" ]]; then
        echo "  (no data)"
        return
    fi

    local signals
    signals="$(grep -oP 'signal:\s+\K-?[0-9]+' "$logfile" 2>/dev/null || true)"

    if [[ -z "$signals" ]]; then
        echo "  (no signal data captured)"
        return
    fi

    local min max
    min="$(echo "$signals" | sort -n | head -1)"
    max="$(echo "$signals" | sort -n | tail -1)"
    local count
    count="$(echo "$signals" | wc -l)"
    local avg
    avg="$(echo "$signals" | awk '{ sum += $1; n++ } END { if (n>0) printf "%.0f", sum/n }')"

    echo "  Signal range: ${min} to ${max} dBm (avg: ${avg} dBm, ${count} samples)"
}

# ---------------------------------------------------------------------------
# Count kernel errors
# ---------------------------------------------------------------------------
count_kernel_errors() {
    local logfile="${LOG_DIR}/dmesg-errors.log"

    if [[ ! -f "$logfile" ]]; then
        echo "  No kernel errors detected"
        return
    fi

    local count
    count="$(grep -cvE '^#|^$' "$logfile" 2>/dev/null || echo 0)"

    if (( count == 0 )); then
        echo "  No kernel errors detected"
    else
        echo "  ${count} kernel error/warning lines detected"
        echo "  Last 5 entries:"
        grep -vE '^#|^$' "$logfile" | tail -5 | sed 's/^/    /'
    fi
}

# ---------------------------------------------------------------------------
# Count connection drops
# ---------------------------------------------------------------------------
count_drops() {
    local logfile="${LOG_DIR}/connection-drops.log"

    if [[ ! -f "$logfile" ]]; then
        echo "  (no data)"
        return
    fi

    local total_line
    total_line="$(grep 'total_drops=' "$logfile" 2>/dev/null || true)"
    if [[ -n "$total_line" ]]; then
        local count="${total_line#*=}"
        if (( count == 0 )); then
            echo "  No connection drops detected"
        else
            echo "  ${count} connection drop(s) detected"
            grep -E 'CONNECTION (LOST|RESTORED)' "$logfile" | sed 's/^/    /'
        fi
    else
        # Monitor still running, count from log lines
        local count
        count="$(grep -c 'CONNECTION LOST' "$logfile" 2>/dev/null || echo 0)"
        if (( count == 0 )); then
            echo "  No connection drops detected (so far)"
        else
            echo "  ${count} connection drop(s) detected (so far)"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------
print_summary() {
    if (( SUMMARY_PRINTED )); then
        return
    fi
    SUMMARY_PRINTED=1

    local end_epoch
    end_epoch="$(date +%s)"
    local elapsed=$(( end_epoch - START_EPOCH ))
    local hours=$(( elapsed / 3600 ))
    local minutes=$(( (elapsed % 3600) / 60 ))
    local seconds=$(( elapsed % 60 ))

    local summary="${LOG_DIR}/summary.txt"

    {
        echo "=============================================="
        echo " MT7927 WiFi Stability Test - Summary"
        echo "=============================================="
        echo ""
        echo "Interface:  ${IFACE}"
        echo "Started:    $(date -d "@${START_EPOCH}" '+%Y-%m-%d %H:%M:%S')"
        echo "Ended:      $(ts)"
        echo "Duration:   ${hours}h ${minutes}m ${seconds}s"
        echo "Log dir:    ${LOG_DIR}"
        echo ""
        echo "--- Ping to gateway ($(echo "$GATEWAY" | head -1)) ---"
        parse_ping_stats "${LOG_DIR}/ping-gateway.log"
        echo ""
        echo "--- Ping to 1.1.1.1 ---"
        parse_ping_stats "${LOG_DIR}/ping-cloudflare.log"
        echo ""
        echo "--- Connection drops ---"
        count_drops
        echo ""
        echo "--- Signal strength ---"
        parse_signal_range
        echo ""
        echo "--- Kernel errors (mt76/mt7925/mt6639) ---"
        count_kernel_errors
        echo ""
        if [[ -n "$IPERF_SERVER" ]]; then
            echo "--- Throughput (iperf3 to ${IPERF_SERVER}) ---"
            if [[ -f "${LOG_DIR}/iperf3.log" ]]; then
                local tests
                tests="$(grep -c 'sender' "${LOG_DIR}/iperf3.log" 2>/dev/null || echo 0)"
                echo "  ${tests} throughput test(s) completed"
                echo "  See ${LOG_DIR}/iperf3.log for details"
            else
                echo "  (no data)"
            fi
            echo ""
        fi
        echo "--- Log files ---"
        for f in "${LOG_DIR}"/*.log; do
            if [[ -f "$f" ]]; then
                local lines
                lines="$(wc -l < "$f")"
                echo "  $(basename "$f"): ${lines} lines"
            fi
        done
        echo ""
        echo "=============================================="
    } | tee "$summary"
}

# ---------------------------------------------------------------------------
# Cleanup: kill background jobs, print summary
# ---------------------------------------------------------------------------
cleanup() {
    log "Stopping test..."

    # Kill all background pids
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done

    echo ""
    print_summary
    exit 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    # Parse arguments
    while getopts "d:i:s:h" opt; do
        case "$opt" in
            d) DURATION_SECONDS="$(parse_duration "$OPTARG")" ;;
            i) IFACE="$OPTARG" ;;
            s) IPERF_SERVER="$OPTARG" ;;
            h) usage ;;
            *) usage ;;
        esac
    done

    # Auto-detect interface if not specified
    if [[ -z "$IFACE" ]]; then
        IFACE="$(detect_interface)"
    fi

    # Verify interface exists and is up
    if [[ ! -d "/sys/class/net/${IFACE}" ]]; then
        echo "ERROR: interface ${IFACE} does not exist" >&2
        exit 1
    fi

    # Get default gateway
    GATEWAY="$(ip route show default dev "$IFACE" 2>/dev/null \
        | grep -oP 'via \K[0-9.]+' | head -1 || true)"
    if [[ -z "$GATEWAY" ]]; then
        # Fallback: any default gateway
        GATEWAY="$(ip route show default 2>/dev/null \
            | grep -oP 'via \K[0-9.]+' | head -1 || true)"
    fi
    if [[ -z "$GATEWAY" ]]; then
        echo "ERROR: no default gateway found. Is WiFi connected?" >&2
        exit 1
    fi

    # Create log directory
    LOG_DIR="/tmp/mt7927-stability-$(date '+%Y%m%d-%H%M')"
    mkdir -p "$LOG_DIR"

    START_EPOCH="$(date +%s)"

    # Set up signal handler
    trap cleanup INT TERM

    # Print startup info
    local hours=$(( DURATION_SECONDS / 3600 ))
    local minutes=$(( (DURATION_SECONDS % 3600) / 60 ))
    log "MT7927 WiFi Stability Test"
    log "Interface:   ${IFACE}"
    log "Gateway:     ${GATEWAY}"
    log "Duration:    ${hours}h ${minutes}m"
    log "Log dir:     ${LOG_DIR}"
    if [[ -n "$IPERF_SERVER" ]]; then
        log "iperf3:      ${IPERF_SERVER}"
    fi
    log "Press Ctrl+C to stop early and see summary"
    echo ""

    # Capture initial state
    {
        echo "=== Initial state at $(ts) ==="
        echo ""
        echo "--- iw dev ${IFACE} info ---"
        iw dev "$IFACE" info 2>&1 || true
        echo ""
        echo "--- iw dev ${IFACE} link ---"
        iw dev "$IFACE" link 2>&1 || true
        echo ""
        echo "--- iw dev ${IFACE} station dump ---"
        iw dev "$IFACE" station dump 2>&1 || true
        echo ""
        echo "--- ip addr show ${IFACE} ---"
        ip addr show "$IFACE" 2>&1 || true
        echo ""
        echo "--- Driver info ---"
        local mod_path="/sys/class/net/${IFACE}/device/driver"
        if [[ -L "$mod_path" ]]; then
            echo "Driver: $(basename "$(readlink "$mod_path")")"
        fi
        echo "Kernel: $(uname -r)"
        echo ""
    } > "${LOG_DIR}/initial-state.log"
    log "Initial state captured"

    # Start background monitors
    run_ping "$GATEWAY" "gateway" &
    PIDS+=($!)
    log "Started ping to gateway (${GATEWAY})"

    run_ping "1.1.1.1" "cloudflare" &
    PIDS+=($!)
    log "Started ping to 1.1.1.1"

    run_station_monitor &
    PIDS+=($!)
    log "Started station monitor (every ${STATION_INTERVAL}s)"

    run_link_monitor &
    PIDS+=($!)
    log "Started link monitor (every ${LINK_LOG_INTERVAL}s)"

    run_dmesg_monitor &
    PIDS+=($!)
    log "Started dmesg monitor (every ${DMESG_INTERVAL}s)"

    run_drop_monitor &
    PIDS+=($!)
    log "Started connection drop monitor"

    if [[ -n "$IPERF_SERVER" ]]; then
        run_iperf_monitor &
        PIDS+=($!)
        log "Started iperf3 monitor (every ${IPERF_INTERVAL}s to ${IPERF_SERVER})"
    fi

    echo ""
    log "All monitors running. Test will end at $(date -d "+${DURATION_SECONDS} seconds" '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Wait until duration expires, checking every 30 seconds
    while time_remaining; do
        sleep 30 || true

        # Periodic liveness message (every 30 min)
        local now
        now="$(date +%s)"
        local elapsed=$(( now - START_EPOCH ))
        if (( elapsed % 1800 < 30 )); then
            local remaining=$(( DURATION_SECONDS - elapsed ))
            local rem_h=$(( remaining / 3600 ))
            local rem_m=$(( (remaining % 3600) / 60 ))
            log "Still running - ${rem_h}h ${rem_m}m remaining"
        fi
    done

    log "Duration reached"
    cleanup
}

main "$@"
