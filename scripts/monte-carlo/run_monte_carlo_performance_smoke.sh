#!/usr/bin/env bash

# Native-Spectre Monte Carlo performance runner template.
#
# This public template intentionally uses generic paths and model names.
# Set MC_STB_BASE_NETLIST, MC_MODEL_FILE, and wrapper/model variables for the
# local PDK before running.

set -u
set -o pipefail

SCRIPT_VERSION=1

BASE_NETLIST="${MC_STB_BASE_NETLIST:-$HOME/simulation/ota_project_stb/spectre/schematic/netlist/netlist}"
MODEL_FILE="${MC_MODEL_FILE:-$HOME/pdk/models/spectre/model.lib}"
RESULT_ROOT_BASE="${MC_PERFORMANCE_RESULT_ROOT:-$HOME/simulation/ota_project_ocean/monte_carlo_performance}"
MODEL_SECTION="${MC_MODEL_SECTION:-mc}"
NOMINAL_NMOS_MODEL="${MC_NOMINAL_NMOS_MODEL:-nmos_nominal}"
NOMINAL_PMOS_MODEL="${MC_NOMINAL_PMOS_MODEL:-pmos_nominal}"
NMOS_MISMATCH_WRAPPER="${MC_NMOS_MISMATCH_WRAPPER:-nmos_mismatch_wrapper}"
PMOS_MISMATCH_WRAPPER="${MC_PMOS_MISMATCH_WRAPPER:-pmos_mismatch_wrapper}"

NUMRUNS="${MC_NUMRUNS:-10}"
SEED="${MC_SEED:-20260902}"
VARIATIONS="${MC_VARIATIONS:-all}"
VCM="${MC_VCM:-0.8}"
VDD="${MC_VDD:-1.2}"
TEMPERATURE="${MC_TEMPERATURE:-27}"
STB_START="${MC_STB_START:-1}"
STB_STOP="${MC_STB_STOP:-100G}"
STB_DEC="${MC_STB_DEC:-100}"
FORCE="${MC_FORCE:-0}"
MODE="${1:-full}"

case "$MODE" in
    prepare|full) ;;
    *) printf 'ERROR: INVALID_MODE=%s\nVALID_MODES=prepare full\n' "$MODE" >&2; exit 2 ;;
esac

case "$VARIATIONS" in
    process|mismatch|all) ;;
    *) printf 'ERROR: INVALID_VARIATIONS=%s\nVALID_VARIATIONS=process mismatch all\n' "$VARIATIONS" >&2; exit 2 ;;
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

DUT_NETLIST="$INPUT_DIR/ota_stb_mc.netlist"
DRIVER_NETLIST="$INPUT_DIR/monte_carlo_performance.scs"
SCHEMA_FILE="$INPUT_DIR/performance_mcdata_schema.txt"
RUN_LOG="$LOG_DIR/spectre.log"
PREPARE_FILE="$SUMMARY_DIR/monte_carlo_performance_prepare.txt"
SUMMARY_FILE="$SUMMARY_DIR/monte_carlo_performance_summary.txt"
STATUS_FILE="$SUMMARY_DIR/monte_carlo_performance_status.tsv"
CHECKSUM_FILE="$SUMMARY_DIR/monte_carlo_performance_inputs.sha256"
COMPLETE_MARKER="$RESULT_ROOT/.complete"

PERFORMANCE_SCALAR_FILE="$RAW_DIR/performance.mcdata"
PERFORMANCE_PARAM_FILE="$RAW_DIR/performance.mcparam"
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
    {
        gsub(/m=\(1\)\*\(1\)/, "mr=1 mismod=1")
        print
    }
    ' "$BASE_NETLIST" > "$DUT_NETLIST"
}

validate_mc_dut_netlist() {
    local wrapper_count mismatch_enable_count nominal_mos_count probe_count

    wrapper_count="$(grep -Ec "^(PM0|PM1|NM0|NM1|NM2)[[:space:]].*($NMOS_MISMATCH_WRAPPER|$PMOS_MISMATCH_WRAPPER)" "$DUT_NETLIST" || true)"
    mismatch_enable_count="$(grep -Ec 'mismod=1' "$DUT_NETLIST" || true)"
    nominal_mos_count="$(grep -Ec "^(PM0|PM1|NM0|NM1|NM2)[[:space:]].*($NOMINAL_NMOS_MODEL|$NOMINAL_PMOS_MODEL)" "$DUT_NETLIST" || true)"
    probe_count="$(grep -Ec '^IPRB0[[:space:]]+\(net012[[:space:]]+vout\)[[:space:]]+iprobe([[:space:]]|$)' "$DUT_NETLIST" || true)"

    printf 'MC_WRAPPER_DEVICE_COUNT=%s\n' "$wrapper_count"
    printf 'MISMATCH_ENABLED_DEVICE_COUNT=%s\n' "$mismatch_enable_count"
    printf 'NOMINAL_MODEL_DEVICE_COUNT=%s\n' "$nominal_mos_count"
    printf 'MC_IPRB0_COUNT=%s\n' "$probe_count"

    if [[ "$wrapper_count" -ne 5 || "$mismatch_enable_count" -ne 5 || \
          "$nominal_mos_count" -ne 0 || "$probe_count" -ne 1 ]]; then
        printf 'ERROR: MC_DUT_NETLIST_VALIDATION_FAILED\n' >&2
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

mc_performance montecarlo \\
    numruns=$NUMRUNS \\
    seed=$SEED \\
    variations=$VARIATIONS \\
    sampling=standard \\
    donominal=yes \\
    scalarfile="performance.mcdata" \\
    paramfile="performance.mcparam" \\
    saveprocessparams=yes \\
    processscalarfile="process.mcdata" \\
    processparamfile="process.mcparam" \\
    savemismatchparams=yes \\
    mismatchscalarfile="mismatch.mcdata" \\
    mismatchparamfile="mismatch.mcparam" \\
    dumpseed=yes \\
    savefamilyplots=yes {
    dcOp dc
    loopStb stb start=$STB_START stop=$STB_STOP dec=$STB_DEC probe=IPRB0
    export VOUT_DC=oceanEval("value(v(\"vout\" ?result \"dcOp\") 0)")
    export VDD_CURRENT_A=oceanEval("value(getData(\"V2:p\" ?result \"dcOp\") 0)")
    export VDD_POWER_W=oceanEval("-$VDD * value(getData(\"V2:p\" ?result \"dcOp\") 0)")
    export LOOP_GAIN_DB_1HZ=oceanEval("value(db20(getData(\"loopGain\" ?result \"stb\")) 1)")
    export UGF_HZ=oceanEval("unityGainFreq(getData(\"loopGain\" ?result \"stb\"))")
    export PHASE_MARGIN_DEG=oceanEval("phaseMargin(-getData(\"loopGain\" ?result \"stb\"))")
}
EOF

    cat > "$SCHEMA_FILE" <<'EOF'
PERFORMANCE_MCDATA_COLUMN_1=VOUT_DC_V
PERFORMANCE_MCDATA_COLUMN_2=VDD_CURRENT_A
PERFORMANCE_MCDATA_COLUMN_3=VDD_POWER_W
PERFORMANCE_MCDATA_COLUMN_4=LOOP_GAIN_DB_1HZ
PERFORMANCE_MCDATA_COLUMN_5=UGF_HZ
PERFORMANCE_MCDATA_COLUMN_6=PHASE_MARGIN_DEG
EOF
}

prepare_run() {
    validate_source_topology || return 1
    create_mc_dut_netlist || return 1
    validate_mc_dut_netlist || return 1
    create_driver_netlist || return 1
    sha256sum "$BASE_NETLIST" "$DUT_NETLIST" "$DRIVER_NETLIST" "$SCHEMA_FILE" > "$CHECKSUM_FILE"

    {
        printf 'MONTE_CARLO_PERFORMANCE_PREPARED\n'
        printf 'SCRIPT_VERSION=%s\n' "$SCRIPT_VERSION"
        printf 'RUN_ID=%s\n' "$RUN_ID"
        printf 'VARIATIONS=%s\n' "$VARIATIONS"
        printf 'NUMRUNS=%s\n' "$NUMRUNS"
        printf 'SEED=%s\n' "$SEED"
        printf 'VCM=%s V\n' "$VCM"
        printf 'VDD=%s V\n' "$VDD"
        printf 'TEMPERATURE=%s C\n' "$TEMPERATURE"
        printf 'MODEL_SECTION=%s\n' "$MODEL_SECTION"
        printf 'STB_PROBE_INSTANCE=IPRB0\n'
        printf 'STB_ANALYSIS_INSTANCE=loopStb\n'
        printf 'STB_RESULT_NAME=stb\n'
        printf 'OPERATING_POINT=UNITY_FEEDBACK\n'
        printf 'DUT_NETLIST=%s\n' "$DUT_NETLIST"
        printf 'DRIVER_NETLIST=%s\n' "$DRIVER_NETLIST"
        printf 'SCHEMA_FILE=%s\n' "$SCHEMA_FILE"
        printf 'CHECKSUM_FILE=%s\n' "$CHECKSUM_FILE"
        printf 'RESULT_ROOT=%s\n' "$RESULT_ROOT"
    } | tee "$PREPARE_FILE"
}

count_valid_rows() {
    local file_path="$1"

    if [[ ! -s "$file_path" ]]; then
        printf '0\n'
        return
    fi

    awk '
    function numeric(x) { return x ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/ }
    NF == 6 {
        valid=1
        for (i=1; i<=6; i++) if (!numeric($i)) valid=0
        if (valid) count++
    }
    END { print count+0 }
    ' "$file_path"
}

run_performance() {
    local start_epoch end_epoch elapsed spectre_status error_count valid_rows invalid_numeric_rows failed_iterations validation_failed
    validation_failed=0

    if [[ -s "$COMPLETE_MARKER" && "$FORCE" == "0" ]]; then
        printf 'MONTE_CARLO_PERFORMANCE_SKIPPED=VERIFIED_MARKER\n'
        printf 'COMPLETE_MARKER=%s\n' "$COMPLETE_MARKER"
        cat "$SUMMARY_FILE"
        return 0
    fi

    rm -f -- "$PERFORMANCE_SCALAR_FILE" "$PERFORMANCE_PARAM_FILE" \
        "$PROCESS_SCALAR_FILE" "$PROCESS_PARAM_FILE" \
        "$MISMATCH_SCALAR_FILE" "$MISMATCH_PARAM_FILE" \
        "$RUN_LOG" "$COMPLETE_MARKER"

    start_epoch="$(date +%s)"
    printf 'MONTE_CARLO_PERFORMANCE_STARTED\n'
    printf 'VARIATIONS=%s NUMRUNS=%s SEED=%s\n' "$VARIATIONS" "$NUMRUNS" "$SEED"

    (
        cd "$RESULT_ROOT" || exit 1
        spectre -64 "$DRIVER_NETLIST" -format psfbin -raw "$RAW_DIR" +log "$RUN_LOG"
    )
    spectre_status=$?
    end_epoch="$(date +%s)"
    elapsed=$((end_epoch - start_epoch))

    error_count="$(grep -cEi '\*Error\*|(^|[[:space:]])ERROR([[:space:]:]|$)|FATAL|Segmentation fault' "$RUN_LOG" 2>/dev/null || true)"
    valid_rows="$(count_valid_rows "$PERFORMANCE_SCALAR_FILE")"
    invalid_numeric_rows="$(awk 'NF > 0 && $1 ~ /^[-+]?[0-9]/ && NF != 6 {count++} END {print count+0}' "$PERFORMANCE_SCALAR_FILE" 2>/dev/null || printf '0\n')"
    failed_iterations="$(grep -cEi 'monte carlo iteration.*failed|iteration.*did not converge' "$RUN_LOG" 2>/dev/null || true)"

    if [[ "$spectre_status" -ne 0 || "$error_count" -ne 0 || "$failed_iterations" -ne 0 ]]; then
        validation_failed=1
    fi

    if [[ ! -s "$PERFORMANCE_SCALAR_FILE" || ! -s "$PERFORMANCE_PARAM_FILE" ]]; then
        printf 'ERROR: PERFORMANCE_OUTPUT_MISSING\n' >&2
        validation_failed=1
    fi

    if [[ "$valid_rows" -ne "$NUMRUNS" || "$invalid_numeric_rows" -ne 0 ]]; then
        printf 'ERROR: PERFORMANCE_ROW_VALIDATION_FAILED VALID=%s INVALID=%s EXPECTED=%s\n' \
            "$valid_rows" "$invalid_numeric_rows" "$NUMRUNS" >&2
        validation_failed=1
    fi

    if [[ "$VARIATIONS" == "process" || "$VARIATIONS" == "all" ]]; then
        [[ -s "$PROCESS_SCALAR_FILE" && -s "$PROCESS_PARAM_FILE" ]] || validation_failed=1
    fi

    if [[ "$VARIATIONS" == "mismatch" || "$VARIATIONS" == "all" ]]; then
        [[ -s "$MISMATCH_SCALAR_FILE" && -s "$MISMATCH_PARAM_FILE" ]] || validation_failed=1
    fi

    {
        printf 'MONTE_CARLO_PERFORMANCE_SUMMARY_BEGIN\n'
        printf 'SCRIPT_VERSION=%s\n' "$SCRIPT_VERSION"
        printf 'RUN_ID=%s\n' "$RUN_ID"
        printf 'VARIATIONS=%s\n' "$VARIATIONS"
        printf 'NUMRUNS_REQUESTED=%s\n' "$NUMRUNS"
        printf 'SEED=%s\n' "$SEED"
        printf 'OPERATING_POINT=UNITY_FEEDBACK\n'
        printf 'VCM=%s V\n' "$VCM"
        printf 'VDD=%s V\n' "$VDD"
        printf 'TEMPERATURE=%s C\n' "$TEMPERATURE"
        printf 'SPECTRE_EXIT_STATUS=%s\n' "$spectre_status"
        printf 'ELAPSED_SECONDS=%s\n' "$elapsed"
        printf 'LOG_ERROR_COUNT=%s\n' "$error_count"
        printf 'FAILED_MONTE_CARLO_ITERATIONS=%s\n' "$failed_iterations"
        printf 'PERFORMANCE_VALID_ROWS=%s\n' "$valid_rows"
        printf 'PERFORMANCE_INVALID_NUMERIC_ROWS=%s\n' "$invalid_numeric_rows"
        printf 'PERFORMANCE_SCALAR_FILE=%s\n' "$PERFORMANCE_SCALAR_FILE"
        printf 'PERFORMANCE_PARAM_FILE=%s\n' "$PERFORMANCE_PARAM_FILE"
        printf 'PERFORMANCE_SCHEMA_FILE=%s\n' "$SCHEMA_FILE"
        printf 'SPECTRE_LOG=%s\n' "$RUN_LOG"
        if [[ "$validation_failed" -eq 0 ]]; then
            printf 'MONTE_CARLO_PERFORMANCE_STATUS=PASSED\n'
        else
            printf 'MONTE_CARLO_PERFORMANCE_STATUS=FAILED\n'
        fi
        printf 'MONTE_CARLO_PERFORMANCE_SUMMARY_END\n'
    } | tee "$SUMMARY_FILE"

    {
        printf 'RUN_ID\tVARIATIONS\tNUMRUNS\tSEED\tSTATUS\tEXIT_STATUS\tELAPSED_SECONDS\tERROR_COUNT\tFAILED_ITERATIONS\tVALID_ROWS\tLOG\n'
        if [[ "$validation_failed" -eq 0 ]]; then
            printf '%s\t%s\t%s\t%s\tPASSED\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$RUN_ID" "$VARIATIONS" "$NUMRUNS" "$SEED" "$spectre_status" "$elapsed" "$error_count" "$failed_iterations" "$valid_rows" "$RUN_LOG"
        else
            printf '%s\t%s\t%s\t%s\tFAILED\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$RUN_ID" "$VARIATIONS" "$NUMRUNS" "$SEED" "$spectre_status" "$elapsed" "$error_count" "$failed_iterations" "$valid_rows" "$RUN_LOG"
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
        printf 'COMPLETED_AT=%s\n' "$(date -Is)"
        printf 'SUMMARY_SHA256=%s\n' "$(sha256sum "$SUMMARY_FILE" | awk '{print $1}')"
        printf 'DATA_SHA256=%s\n' "$(sha256sum "$PERFORMANCE_SCALAR_FILE" | awk '{print $1}')"
    } > "$COMPLETE_MARKER"

    printf 'MONTE_CARLO_PERFORMANCE_VERIFIED\n'
    printf 'SUMMARY_FILE=%s\n' "$SUMMARY_FILE"
    printf 'STATUS_FILE=%s\n' "$STATUS_FILE"
    printf 'COMPLETE_MARKER=%s\n' "$COMPLETE_MARKER"
}

if ! prepare_run; then
    printf 'ERROR: MONTE_CARLO_PERFORMANCE_PREPARATION_FAILED\n' >&2
    exit 1
fi

if [[ "$MODE" == "prepare" ]]; then
    printf 'MODE=prepare\n'
    exit 0
fi

run_performance
