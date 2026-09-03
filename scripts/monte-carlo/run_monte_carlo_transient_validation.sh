#!/usr/bin/env bash

# Correlated transient Monte Carlo runner template.
#
# It creates a generated DUT netlist, runs fixed-time transient samples, and
# compares process/mismatch random streams with a reference performance run.

set -u
set -o pipefail

SCRIPT_VERSION=1

BASE_NETLIST="${MC_STB_BASE_NETLIST:-$HOME/simulation/ota_project_stb/spectre/schematic/netlist/netlist}"
MODEL_FILE="${MC_MODEL_FILE:-$HOME/pdk/models/spectre/model.lib}"
RESULT_ROOT_BASE="${MC_TRANSIENT_RESULT_ROOT:-$HOME/simulation/ota_project_ocean/monte_carlo_transient_validation}"
REFERENCE_RESULT_ROOT="${MC_REFERENCE_PERFORMANCE_ROOT:-$HOME/simulation/ota_project_ocean/monte_carlo_performance/all_n200_seed20260902}"
MODEL_SECTION="${MC_MODEL_SECTION:-mc}"
NOMINAL_NMOS_MODEL="${MC_NOMINAL_NMOS_MODEL:-nmos_nominal}"
NOMINAL_PMOS_MODEL="${MC_NOMINAL_PMOS_MODEL:-pmos_nominal}"
NMOS_MISMATCH_WRAPPER="${MC_NMOS_MISMATCH_WRAPPER:-nmos_mismatch_wrapper}"
PMOS_MISMATCH_WRAPPER="${MC_PMOS_MISMATCH_WRAPPER:-pmos_mismatch_wrapper}"

NUMRUNS="${MC_NUMRUNS:-200}"
SEED="${MC_SEED:-20260902}"
VARIATIONS="${MC_VARIATIONS:-all}"
VCM="${MC_VCM:-0.8}"
VDD="${MC_VDD:-1.2}"
STEP="${MC_STEP:-10m}"
TEMPERATURE="${MC_TEMPERATURE:-27}"
TRAN_STOP="${MC_TRAN_STOP:-30n}"
TRAN_MAXSTEP="${MC_TRAN_MAXSTEP:-20p}"
STEP_DELAY="${MC_STEP_DELAY:-1n}"
STEP_RISE="${MC_STEP_RISE:-10p}"
STEP_FALL="${MC_STEP_FALL:-10p}"
STEP_WIDTH="${MC_STEP_WIDTH:-10n}"
STEP_PERIOD="${MC_STEP_PERIOD:-1u}"
FORCE="${MC_FORCE:-0}"
MODE="${1:-full}"

case "$MODE" in
    prepare|full) ;;
    *) printf 'ERROR: INVALID_MODE=%s\nVALID_MODES=prepare full\n' "$MODE" >&2; exit 2 ;;
esac

case "$VARIATIONS" in
    all) ;;
    *) printf 'ERROR: INVALID_VARIATIONS=%s\nVALID_VARIATIONS=all\n' "$VARIATIONS" >&2; exit 2 ;;
esac

if [[ ! "$NUMRUNS" =~ ^[1-9][0-9]*$ ]]; then
    printf 'ERROR: INVALID_NUMRUNS=%s\n' "$NUMRUNS" >&2
    exit 2
fi

if [[ ! "$SEED" =~ ^[1-9][0-9]*$ ]]; then
    printf 'ERROR: INVALID_SEED=%s\n' "$SEED" >&2
    exit 2
fi

if [[ "$FORCE" != "0" && "$FORCE" != "1" ]]; then
    printf 'ERROR: INVALID_FORCE=%s\n' "$FORCE" >&2
    exit 2
fi

for required_file in "$BASE_NETLIST" "$MODEL_FILE"; do
    if [[ ! -s "$required_file" ]]; then
        printf 'ERROR: REQUIRED_FILE_MISSING=%s\n' "$required_file" >&2
        exit 1
    fi
done

if ! command -v spectre >/dev/null 2>&1; then
    printf 'ERROR: SPECTRE_NOT_FOUND\n' >&2
    exit 1
fi

RUN_ID="${VARIATIONS}_n${NUMRUNS}_seed${SEED}"
RESULT_ROOT="$RESULT_ROOT_BASE/$RUN_ID"
INPUT_DIR="$RESULT_ROOT/input"
RAW_DIR="$RESULT_ROOT/psf"
LOG_DIR="$RESULT_ROOT/logs"
SUMMARY_DIR="$RESULT_ROOT/summary"

DUT_NETLIST="$INPUT_DIR/ota_transient_mc.netlist"
DRIVER_NETLIST="$INPUT_DIR/monte_carlo_transient_validation.scs"
SCHEMA_FILE="$INPUT_DIR/transient_mcdata_schema.txt"
RUN_LOG="$LOG_DIR/spectre.log"
PREPARE_FILE="$SUMMARY_DIR/monte_carlo_transient_prepare.txt"
SUMMARY_FILE="$SUMMARY_DIR/monte_carlo_transient_summary.txt"
STATUS_FILE="$SUMMARY_DIR/monte_carlo_transient_status.tsv"
CHECKSUM_FILE="$SUMMARY_DIR/monte_carlo_transient_inputs.sha256"
STREAM_CHECK_FILE="$SUMMARY_DIR/transient_random_stream_check.txt"
COMPLETE_MARKER="$RESULT_ROOT/.complete"

TRANSIENT_SCALAR_FILE="$RAW_DIR/transient.mcdata"
TRANSIENT_PARAM_FILE="$RAW_DIR/transient.mcparam"
PROCESS_SCALAR_FILE="$RAW_DIR/process.mcdata"
PROCESS_PARAM_FILE="$RAW_DIR/process.mcparam"
MISMATCH_SCALAR_FILE="$RAW_DIR/mismatch.mcdata"
MISMATCH_PARAM_FILE="$RAW_DIR/mismatch.mcparam"

mkdir -p "$INPUT_DIR" "$RAW_DIR" "$LOG_DIR" "$SUMMARY_DIR"

validate_source_topology() {
    local mos_count probe_count feedback_count capacitor_count vdd_count input_count bias_count

    mos_count="$(grep -Ec '^(PM0|PM1|NM0|NM1|NM2)[[:space:]]' "$BASE_NETLIST" || true)"
    probe_count="$(grep -Ec '^IPRB0[[:space:]]+\(net012[[:space:]]+vout\)[[:space:]]+iprobe([[:space:]]|$)' "$BASE_NETLIST" || true)"
    feedback_count="$(grep -Ec '^NM1[[:space:]]+\(vout[[:space:]]+net012[[:space:]]+net2[[:space:]]+0\)' "$BASE_NETLIST" || true)"
    capacitor_count="$(grep -Ec '^C0[[:space:]]+\(vout[[:space:]]+0\)[[:space:]]+capacitor[[:space:]]+c=100f([[:space:]]|$)' "$BASE_NETLIST" || true)"
    vdd_count="$(grep -Ec '^V2[[:space:]]+\(net1[[:space:]]+0\)[[:space:]]+vsource[[:space:]]+dc=1\.2([[:space:]]|$)' "$BASE_NETLIST" || true)"
    input_count="$(grep -Ec '^V0[[:space:]]+\(net013[[:space:]]+0\)[[:space:]]+vsource[[:space:]]+dc=VCM([[:space:]]|$)' "$BASE_NETLIST" || true)"
    bias_count="$(grep -Ec '^V3[[:space:]]+\(net10[[:space:]]+0\)[[:space:]]+vsource[[:space:]]+dc=550\.00m([[:space:]]|$)' "$BASE_NETLIST" || true)"

    printf 'SOURCE_MOS_DEVICE_COUNT=%s\n' "$mos_count"
    printf 'SOURCE_IPRB0_COUNT=%s\n' "$probe_count"
    printf 'SOURCE_FEEDBACK_CONNECTION_COUNT=%s\n' "$feedback_count"
    printf 'SOURCE_LOAD_CAPACITOR_COUNT=%s\n' "$capacitor_count"
    printf 'SOURCE_VDD_SOURCE_COUNT=%s\n' "$vdd_count"
    printf 'SOURCE_INPUT_SOURCE_COUNT=%s\n' "$input_count"
    printf 'SOURCE_BIAS_SOURCE_COUNT=%s\n' "$bias_count"

    if [[ "$mos_count" -ne 5 || "$probe_count" -ne 1 || "$feedback_count" -ne 1 || \
          "$capacitor_count" -ne 1 || "$vdd_count" -ne 1 || "$input_count" -ne 1 || \
          "$bias_count" -ne 1 ]]; then
        printf 'ERROR: SOURCE_TOPOLOGY_VALIDATION_FAILED\n' >&2
        return 1
    fi
}

create_mc_dut_netlist() {
    awk \
        -v step="$STEP" \
        -v step_delay="$STEP_DELAY" \
        -v step_rise="$STEP_RISE" \
        -v step_fall="$STEP_FALL" \
        -v step_width="$STEP_WIDTH" \
        -v step_period="$STEP_PERIOD" \
        -v nominal_nmos="$NOMINAL_NMOS_MODEL" \
        -v nominal_pmos="$NOMINAL_PMOS_MODEL" \
        -v nmos_wrapper="$NMOS_MISMATCH_WRAPPER" \
        -v pmos_wrapper="$PMOS_MISMATCH_WRAPPER" '
    BEGIN {
        print "simulator lang=spectre"
        print ""
    }
    /^(PM0|PM1)[[:space:]]/ {
        sub("\\) " nominal_pmos " ", ") " pmos_wrapper " ")
    }
    /^(NM0|NM1|NM2)[[:space:]]/ {
        sub("\\) " nominal_nmos " ", ") " nmos_wrapper " ")
    }
    /^V0[[:space:]]+\(net013[[:space:]]+0\)[[:space:]]+vsource/ {
        sub(/type=sine/, "type=pulse val0=VCM val1=VCM+" step " delay=" step_delay " rise=" step_rise " fall=" step_fall " width=" step_width " period=" step_period)
    }
    {
        gsub(/m=\(1\)\*\(1\)/, "mr=1 mismod=1")
        print
    }
    ' "$BASE_NETLIST" > "$DUT_NETLIST"
}

validate_mc_dut_netlist() {
    local wrapper_count mismatch_enable_count nominal_mos_count probe_count pulse_count

    wrapper_count="$(grep -Ec "^(PM0|PM1|NM0|NM1|NM2)[[:space:]].*($NMOS_MISMATCH_WRAPPER|$PMOS_MISMATCH_WRAPPER)" "$DUT_NETLIST" || true)"
    mismatch_enable_count="$(grep -Ec 'mismod=1' "$DUT_NETLIST" || true)"
    nominal_mos_count="$(grep -Ec "^(PM0|PM1|NM0|NM1|NM2)[[:space:]].*($NOMINAL_NMOS_MODEL|$NOMINAL_PMOS_MODEL)" "$DUT_NETLIST" || true)"
    probe_count="$(grep -Ec '^IPRB0[[:space:]]+\(net012[[:space:]]+vout\)[[:space:]]+iprobe([[:space:]]|$)' "$DUT_NETLIST" || true)"
    pulse_count="$(grep -Ec '^V0[[:space:]].*type=pulse.*val0=VCM.*val1=VCM\+' "$DUT_NETLIST" || true)"

    printf 'MC_WRAPPER_DEVICE_COUNT=%s\n' "$wrapper_count"
    printf 'MISMATCH_ENABLED_DEVICE_COUNT=%s\n' "$mismatch_enable_count"
    printf 'NOMINAL_MODEL_DEVICE_COUNT=%s\n' "$nominal_mos_count"
    printf 'MC_IPRB0_COUNT=%s\n' "$probe_count"
    printf 'TRANSIENT_PULSE_SOURCE_COUNT=%s\n' "$pulse_count"

    if [[ "$wrapper_count" -ne 5 || "$mismatch_enable_count" -ne 5 || \
          "$nominal_mos_count" -ne 0 || "$probe_count" -ne 1 || "$pulse_count" -ne 1 ]]; then
        printf 'ERROR: MC_TRANSIENT_DUT_VALIDATION_FAILED\n' >&2
        return 1
    fi
}

create_driver_netlist() {
    cat > "$DRIVER_NETLIST" <<EOF
simulator lang=spectre
global 0

parameters VCM=$VCM

include "$MODEL_FILE" section=$MODEL_SECTION
simulator lang=spectre
include "$DUT_NETLIST"

simulatorOptions options temp=$TEMPERATURE tnom=27
saveOptions options save=allpub currents=selected
save vout net013 net012
save V2:p

mc_transient montecarlo \\
    numruns=$NUMRUNS \\
    seed=$SEED \\
    variations=$VARIATIONS \\
    sampling=standard \\
    donominal=yes \\
    scalarfile="transient.mcdata" \\
    paramfile="transient.mcparam" \\
    saveprocessparams=yes \\
    processscalarfile="process.mcdata" \\
    processparamfile="process.mcparam" \\
    savemismatchparams=yes \\
    mismatchscalarfile="mismatch.mcdata" \\
    mismatchparamfile="mismatch.mcparam" \\
    dumpseed=yes \\
    savefamilyplots=yes {
    dcOp dc
    tran tran stop=$TRAN_STOP maxstep=$TRAN_MAXSTEP
    export VOUT_DC=oceanEval("value(v(\"vout\" ?result \"dcOp\") 0)")
    export VOUT_AT_5NS=oceanEval("value(v(\"vout\" ?result \"tran\") 5n)")
    export VOUT_AT_10NS=oceanEval("value(v(\"vout\" ?result \"tran\") 10n)")
    export VOUT_AT_20NS=oceanEval("value(v(\"vout\" ?result \"tran\") 20n)")
    export VOUT_AT_30NS=oceanEval("value(v(\"vout\" ?result \"tran\") 30n)")
    export VDD_CURRENT_A=oceanEval("value(getData(\"V2:p\" ?result \"dcOp\") 0)")
    export VDD_POWER_W=oceanEval("-$VDD * value(getData(\"V2:p\" ?result \"dcOp\") 0)")
}
EOF

    cat > "$SCHEMA_FILE" <<'EOF'
TRANSIENT_MCDATA_COLUMN_1=VOUT_DC_V
TRANSIENT_MCDATA_COLUMN_2=VOUT_AT_5NS_V
TRANSIENT_MCDATA_COLUMN_3=VOUT_AT_10NS_V
TRANSIENT_MCDATA_COLUMN_4=VOUT_AT_20NS_V
TRANSIENT_MCDATA_COLUMN_5=VOUT_AT_30NS_V
TRANSIENT_MCDATA_COLUMN_6=VDD_CURRENT_A
TRANSIENT_MCDATA_COLUMN_7=VDD_POWER_W
EOF
}

check_random_streams() {
    local reference_process reference_mismatch process_match mismatch_match
    reference_process="$REFERENCE_RESULT_ROOT/psf/process.mcdata"
    reference_mismatch="$REFERENCE_RESULT_ROOT/psf/mismatch.mcdata"
    process_match="NOT_CHECKED"
    mismatch_match="NOT_CHECKED"

    if [[ -s "$reference_process" ]]; then
        if cmp -s "$PROCESS_SCALAR_FILE" "$reference_process"; then process_match="MATCH"; else process_match="MISMATCH"; fi
    else
        process_match="REFERENCE_MISSING"
    fi

    if [[ -s "$reference_mismatch" ]]; then
        if cmp -s "$MISMATCH_SCALAR_FILE" "$reference_mismatch"; then mismatch_match="MATCH"; else mismatch_match="MISMATCH"; fi
    else
        mismatch_match="REFERENCE_MISSING"
    fi

    {
        printf 'REFERENCE_RESULT_ROOT=%s\n' "$REFERENCE_RESULT_ROOT"
        printf 'PROCESS_RANDOM_STREAM=%s\n' "$process_match"
        printf 'MISMATCH_RANDOM_STREAM=%s\n' "$mismatch_match"
        printf 'PROCESS_TRANSIENT_SHA256=%s\n' "$(sha256sum "$PROCESS_SCALAR_FILE" | awk '{print $1}')"
        printf 'MISMATCH_TRANSIENT_SHA256=%s\n' "$(sha256sum "$MISMATCH_SCALAR_FILE" | awk '{print $1}')"
        [[ -s "$reference_process" ]] && printf 'PROCESS_REFERENCE_SHA256=%s\n' "$(sha256sum "$reference_process" | awk '{print $1}')"
        [[ -s "$reference_mismatch" ]] && printf 'MISMATCH_REFERENCE_SHA256=%s\n' "$(sha256sum "$reference_mismatch" | awk '{print $1}')"
    } | tee "$STREAM_CHECK_FILE"

    [[ "$process_match" == "MATCH" && "$mismatch_match" == "MATCH" ]]
}

prepare_run() {
    validate_source_topology || return 1
    create_mc_dut_netlist || return 1
    validate_mc_dut_netlist || return 1
    create_driver_netlist || return 1
    sha256sum "$BASE_NETLIST" "$DUT_NETLIST" "$DRIVER_NETLIST" "$SCHEMA_FILE" > "$CHECKSUM_FILE"

    {
        printf 'MONTE_CARLO_TRANSIENT_PREPARED\n'
        printf 'SCRIPT_VERSION=%s\n' "$SCRIPT_VERSION"
        printf 'RUN_ID=%s\n' "$RUN_ID"
        printf 'VARIATIONS=%s\n' "$VARIATIONS"
        printf 'NUMRUNS=%s\n' "$NUMRUNS"
        printf 'SEED=%s\n' "$SEED"
        printf 'VCM=%s V\n' "$VCM"
        printf 'VDD=%s V\n' "$VDD"
        printf 'STEP_SIZE=%s V\n' "$STEP"
        printf 'STEP_DELAY=%s\n' "$STEP_DELAY"
        printf 'STEP_RISE=%s\n' "$STEP_RISE"
        printf 'STEP_FALL=%s\n' "$STEP_FALL"
        printf 'STEP_WIDTH=%s\n' "$STEP_WIDTH"
        printf 'STEP_PERIOD=%s\n' "$STEP_PERIOD"
        printf 'TRAN_STOP=%s\n' "$TRAN_STOP"
        printf 'TRAN_MAXSTEP=%s\n' "$TRAN_MAXSTEP"
        printf 'TEMPERATURE=%s C\n' "$TEMPERATURE"
        printf 'MODEL_SECTION=%s\n' "$MODEL_SECTION"
        printf 'OPERATING_POINT=UNITY_FEEDBACK\n'
        printf 'DUT_NETLIST=%s\n' "$DUT_NETLIST"
        printf 'DRIVER_NETLIST=%s\n' "$DRIVER_NETLIST"
        printf 'SCHEMA_FILE=%s\n' "$SCHEMA_FILE"
        printf 'RESULT_ROOT=%s\n' "$RESULT_ROOT"
        printf 'REFERENCE_RESULT_ROOT=%s\n' "$REFERENCE_RESULT_ROOT"
    } | tee "$PREPARE_FILE"
}

count_valid_rows() {
    local file_path="$1"
    [[ -s "$file_path" ]] || { printf '0\n'; return; }

    awk '
    function numeric(x) { return x ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/ }
    NF == 7 {
        valid=1
        for (i=1; i<=7; i++) if (!numeric($i)) valid=0
        if (valid) count++
    }
    END { print count+0 }
    ' "$file_path"
}

run_transient_validation() {
    local start_epoch end_epoch elapsed spectre_status error_count valid_rows invalid_numeric_rows failed_iterations stream_status validation_failed
    validation_failed=0

    if [[ -s "$COMPLETE_MARKER" && "$FORCE" == "0" ]]; then
        printf 'MONTE_CARLO_TRANSIENT_SKIPPED=VERIFIED_MARKER\n'
        printf 'COMPLETE_MARKER=%s\n' "$COMPLETE_MARKER"
        cat "$SUMMARY_FILE"
        return 0
    fi

    rm -f -- "$TRANSIENT_SCALAR_FILE" "$TRANSIENT_PARAM_FILE" \
        "$PROCESS_SCALAR_FILE" "$PROCESS_PARAM_FILE" \
        "$MISMATCH_SCALAR_FILE" "$MISMATCH_PARAM_FILE" \
        "$RUN_LOG" "$COMPLETE_MARKER" "$STREAM_CHECK_FILE"

    start_epoch="$(date +%s)"
    printf 'MONTE_CARLO_TRANSIENT_STARTED\n'
    printf 'VARIATIONS=%s NUMRUNS=%s SEED=%s\n' "$VARIATIONS" "$NUMRUNS" "$SEED"
    printf 'TRANSIENT_STEP=%s V AT %s\n' "$STEP" "$STEP_DELAY"

    (
        cd "$RESULT_ROOT" || exit 1
        spectre -64 "$DRIVER_NETLIST" -format psfbin -raw "$RAW_DIR" +log "$RUN_LOG"
    )
    spectre_status=$?
    end_epoch="$(date +%s)"
    elapsed=$((end_epoch - start_epoch))

    error_count="$(grep -cEi '\*Error\*|(^|[[:space:]])ERROR([[:space:]:]|$)|FATAL|Segmentation fault' "$RUN_LOG" 2>/dev/null || true)"
    valid_rows="$(count_valid_rows "$TRANSIENT_SCALAR_FILE")"
    invalid_numeric_rows="$(awk 'NF > 0 && $1 ~ /^[-+]?[0-9]/ && NF != 7 {count++} END {print count+0}' "$TRANSIENT_SCALAR_FILE" 2>/dev/null || printf '0\n')"
    failed_iterations="$(grep -cEi 'monte carlo iteration.*failed|iteration.*did not converge' "$RUN_LOG" 2>/dev/null || true)"

    if [[ "$spectre_status" -ne 0 || "$error_count" -ne 0 || "$failed_iterations" -ne 0 ]]; then
        validation_failed=1
    fi

    if [[ ! -s "$TRANSIENT_SCALAR_FILE" || ! -s "$TRANSIENT_PARAM_FILE" ]]; then
        printf 'ERROR: TRANSIENT_OUTPUT_MISSING\n' >&2
        validation_failed=1
    fi

    if [[ "$valid_rows" -ne "$NUMRUNS" || "$invalid_numeric_rows" -ne 0 ]]; then
        printf 'ERROR: TRANSIENT_ROW_VALIDATION_FAILED VALID=%s INVALID=%s EXPECTED=%s\n' "$valid_rows" "$invalid_numeric_rows" "$NUMRUNS" >&2
        validation_failed=1
    fi

    [[ -s "$PROCESS_SCALAR_FILE" && -s "$PROCESS_PARAM_FILE" ]] || validation_failed=1
    [[ -s "$MISMATCH_SCALAR_FILE" && -s "$MISMATCH_PARAM_FILE" ]] || validation_failed=1

    if [[ -s "$PROCESS_SCALAR_FILE" && -s "$MISMATCH_SCALAR_FILE" ]]; then
        check_random_streams
        stream_status=$?
        [[ "$stream_status" -eq 0 ]] || validation_failed=1
    else
        stream_status=1
    fi

    {
        printf 'MONTE_CARLO_TRANSIENT_SUMMARY_BEGIN\n'
        printf 'SCRIPT_VERSION=%s\n' "$SCRIPT_VERSION"
        printf 'RUN_ID=%s\n' "$RUN_ID"
        printf 'VARIATIONS=%s\n' "$VARIATIONS"
        printf 'NUMRUNS_REQUESTED=%s\n' "$NUMRUNS"
        printf 'SEED=%s\n' "$SEED"
        printf 'OPERATING_POINT=UNITY_FEEDBACK\n'
        printf 'VCM=%s V\n' "$VCM"
        printf 'VDD=%s V\n' "$VDD"
        printf 'STEP_SIZE=%s V\n' "$STEP"
        printf 'STEP_DELAY=%s\n' "$STEP_DELAY"
        printf 'TRAN_STOP=%s\n' "$TRAN_STOP"
        printf 'TRAN_MAXSTEP=%s\n' "$TRAN_MAXSTEP"
        printf 'TEMPERATURE=%s C\n' "$TEMPERATURE"
        printf 'SPECTRE_EXIT_STATUS=%s\n' "$spectre_status"
        printf 'ELAPSED_SECONDS=%s\n' "$elapsed"
        printf 'LOG_ERROR_COUNT=%s\n' "$error_count"
        printf 'FAILED_MONTE_CARLO_ITERATIONS=%s\n' "$failed_iterations"
        printf 'TRANSIENT_VALID_ROWS=%s\n' "$valid_rows"
        printf 'TRANSIENT_INVALID_NUMERIC_ROWS=%s\n' "$invalid_numeric_rows"
        if [[ "$stream_status" -eq 0 ]]; then printf 'RANDOM_STREAM_CHECK=MATCHED\n'; else printf 'RANDOM_STREAM_CHECK=FAILED\n'; fi
        printf 'TRANSIENT_SCALAR_FILE=%s\n' "$TRANSIENT_SCALAR_FILE"
        printf 'TRANSIENT_PARAM_FILE=%s\n' "$TRANSIENT_PARAM_FILE"
        printf 'TRANSIENT_SCHEMA_FILE=%s\n' "$SCHEMA_FILE"
        printf 'RANDOM_STREAM_CHECK_FILE=%s\n' "$STREAM_CHECK_FILE"
        printf 'SPECTRE_LOG=%s\n' "$RUN_LOG"
        if [[ "$validation_failed" -eq 0 ]]; then
            printf 'MONTE_CARLO_TRANSIENT_STATUS=PASSED\n'
        else
            printf 'MONTE_CARLO_TRANSIENT_STATUS=FAILED\n'
        fi
        printf 'MONTE_CARLO_TRANSIENT_SUMMARY_END\n'
    } | tee "$SUMMARY_FILE"

    {
        printf 'RUN_ID\tVARIATIONS\tNUMRUNS\tSEED\tSTATUS\tEXIT_STATUS\tELAPSED_SECONDS\tERROR_COUNT\tFAILED_ITERATIONS\tVALID_ROWS\tSTREAM_CHECK\tLOG\n'
        if [[ "$validation_failed" -eq 0 ]]; then
            printf '%s\t%s\t%s\t%s\tPASSED\t%s\t%s\t%s\t%s\t%s\tMATCHED\t%s\n' "$RUN_ID" "$VARIATIONS" "$NUMRUNS" "$SEED" "$spectre_status" "$elapsed" "$error_count" "$failed_iterations" "$valid_rows" "$RUN_LOG"
        else
            printf '%s\t%s\t%s\t%s\tFAILED\t%s\t%s\t%s\t%s\t%s\tFAILED\t%s\n' "$RUN_ID" "$VARIATIONS" "$NUMRUNS" "$SEED" "$spectre_status" "$elapsed" "$error_count" "$failed_iterations" "$valid_rows" "$RUN_LOG"
        fi
    } > "$STATUS_FILE"

    if [[ "$validation_failed" -ne 0 ]]; then
        return 1
    fi

    {
        printf 'RUN_ID=%s\n' "$RUN_ID"
        printf 'VARIATIONS=%s\n' "$VARIATIONS"
        printf 'NUMRUNS=%s\n' "$NUMRUNS"
        printf 'SEED=%s\n' "$SEED"
        printf 'RANDOM_STREAM_CHECK=MATCHED\n'
        printf 'COMPLETED_AT=%s\n' "$(date -Is)"
        printf 'SUMMARY_SHA256=%s\n' "$(sha256sum "$SUMMARY_FILE" | awk '{print $1}')"
        printf 'DATA_SHA256=%s\n' "$(sha256sum "$TRANSIENT_SCALAR_FILE" | awk '{print $1}')"
    } > "$COMPLETE_MARKER"

    printf 'MONTE_CARLO_TRANSIENT_VERIFIED\n'
    printf 'SUMMARY_FILE=%s\n' "$SUMMARY_FILE"
    printf 'STATUS_FILE=%s\n' "$STATUS_FILE"
    printf 'RANDOM_STREAM_CHECK_FILE=%s\n' "$STREAM_CHECK_FILE"
    printf 'COMPLETE_MARKER=%s\n' "$COMPLETE_MARKER"
}

if ! prepare_run; then
    printf 'ERROR: MONTE_CARLO_TRANSIENT_PREPARATION_FAILED\n' >&2
    exit 1
fi

if [[ "$MODE" == "prepare" ]]; then
    printf 'MODE=prepare\n'
    exit 0
fi

run_transient_validation
