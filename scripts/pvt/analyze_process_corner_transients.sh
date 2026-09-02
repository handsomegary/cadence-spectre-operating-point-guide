#!/usr/bin/env bash

# Extract transient metrics from completed deterministic process-corner results.
# This script reads existing raw text files only. It does not invoke OCEAN.

set -u
set -o pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/cadence_projects/ota_project}"
RESULT_ROOT="${RESULT_ROOT:-$HOME/simulation/ota_project_ocean}"
PVT_ROOT="${PVT_ROOT:-$RESULT_ROOT/pvt_process}"
ANALYZER="${TRANSIENT_ANALYZER:-$PROJECT_DIR/analyze_transient_generic.awk}"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
STATUS_FILE="$PVT_ROOT/transient_analysis_status_$RUN_ID.tsv"

read -r -a CORNERS <<< "${PVT_CORNERS:-ff ss fnsp snfp}"
CASES=(tran_small tran_large tran_slew_140m)

if [[ ! -s "$ANALYZER" ]]; then
    printf 'ERROR: Transient analyzer is missing or empty: %s\n' "$ANALYZER" >&2
    exit 1
fi

command -v awk >/dev/null 2>&1 || { printf 'ERROR: awk is unavailable.\n' >&2; exit 1; }

mkdir -p "$PVT_ROOT"
printf 'CORNER\tCASE\tSTATUS\tNUMERIC_ROWS\tOUTPUT\tLOG\n' > "$STATUS_FILE"
failed_count=0

for corner in "${CORNERS[@]}"; do
    printf '\n===== CORNER %s =====\n' "$corner"

    for transient_case in "${CASES[@]}"; do
        result_dir="$PVT_ROOT/$corner/$transient_case"
        raw_file="$result_dir/${transient_case}_raw.txt"
        output_file="$result_dir/${transient_case}_analysis.txt"
        log_file="$result_dir/${transient_case}_analysis.log"
        temporary_file="$result_dir/.${transient_case}_analysis.$RUN_ID.tmp"

        if [[ ! -s "$raw_file" ]]; then
            printf '[FAIL] %-5s %-16s missing raw file\n' "$corner" "$transient_case"
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$corner" "$transient_case" "FAILED_MISSING_RAW" 0 "$output_file" "$log_file" >> "$STATUS_FILE"
            failed_count=$((failed_count + 1))
            continue
        fi

        printf '[RUN ] %-5s %-16s\n' "$corner" "$transient_case"
        if awk -v "case_name=$transient_case" -f "$ANALYZER" "$raw_file" > "$temporary_file" 2> "$log_file" && \
           grep -Fq 'TRANSIENT_ANALYSIS_STATUS=VERIFIED' "$temporary_file" && \
           ! grep -Fq 'ERROR:' "$temporary_file"; then
            mv -f -- "$temporary_file" "$output_file"
            numeric_rows="$(awk -F= '$1=="NUMERIC_ROWS" {print $2; exit}' "$output_file")"
            printf '[PASS] %-5s %-16s rows=%s\n' "$corner" "$transient_case" "$numeric_rows"
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$corner" "$transient_case" "PASSED" "${numeric_rows:-0}" "$output_file" "$log_file" >> "$STATUS_FILE"
        else
            mv -f -- "$temporary_file" "$output_file" 2>/dev/null || true
            numeric_rows="$(awk -F= '$1=="NUMERIC_ROWS" {print $2; exit}' "$output_file" 2>/dev/null)"
            printf '[FAIL] %-5s %-16s output=%s log=%s\n' "$corner" "$transient_case" "$output_file" "$log_file"
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$corner" "$transient_case" "FAILED_ANALYSIS" "${numeric_rows:-0}" "$output_file" "$log_file" >> "$STATUS_FILE"
            failed_count=$((failed_count + 1))
        fi
    done
done

printf '\nSTATUS_FILE=%s\nEXPECTED_ANALYSIS_COUNT=%d\nFAILED_COUNT=%d\n' \
    "$STATUS_FILE" "$(( ${#CORNERS[@]} * ${#CASES[@]} ))" "$failed_count"

[[ "$failed_count" -eq 0 ]]
