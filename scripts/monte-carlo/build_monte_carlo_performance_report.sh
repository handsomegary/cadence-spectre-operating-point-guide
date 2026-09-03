#!/usr/bin/env bash

# Build a statistical report from a verified Monte Carlo performance run.
# This script is read-only with respect to simulation data.

set -u
set -o pipefail

SCRIPT_VERSION=1

RESULT_ROOT="${MC_PERFORMANCE_RESULT_ROOT:-$HOME/simulation/ota_project_ocean/monte_carlo_performance/all_n200_seed20260902}"
EXPECTED_COUNT="${MC_EXPECTED_COUNT:-200}"
VARIATIONS="${MC_VARIATIONS:-all}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANALYZER="${MC_PERFORMANCE_ANALYZER:-$SCRIPT_DIR/analyze_monte_carlo_performance_v1.awk}"

DATA_FILE="$RESULT_ROOT/psf/performance.mcdata"
PARAM_FILE="$RESULT_ROOT/psf/performance.mcparam"
SCHEMA_FILE="$RESULT_ROOT/input/performance_mcdata_schema.txt"
RUN_LOG="$RESULT_ROOT/logs/spectre.log"
RUN_SUMMARY="$RESULT_ROOT/summary/monte_carlo_performance_summary.txt"
REPORT_DIR="$RESULT_ROOT/report"
STAMP="$(date +%Y%m%d_%H%M%S)"

ANALYSIS_FILE="$REPORT_DIR/monte_carlo_performance_analysis_$STAMP.txt"
SAMPLE_FILE="$REPORT_DIR/monte_carlo_performance_samples_$STAMP.tsv"
REPORT_FILE="$REPORT_DIR/monte_carlo_performance_report_$STAMP.txt"
CHECKSUM_FILE="$REPORT_DIR/monte_carlo_performance_report_$STAMP.sha256"

for required_file in "$ANALYZER" "$DATA_FILE" "$PARAM_FILE" "$SCHEMA_FILE" "$RUN_LOG" "$RUN_SUMMARY"; do
    if [[ ! -s "$required_file" ]]; then
        printf 'ERROR: REQUIRED_FILE_MISSING=%s\n' "$required_file" >&2
        exit 1
    fi
done

if ! grep -q '^MONTE_CARLO_PERFORMANCE_STATUS=PASSED$' "$RUN_SUMMARY"; then
    printf 'ERROR: SOURCE_MONTE_CARLO_RUN_NOT_VERIFIED\n' >&2
    exit 1
fi

if [[ ! "$EXPECTED_COUNT" =~ ^[1-9][0-9]*$ ]]; then
    printf 'ERROR: INVALID_EXPECTED_COUNT=%s\n' "$EXPECTED_COUNT" >&2
    exit 2
fi

mkdir -p "$REPORT_DIR"

if ! awk -f "$ANALYZER" "$DATA_FILE" > "$ANALYSIS_FILE"; then
    printf 'ERROR: PERFORMANCE_ANALYSIS_FAILED\n' >&2
    exit 1
fi

valid_rows="$(awk -F= '/^VALID_ROWS=/{print $2; exit}' "$ANALYSIS_FILE")"
invalid_rows="$(awk -F= '/^INVALID_NUMERIC_ROWS=/{print $2; exit}' "$ANALYSIS_FILE")"
non_six_rows="$(awk -F= '/^NON_SIX_COLUMN_ROWS=/{print $2; exit}' "$ANALYSIS_FILE")"
nonpositive_ugf="$(awk -F= '/^NONPOSITIVE_UGF_ROWS=/{print $2; exit}' "$ANALYSIS_FILE")"

if [[ "$valid_rows" -ne "$EXPECTED_COUNT" || "$invalid_rows" -ne 0 || "$non_six_rows" -ne 0 || "$nonpositive_ugf" -ne 0 ]]; then
    printf 'ERROR: PERFORMANCE_REPORT_VALIDATION_FAILED VALID=%s INVALID=%s NON_SIX=%s NONPOSITIVE_UGF=%s EXPECTED=%s\n' \
        "$valid_rows" "$invalid_rows" "$non_six_rows" "$nonpositive_ugf" "$EXPECTED_COUNT" >&2
    exit 1
fi

awk '
BEGIN {
    FS = " "
    OFS = "\t"
    print "RUN","VOUT_DC_V","VDD_CURRENT_A","VDD_POWER_W","LOOP_GAIN_DB_1HZ","UGF_HZ","PHASE_MARGIN_DEG"
}
NF == 6 && $1 ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/ && \
         $2 ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/ && \
         $3 ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/ && \
         $4 ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/ && \
         $5 ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/ && \
         $6 ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/ {
    run++
    printf "%d\t%.12e\t%.12e\t%.12e\t%.12e\t%.12e\t%.12e\n", run,$1,$2,$3,$4,$5,$6
}
' "$DATA_FILE" > "$SAMPLE_FILE"

{
    printf 'OTA_MONTE_CARLO_PERFORMANCE_REPORT_BEGIN\n'
    printf 'REPORT_SCRIPT_VERSION=%s\n' "$SCRIPT_VERSION"
    printf 'SOURCE_RESULT_ROOT=%s\n' "$RESULT_ROOT"
    printf 'SOURCE_DATA_FILE=%s\n' "$DATA_FILE"
    printf 'SOURCE_PARAM_FILE=%s\n' "$PARAM_FILE"
    printf 'SOURCE_SCHEMA_FILE=%s\n' "$SCHEMA_FILE"
    printf 'SOURCE_LOG=%s\n' "$RUN_LOG"
    printf 'GENERATED_AT=%s\n' "$(date -Is)"
    printf 'VARIATIONS=%s\n' "$VARIATIONS"
    printf 'EXPECTED_COUNT=%s\n' "$EXPECTED_COUNT"
    printf '\n===== SOURCE RUN SUMMARY =====\n'
    cat "$RUN_SUMMARY"
    printf '\n===== STATISTICAL ANALYSIS =====\n'
    cat "$ANALYSIS_FILE"
    printf '\n===== OUTPUT FILES =====\n'
    printf 'SAMPLE_FILE=%s\n' "$SAMPLE_FILE"
    printf 'ANALYSIS_FILE=%s\n' "$ANALYSIS_FILE"
    printf 'OTA_MONTE_CARLO_PERFORMANCE_REPORT_END\n'
} > "$REPORT_FILE"

sha256sum \
    "$ANALYZER" \
    "$DATA_FILE" \
    "$PARAM_FILE" \
    "$SCHEMA_FILE" \
    "$RUN_LOG" \
    "$RUN_SUMMARY" \
    "$ANALYSIS_FILE" \
    "$SAMPLE_FILE" \
    "$REPORT_FILE" > "$CHECKSUM_FILE"

ln -sfn "$(basename "$ANALYSIS_FILE")" "$REPORT_DIR/monte_carlo_performance_analysis_latest.txt"
ln -sfn "$(basename "$SAMPLE_FILE")" "$REPORT_DIR/monte_carlo_performance_samples_latest.tsv"
ln -sfn "$(basename "$REPORT_FILE")" "$REPORT_DIR/monte_carlo_performance_report_latest.txt"
ln -sfn "$(basename "$CHECKSUM_FILE")" "$REPORT_DIR/monte_carlo_performance_report_latest.sha256"

printf 'MONTE_CARLO_PERFORMANCE_REPORT_CREATED\n'
printf 'REPORT_FILE=%s\n' "$REPORT_FILE"
printf 'ANALYSIS_FILE=%s\n' "$ANALYSIS_FILE"
printf 'SAMPLE_FILE=%s\n' "$SAMPLE_FILE"
printf 'CHECKSUM_FILE=%s\n' "$CHECKSUM_FILE"
printf 'SAMPLE_COUNT=%s\n' "$valid_rows"
