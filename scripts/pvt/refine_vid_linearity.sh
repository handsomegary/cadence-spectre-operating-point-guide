#!/usr/bin/env bash

# Refine near-zero VID linearity for selected process corners.
# Existing coarse VID results are preserved.

set -u
set -o pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/cadence_projects/ota_project}"
RESULT_ROOT="${RESULT_ROOT:-$HOME/simulation/ota_project_ocean}"
PVT_ROOT="${PVT_ROOT:-$RESULT_ROOT/pvt_process}"
GENERATED_ROOT="${GENERATED_ROOT:-$PROJECT_DIR/generated_pvt}"
ANALYZER="${VID_ANALYZER:-$PROJECT_DIR/analyze_vid_linearity_v1.awk}"

VID_START="${VID_REFINED_START:--5m}"
VID_STOP="${VID_REFINED_STOP:-5m}"
VID_STEP="${VID_REFINED_STEP:-10u}"
CRASH_RETRIES="${PVT_CRASH_RETRIES:-3}"
STARTUP_DELAY_SECONDS="${PVT_STARTUP_DELAY_SECONDS:-3}"
CRASH_RETRY_DELAY_SECONDS="${PVT_CRASH_RETRY_DELAY_SECONDS:-10}"

read -r -a CORNERS <<< "${PVT_CORNERS:-ss fnsp}"

RUN_ID="$(date +%Y%m%d_%H%M%S)"
STATUS_FILE="$PVT_ROOT/vid_refined_status_$RUN_ID.tsv"
mkdir -p "$PVT_ROOT"
printf 'CORNER\tSTAGE\tSTATUS\tEXIT_STATUS\tRETRIES\tLOG\n' > "$STATUS_FILE"

for command_name in awk grep mkdir mktemp mv ocean rm sed sleep; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'ERROR: Required command is unavailable: %s\n' "$command_name" >&2
        exit 1
    fi
done

if [[ ! -s "$ANALYZER" ]]; then
    printf 'ERROR: VID analyzer is missing or empty: %s\n' "$ANALYZER" >&2
    exit 1
fi

record_status() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$STATUS_FILE"
}

log_has_hard_error() {
    grep -Eiq \
        '^\*Error\*|^Error[[:space:]:]|PARSER ERROR|syntax error|FATAL|Segmentation|cannot access file for reading|file not found|No such file or directory' \
        "$1"
}

run_ocean_process() {
    local script="$1"
    local base_log="$2"
    local attempt=1
    local maximum_attempts=$((CRASH_RETRIES + 1))
    local attempt_log

    OCEAN_LAST_STATUS=1
    OCEAN_LAST_LOG="$base_log"
    OCEAN_LAST_RETRIES=0

    while [[ "$attempt" -le "$maximum_attempts" ]]; do
        attempt_log="$base_log"
        [[ "$attempt" -gt 1 ]] && attempt_log="${base_log%.log}.retry_$((attempt - 1)).log"
        [[ "$STARTUP_DELAY_SECONDS" -gt 0 ]] && sleep "$STARTUP_DELAY_SECONDS"

        ocean -nograph -restore "$script" > "$attempt_log" 2>&1
        OCEAN_LAST_STATUS=$?
        OCEAN_LAST_LOG="$attempt_log"

        [[ "$OCEAN_LAST_STATUS" -ne 139 ]] && break
        [[ "$attempt" -ge "$maximum_attempts" ]] && break

        [[ "$CRASH_RETRY_DELAY_SECONDS" -gt 0 ]] && sleep "$CRASH_RETRY_DELAY_SECONDS"
        attempt=$((attempt + 1))
    done

    OCEAN_LAST_RETRIES=$((attempt - 1))
}

generate_refined_simulation() {
    local corner="$1"
    local source="$GENERATED_ROOT/$corner/vid_sweep_${corner}.ocn"
    local target="$GENERATED_ROOT/$corner/vid_sweep_refined_${corner}.ocn"
    local result_dir="$PVT_ROOT/$corner/dc_vid_refined"
    local temporary

    [[ -f "$source" ]] || { printf 'ERROR: Missing generated VID script: %s\n' "$source" >&2; return 1; }
    mkdir -p "$GENERATED_ROOT/$corner" "$result_dir"
    temporary="$(mktemp "$GENERATED_ROOT/$corner/.vid_sweep_refined_${corner}.XXXXXX")"

    sed \
        -e "s|$PVT_ROOT/$corner/dc_vid|$result_dir|g" \
        -e "s/?start \"-50m\"/?start \"$VID_START\"/" \
        -e "s/?stop \"50m\"/?stop \"$VID_STOP\"/" \
        -e "s/?step \"100u\"/?step \"$VID_STEP\"/" \
        "$source" > "$temporary"

    mv -f -- "$temporary" "$target"
    printf '%s\n' "$target"
}

write_export_script() {
    local corner="$1"
    local result_dir="$PVT_ROOT/$corner/dc_vid_refined"
    local target="$GENERATED_ROOT/$corner/vid_export_refined_${corner}.ocn"

    cat > "$target" <<EOF
openResults("$result_dir/psf")
selectResult('dc)
nm0Margin = abs(getData("NM0:vds")) - abs(getData("NM0:vdsat"))
nm1Margin = abs(getData("NM1:vds")) - abs(getData("NM1:vdsat"))
nm2Margin = abs(getData("NM2:vds")) - abs(getData("NM2:vdsat"))
pm0Margin = abs(getData("PM0:vds")) - abs(getData("PM0:vdsat"))
pm1Margin = abs(getData("PM1:vds")) - abs(getData("PM1:vdsat"))
ocnPrint(?output "$result_dir/vid_vout_scientific.txt" ?numberNotation 'scientific ?precision 12 v("/vout"))
ocnPrint(?output "$result_dir/vid_all_margins.txt" v("/vout") getData("NM0:region") nm0Margin getData("NM1:region") nm1Margin getData("NM2:region") nm2Margin getData("PM0:region") pm0Margin getData("PM1:region") pm1Margin)
printf("Refined VID exports completed.\\n")
exit()
EOF

    printf '%s\n' "$target"
}

process_corner() {
    local corner="$1"
    local result_dir="$PVT_ROOT/$corner/dc_vid_refined"
    local log_dir="$result_dir/logs"
    local simulation_script
    local export_script
    local analysis_file="$result_dir/vid_linearity_analysis.txt"
    local analysis_log="$log_dir/analysis.log"

    mkdir -p "$result_dir" "$log_dir"
    simulation_script="$(generate_refined_simulation "$corner")" || return 1

    printf '[RUN ] %-5s refined VID simulation\n' "$corner"
    run_ocean_process "$simulation_script" "$log_dir/simulation.log"
    if [[ "$OCEAN_LAST_STATUS" -ne 0 || ! -d "$result_dir/psf" ]] || log_has_hard_error "$OCEAN_LAST_LOG"; then
        record_status "$corner" "simulation" "FAILED" "$OCEAN_LAST_STATUS" "$OCEAN_LAST_RETRIES" "$OCEAN_LAST_LOG"
        return 1
    fi
    record_status "$corner" "simulation" "PASSED" 0 "$OCEAN_LAST_RETRIES" "$OCEAN_LAST_LOG"

    export_script="$(write_export_script "$corner")" || return 1
    printf '[RUN ] %-5s refined VID export\n' "$corner"
    run_ocean_process "$export_script" "$log_dir/export.log"
    if [[ "$OCEAN_LAST_STATUS" -ne 0 || ! -s "$result_dir/vid_vout_scientific.txt" || ! -s "$result_dir/vid_all_margins.txt" ]]; then
        record_status "$corner" "export" "FAILED" "$OCEAN_LAST_STATUS" "$OCEAN_LAST_RETRIES" "$OCEAN_LAST_LOG"
        return 1
    fi
    record_status "$corner" "export" "PASSED" 0 "$OCEAN_LAST_RETRIES" "$OCEAN_LAST_LOG"

    printf '[RUN ] %-5s refined VID analysis\n' "$corner"
    if awk -f "$ANALYZER" "$result_dir/vid_vout_scientific.txt" "$result_dir/vid_all_margins.txt" \
        > "$analysis_file" 2> "$analysis_log" && ! grep -Fq 'ERROR:' "$analysis_file"; then
        printf '[PASS] %-5s refined VID analysis\n' "$corner"
        record_status "$corner" "analysis" "PASSED" 0 0 "$analysis_file"
        return 0
    fi

    record_status "$corner" "analysis" "FAILED" 1 0 "$analysis_log"
    return 1
}

failed_count=0
printf 'VID_REFINED_START=%s\nVID_REFINED_STOP=%s\nVID_REFINED_STEP=%s\n' "$VID_START" "$VID_STOP" "$VID_STEP"
printf 'CORNERS=%s\nSTATUS_FILE=%s\n' "${CORNERS[*]}" "$STATUS_FILE"

for corner in "${CORNERS[@]}"; do
    printf '\n===== CORNER %s =====\n' "$corner"
    process_corner "$corner" || failed_count=$((failed_count + 1))
done

printf '\nSTATUS_FILE=%s\nFAILED_CORNER_COUNT=%d\n' "$STATUS_FILE" "$failed_count"
[[ "$failed_count" -eq 0 ]]
