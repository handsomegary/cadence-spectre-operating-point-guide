#!/usr/bin/env bash

# Deterministic process-corner runner template for Cadence OCEAN flows.
#
# Modes:
#   prepare  Generate and inspect corner-specific OCEAN scripts.
#   core     Run DC operating point, open-loop AC, and unity-feedback STB.
#   full     Run the configured primary test list.
#
# Configure paths with environment variables before use:
#   PROJECT_DIR=$HOME/cadence_projects/ota_project
#   RESULT_ROOT=$HOME/simulation/ota_project_ocean
#   PVT_CORNERS="ff ss fnsp snfp"

set -u
set -o pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/cadence_projects/ota_project}"
RESULT_ROOT="${RESULT_ROOT:-$HOME/simulation/ota_project_ocean}"
PVT_ROOT="${PVT_ROOT:-$RESULT_ROOT/pvt_process}"
GENERATED_ROOT="${GENERATED_ROOT:-$PROJECT_DIR/generated_pvt}"

MODE="${1:-full}"
FORCE_RUN="${PVT_FORCE:-0}"
ADOPT_EXISTING="${PVT_ADOPT_EXISTING:-1}"
CRASH_RETRIES="${PVT_CRASH_RETRIES:-3}"
STARTUP_DELAY_SECONDS="${PVT_STARTUP_DELAY_SECONDS:-3}"
CRASH_RETRY_DELAY_SECONDS="${PVT_CRASH_RETRY_DELAY_SECONDS:-10}"
NOMINAL_MODEL_SECTION="${NOMINAL_MODEL_SECTION:-tt}"
PVT_MODEL_REWRITE_SCRIPT="${PVT_MODEL_REWRITE_SCRIPT:-}"

read -r -a CORNERS <<< "${PVT_CORNERS:-ff ss fnsp snfp}"

CORE_TESTS=(
    "dcop|dcop.ocn"
    "ac_openloop|ac_sweep.ocn"
    "stb_unity|stb_sweep.ocn"
)

FULL_TESTS=(
    "dcop|dcop.ocn"
    "dc_vcm|vcm_sweep.ocn"
    "dc_vid|vid_sweep.ocn"
    "ac_openloop|ac_sweep.ocn"
    "stb_unity|stb_sweep.ocn"
    "tran_small|tran_small.ocn"
    "tran_large|tran_large.ocn"
    "tran_slew_140m|tran_slew_140m.ocn"
    "noise_openloop|noise_openloop.ocn"
    "ac_commonmode|cmrr_sweep.ocn"
    "ac_psrr_plus|psrr_plus_sweep.ocn"
    "ac_psrr_minus|psrr_minus_sweep.ocn"
)

usage() {
    printf '%s\n' \
        "Usage: bash run_process_corners.sh [prepare|core|full]" \
        "" \
        "Environment variables:" \
        "  PROJECT_DIR=\$HOME/cadence_projects/ota_project" \
        "  RESULT_ROOT=\$HOME/simulation/ota_project_ocean" \
        "  PVT_CORNERS=\"ff ss fnsp snfp\"" \
        "  PVT_FORCE=0|1" \
        "  PVT_ADOPT_EXISTING=0|1" \
        "  PVT_CRASH_RETRIES=3" \
        "  PVT_MODEL_REWRITE_SCRIPT=/path/to/custom_model_rewrite.sh"
}

case "$MODE" in
    prepare|core|full) ;;
    *) usage; exit 2 ;;
esac

for command_name in awk date grep mkdir mktemp mv rm sed sleep; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'ERROR: Required command is unavailable: %s\n' "$command_name" >&2
        exit 1
    fi
done

if [[ "$MODE" != "prepare" ]] && ! command -v ocean >/dev/null 2>&1; then
    printf 'ERROR: ocean is unavailable in PATH.\n' >&2
    exit 1
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
    printf 'ERROR: Project directory not found: %s\n' "$PROJECT_DIR" >&2
    exit 1
fi

mkdir -p "$PVT_ROOT" "$GENERATED_ROOT"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
STATUS_FILE="$PVT_ROOT/process_corner_status_$RUN_ID.tsv"
printf 'CORNER\tTEST\tSTATUS\tEXIT_STATUS\tELAPSED_SECONDS\tWARNINGS\tLOG\n' > "$STATUS_FILE"

if [[ "$MODE" == "core" ]]; then
    SELECTED_TESTS=("${CORE_TESTS[@]}")
else
    SELECTED_TESTS=("${FULL_TESTS[@]}")
fi

extract_result_dir() {
    awk -F'"' '/^[[:space:]]*resultsDir[[:space:]]*\(/ {print $2; exit}' "$1"
}

extract_output_paths() {
    awk -F'"' '
        /\?output[[:space:]]/ {
            for (field = 2; field <= NF; field += 2) {
                if ($field ~ /^\//)
                    print $field
            }
        }
    ' "$1"
}

rewrite_model_sections() {
    local corner="$1"
    local script="$2"

    if [[ -n "$PVT_MODEL_REWRITE_SCRIPT" ]]; then
        bash "$PVT_MODEL_REWRITE_SCRIPT" "$corner" "$script"
    else
        sed -i "s/\"$NOMINAL_MODEL_SECTION\"/\"$corner\"/g" "$script"
    fi
}

generate_ocn() {
    local corner="$1"
    local base="$2"
    local source="$PROJECT_DIR/$base"
    local generated_dir="$GENERATED_ROOT/$corner"
    local target="$generated_dir/${base%.ocn}_${corner}.ocn"
    local corner_root="$PVT_ROOT/$corner"
    local temporary

    if [[ ! -f "$source" ]]; then
        printf 'ERROR: Required base script is missing: %s\n' "$source" >&2
        return 1
    fi

    mkdir -p "$generated_dir" "$corner_root"
    temporary="$(mktemp "$generated_dir/.${base%.ocn}_${corner}.XXXXXX")"

    sed "s|$RESULT_ROOT/|$corner_root/|g" "$source" > "$temporary"
    rewrite_model_sections "$corner" "$temporary"
    mv -f -- "$temporary" "$target"
    printf '%s\n' "$target"
}

validate_generated_ocn() {
    local corner="$1"
    local script="$2"
    local corner_root="$PVT_ROOT/$corner"
    local result_dir
    local output

    result_dir="$(extract_result_dir "$script")"
    case "$result_dir" in
        "$corner_root"/*) ;;
        *) printf 'ERROR: resultsDir outside corner root: %s\n' "$result_dir" >&2; return 1 ;;
    esac

    while IFS= read -r output; do
        [[ -z "$output" ]] && continue
        case "$output" in
            "$corner_root"/*) ;;
            *) printf 'ERROR: output outside corner root: %s\n' "$output" >&2; return 1 ;;
        esac
    done < <(extract_output_paths "$script")
}

validate_artifacts() {
    local script="$1"
    local result_dir
    local output

    result_dir="$(extract_result_dir "$script")"
    [[ -n "$result_dir" && -d "$result_dir/psf" ]] || return 1

    while IFS= read -r output; do
        [[ -z "$output" ]] && continue
        [[ -s "$output" ]] || return 1
    done < <(extract_output_paths "$script")
}

log_has_hard_error() {
    grep -Eiq \
        '^\*Error\*|^Error[[:space:]:]|PARSER ERROR|syntax error|FATAL|Segmentation|cannot access file for reading|file not found|No such file or directory' \
        "$1"
}

warning_count() {
    grep -Eic 'WARNING|\*WARNING\*' "$1" 2>/dev/null || true
}

record_status() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$STATUS_FILE"
}

run_ocean_process() {
    local script="$1"
    local base_log="$2"
    local attempt=1
    local maximum_attempts=$((CRASH_RETRIES + 1))
    local attempt_log
    local total_start=$SECONDS

    OCEAN_LAST_STATUS=1
    OCEAN_LAST_LOG="$base_log"
    OCEAN_LAST_RETRIES=0
    OCEAN_LAST_ELAPSED=0

    while [[ "$attempt" -le "$maximum_attempts" ]]; do
        attempt_log="$base_log"
        [[ "$attempt" -gt 1 ]] && attempt_log="${base_log%.log}.retry_$((attempt - 1)).log"
        [[ "$STARTUP_DELAY_SECONDS" -gt 0 ]] && sleep "$STARTUP_DELAY_SECONDS"

        ocean -nograph -restore "$script" > "$attempt_log" 2>&1
        OCEAN_LAST_STATUS=$?
        OCEAN_LAST_LOG="$attempt_log"
        OCEAN_LAST_ELAPSED=$((SECONDS - total_start))

        [[ "$OCEAN_LAST_STATUS" -ne 139 ]] && break
        [[ "$attempt" -ge "$maximum_attempts" ]] && break

        OCEAN_LAST_RETRIES=$attempt
        [[ "$CRASH_RETRY_DELAY_SECONDS" -gt 0 ]] && sleep "$CRASH_RETRY_DELAY_SECONDS"
        attempt=$((attempt + 1))
    done

    OCEAN_LAST_RETRIES=$((attempt - 1))
}

run_test() {
    local corner="$1"
    local test_name="$2"
    local script="$3"
    local corner_root="$PVT_ROOT/$corner"
    local result_dir
    local log_dir="$corner_root/logs"
    local log="$log_dir/${test_name}.log"
    local marker
    local warnings

    result_dir="$(extract_result_dir "$script")"
    mkdir -p "$result_dir" "$log_dir"
    marker="$result_dir/.pvt_complete_${test_name}"

    if [[ "$FORCE_RUN" != "1" && -f "$marker" ]] && validate_artifacts "$script"; then
        printf '[SKIP] %-5s %-18s verified marker\n' "$corner" "$test_name"
        record_status "$corner" "$test_name" "SKIPPED_VERIFIED" 0 0 0 "$log"
        return 0
    fi

    if [[ "$FORCE_RUN" != "1" && "$ADOPT_EXISTING" == "1" ]] && validate_artifacts "$script"; then
        : > "$marker"
        printf '[SKIP] %-5s %-18s adopted existing result\n' "$corner" "$test_name"
        record_status "$corner" "$test_name" "ADOPTED_EXISTING" 0 0 0 "$log"
        return 0
    fi

    printf '[RUN ] %-5s %-18s\n' "$corner" "$test_name"
    run_ocean_process "$script" "$log"
    warnings="$(warning_count "$OCEAN_LAST_LOG")"

    if [[ "$OCEAN_LAST_STATUS" -ne 0 ]] || log_has_hard_error "$OCEAN_LAST_LOG" || ! validate_artifacts "$script"; then
        printf '[FAIL] %-5s %-18s log=%s\n' "$corner" "$test_name" "$OCEAN_LAST_LOG"
        record_status "$corner" "$test_name" "FAILED" "$OCEAN_LAST_STATUS" "$OCEAN_LAST_ELAPSED" "$warnings" "$OCEAN_LAST_LOG"
        return 1
    fi

    : > "$marker"
    printf '[PASS] %-5s %-18s elapsed=%ss warnings=%s retries=%s\n' \
        "$corner" "$test_name" "$OCEAN_LAST_ELAPSED" "$warnings" "$OCEAN_LAST_RETRIES"
    record_status "$corner" "$test_name" "PASSED" "$OCEAN_LAST_STATUS" "$OCEAN_LAST_ELAPSED" "$warnings" "$OCEAN_LAST_LOG"
}

main() {
    local failed_count=0
    local corner
    local spec
    local test_name
    local base
    local generated

    printf 'MODE=%s\nCORNERS=%s\nPVT_ROOT=%s\nSTATUS_FILE=%s\n' \
        "$MODE" "${CORNERS[*]}" "$PVT_ROOT" "$STATUS_FILE"

    for corner in "${CORNERS[@]}"; do
        printf '\n===== CORNER %s =====\n' "$corner"
        for spec in "${SELECTED_TESTS[@]}"; do
            test_name="${spec%%|*}"
            base="${spec#*|}"
            generated="$(generate_ocn "$corner" "$base")" || { failed_count=$((failed_count + 1)); continue; }

            if ! validate_generated_ocn "$corner" "$generated"; then
                record_status "$corner" "$test_name" "FAILED_GENERATED_VALIDATION" 1 0 0 "$generated"
                failed_count=$((failed_count + 1))
                continue
            fi

            if [[ "$MODE" == "prepare" ]]; then
                printf '[PASS] %-5s %-18s prepared\n' "$corner" "$test_name"
                record_status "$corner" "$test_name" "PREPARED" 0 0 0 "$generated"
            else
                run_test "$corner" "$test_name" "$generated" || failed_count=$((failed_count + 1))
            fi
        done
    done

    printf '\nSTATUS_FILE=%s\nFAILED_COUNT=%d\n' "$STATUS_FILE" "$failed_count"
    [[ "$failed_count" -eq 0 ]]
}

main "$@"
