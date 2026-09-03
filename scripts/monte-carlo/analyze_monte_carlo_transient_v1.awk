BEGIN {
    FS = " "
    OFS = "\t"
    step = step + 0
    name[1] = "VOUT_DC_V"
    name[2] = "VOUT_AT_5NS_V"
    name[3] = "VOUT_AT_10NS_V"
    name[4] = "VOUT_AT_20NS_V"
    name[5] = "VOUT_AT_30NS_V"
    name[6] = "VDD_CURRENT_A"
    name[7] = "VDD_POWER_W"
    name[8] = "HIGH_STEP_AT_5NS_V"
    name[9] = "HIGH_STEP_AT_10NS_V"
    name[10] = "HIGH_STEP_ERROR_AT_10NS_V"
    name[11] = "RETURN_ERROR_AT_20NS_V"
    name[12] = "RETURN_ERROR_AT_30NS_V"
}

function is_numeric(value) {
    return value ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/
}

NF == 7 {
    row_valid = 1
    for (column = 1; column <= 7; column++) {
        if (!is_numeric($column)) row_valid = 0
    }

    if (!row_valid) {
        invalid_rows++
        next
    }

    row_count++
    derived[1] = $1 + 0
    derived[2] = $2 + 0
    derived[3] = $3 + 0
    derived[4] = $4 + 0
    derived[5] = $5 + 0
    derived[6] = $6 + 0
    derived[7] = $7 + 0
    derived[8] = ($2 - $1) + 0
    derived[9] = ($3 - $1) + 0
    derived[10] = ($3 - $1 - step) + 0
    derived[11] = ($4 - $1) + 0
    derived[12] = ($5 - $1) + 0

    for (column = 1; column <= 12; column++) {
        value = derived[column]
        total[column] += value
        total_square[column] += value * value
        if (!(column in minimum) || value < minimum[column]) minimum[column] = value
        if (!(column in maximum) || value > maximum[column]) maximum[column] = value
    }
}

NF != 7 && NF > 0 && $1 ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/ {
    non_seven_column_rows++
}

END {
    print "TRANSIENT_ANALYSIS_BEGIN"
    print "VALID_ROWS=" row_count + 0
    print "INVALID_NUMERIC_ROWS=" invalid_rows + 0
    print "NON_SEVEN_COLUMN_ROWS=" non_seven_column_rows + 0
    printf "STEP_TARGET_V=%.12e\n", step
    print "METRIC\tN\tMEAN\tSAMPLE_SIGMA\tMIN\tMAX"

    for (column = 1; column <= 12; column++) {
        mean = row_count > 0 ? total[column] / row_count : 0
        if (row_count > 1) {
            variance = (total_square[column] - (total[column] * total[column] / row_count)) / (row_count - 1)
            if (variance < 0 && variance > -1e-24) variance = 0
            sigma = sqrt(variance)
        } else {
            sigma = 0
        }

        printf "%s\t%d\t%.12e\t%.12e\t%.12e\t%.12e\n", name[column], row_count, mean, sigma, minimum[column], maximum[column]
    }

    print "TRANSIENT_ANALYSIS_END"
}
