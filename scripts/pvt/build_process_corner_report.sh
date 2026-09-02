#!/usr/bin/env bash

# Build consolidated reports from completed deterministic process-corner results.
# This script is read-only with respect to simulation data and never invokes OCEAN.

set -u
set -o pipefail

RESULT_ROOT="${RESULT_ROOT:-$HOME/simulation/ota_project_ocean}"
PVT_ROOT="${PVT_ROOT:-$RESULT_ROOT/pvt_process}"
REPORT_ROOT="${PVT_REPORT_ROOT:-$PVT_ROOT/reports}"
RUN_ID="$(date +%Y%m%d_%H%M%S)"

read -r -a CORNERS <<< "${PVT_CORNERS:-ff ss fnsp snfp}"

PRIMARY_TESTS=(
    dcop
    dc_vcm
    dc_vid
    ac_openloop
    stb_unity
    tran_small
    tran_large
    tran_slew_140m
    noise_openloop
    ac_commonmode
    ac_psrr_plus
    ac_psrr_minus
)

ANALYSIS_SPECS=(
    "DCOP|dcop/dcop_existing_summary.txt"
    "AC_OPENLOOP|ac_openloop/ac_corner_analysis.txt"
    "STB_UNITY|stb_unity/stb_margin_summary.txt"
    "DC_VCM|dc_vcm/vcm_range_analysis.txt"
    "DC_VID|dc_vid/vid_linearity_analysis.txt"
    "NOISE|noise_openloop/noise_analysis_final.txt"
    "CMRR|ac_commonmode/cmrr_analysis.txt"
    "PSRR_PLUS|ac_psrr_plus/psrr_plus_analysis.txt"
    "PSRR_MINUS|ac_psrr_minus/psrr_minus_analysis.txt"
    "TRAN_SMALL|tran_small/tran_small_analysis.txt"
    "TRAN_LARGE|tran_large/tran_large_analysis.txt"
    "TRAN_SLEW_140M|tran_slew_140m/tran_slew_140m_analysis.txt"
)

if [[ ! -d "$PVT_ROOT" ]]; then
    printf 'ERROR: PVT result root is missing: %s\n' "$PVT_ROOT" >&2
    exit 1
fi

mkdir -p "$REPORT_ROOT"

REPORT_FILE="$REPORT_ROOT/process_corner_report_$RUN_ID.txt"
LONG_FILE="$REPORT_ROOT/process_corner_metrics_long_$RUN_ID.tsv"
COMPARISON_FILE="$REPORT_ROOT/process_corner_comparison_$RUN_ID.tsv"
CHECKSUM_FILE="$REPORT_ROOT/process_corner_report_$RUN_ID.sha256"

printf 'CORNER\tCATEGORY\tMETRIC\tVALUE\n' > "$LONG_FILE"
verified_count=0
missing_primary_count=0
missing_analysis_count=0

{
    printf 'DETERMINISTIC PROCESS-CORNER REPORT\n'
    printf 'GENERATED_AT=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'PVT_ROOT=%s\n' "$PVT_ROOT"
    printf 'CORNERS=%s\n' "${CORNERS[*]}"
    printf 'PRIMARY_TEST_COUNT_PER_CORNER=%d\n' "${#PRIMARY_TESTS[@]}"
    printf 'EXPECTED_PRIMARY_RESULT_COUNT=%d\n' "$(( ${#CORNERS[@]} * ${#PRIMARY_TESTS[@]} ))"

    printf '\n===== PRIMARY RESULT VERIFICATION =====\n'
    printf '%-8s %-20s %-12s %-12s %-12s\n' "CORNER" "TEST" "MARKER" "PSF" "STATUS"

    for corner in "${CORNERS[@]}"; do
        for test_name in "${PRIMARY_TESTS[@]}"; do
            result_dir="$PVT_ROOT/$corner/$test_name"
            marker="$result_dir/.pvt_complete_${test_name}"
            marker_status="MISSING"
            psf_status="MISSING"
            result_status="MISSING"

            [[ -f "$marker" ]] && marker_status="PRESENT"
            [[ -d "$result_dir/psf" ]] && psf_status="PRESENT"

            if [[ "$marker_status" == "PRESENT" && "$psf_status" == "PRESENT" ]]; then
                result_status="VERIFIED"
                verified_count=$((verified_count + 1))
            else
                missing_primary_count=$((missing_primary_count + 1))
            fi

            printf '%-8s %-20s %-12s %-12s %-12s\n' "$corner" "$test_name" "$marker_status" "$psf_status" "$result_status"
        done
    done

    printf '\nPRIMARY_RESULT_VERIFIED_COUNT=%d\n' "$verified_count"
    printf 'PRIMARY_RESULT_MISSING_COUNT=%d\n' "$missing_primary_count"
    printf '\n===== ANALYSIS RESULTS =====\n'

    for corner in "${CORNERS[@]}"; do
        printf '\n######## CORNER %s ########\n' "$corner"

        for spec in "${ANALYSIS_SPECS[@]}"; do
            category="${spec%%|*}"
            relative_path="${spec#*|}"
            source_file="$PVT_ROOT/$corner/$relative_path"

            if [[ "$category" == "DC_VID" && -s "$PVT_ROOT/$corner/dc_vid_refined/vid_linearity_analysis.txt" ]]; then
                source_file="$PVT_ROOT/$corner/dc_vid_refined/vid_linearity_analysis.txt"
            fi

            printf '\n[%s]\nSOURCE=%s\n' "$category" "$source_file"
            if [[ ! -s "$source_file" ]]; then
                printf 'STATUS=MISSING_OR_EMPTY\n'
                missing_analysis_count=$((missing_analysis_count + 1))
                continue
            fi

            printf 'STATUS=AVAILABLE\n'
            sed -n '1,240p' "$source_file"

            awk -v corner="$corner" -v category="$category" '
                function trim(text) {
                    sub(/^[[:space:]]+/,"",text)
                    sub(/[[:space:]]+$/,"",text)
                    return text
                }
                index($0,"=") > 0 {
                    separator=index($0,"=")
                    key=trim(substr($0,1,separator-1))
                    value=trim(substr($0,separator+1))
                    if (key == "" || value == "")
                        next
                    gsub(/[[:space:]]+/," ",value)
                    printf "%s\t%s\t%s\t%s\n",corner,category,key,value
                }
            ' "$source_file" >> "$LONG_FILE"
        done
    done

    printf '\nANALYSIS_FILE_MISSING_COUNT=%d\n' "$missing_analysis_count"
} > "$REPORT_FILE"

awk -F'\t' '
    NR == 1 { next }
    {
        metric=$2 "." $3
        if (!(metric in seen)) {
            seen[metric]=1
            order[++metric_count]=metric
        }
        value[metric SUBSEP $1]=$4
    }
    END {
        print "METRIC\tff\tss\tfnsp\tsnfp"
        for (metric_number=1; metric_number<=metric_count; metric_number++) {
            metric=order[metric_number]
            printf "%s\t%s\t%s\t%s\t%s\n",metric,value[metric SUBSEP "ff"],value[metric SUBSEP "ss"],value[metric SUBSEP "fnsp"],value[metric SUBSEP "snfp"]
        }
    }
' "$LONG_FILE" > "$COMPARISON_FILE"

sha256sum "$REPORT_FILE" "$LONG_FILE" "$COMPARISON_FILE" > "$CHECKSUM_FILE"

cp -p -- "$REPORT_FILE" "$REPORT_ROOT/process_corner_report_latest.txt"
cp -p -- "$LONG_FILE" "$REPORT_ROOT/process_corner_metrics_long_latest.tsv"
cp -p -- "$COMPARISON_FILE" "$REPORT_ROOT/process_corner_comparison_latest.tsv"
cp -p -- "$CHECKSUM_FILE" "$REPORT_ROOT/process_corner_report_latest.sha256"

printf 'PROCESS_CORNER_REPORT_CREATED\n'
printf 'REPORT_FILE=%s\nLONG_FILE=%s\nCOMPARISON_FILE=%s\nCHECKSUM_FILE=%s\n' \
    "$REPORT_FILE" "$LONG_FILE" "$COMPARISON_FILE" "$CHECKSUM_FILE"
printf 'PRIMARY_RESULT_VERIFIED_COUNT=%d\nPRIMARY_RESULT_MISSING_COUNT=%d\nANALYSIS_FILE_MISSING_COUNT=%d\n' \
    "$verified_count" "$missing_primary_count" "$missing_analysis_count"

[[ "$missing_primary_count" -eq 0 && "$missing_analysis_count" -eq 0 ]]
