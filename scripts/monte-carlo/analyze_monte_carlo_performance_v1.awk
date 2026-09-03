BEGIN {
    FS = " "
    OFS = "\t"
    name[1] = "VOUT_DC_V"
    name[2] = "VDD_CURRENT_A"
    name[3] = "VDD_POWER_W"
    name[4] = "LOOP_GAIN_DB_1HZ"
    name[5] = "UGF_HZ"
    name[6] = "PHASE_MARGIN_DEG"
}

function is_numeric(value) {
    return value ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/
}

NF == 6 {
    row_valid = 1
    for (column = 1; column <= 6; column++) {
        if (!is_numeric($column)) {
            row_valid = 0
        }
    }

    if (!row_valid) {
        invalid_rows++
        next
    }

    row_count++
    for (column = 1; column <= 6; column++) {
        value = $column + 0
        total[column] += value
        total_square[column] += value * value
        if (!(column in minimum) || value < minimum[column]) minimum[column] = value
        if (!(column in maximum) || value > maximum[column]) maximum[column] = value
    }

    if (($5 + 0) <= 0) {
        nonpositive_ugf++
    }
}

NF != 6 && NF > 0 && $1 ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/ {
    non_six_column_rows++
}

END {
    print "PERFORMANCE_ANALYSIS_BEGIN"
    print "VALID_ROWS=" row_count + 0
    print "INVALID_NUMERIC_ROWS=" invalid_rows + 0
    print "NON_SIX_COLUMN_ROWS=" non_six_column_rows + 0
    print "NONPOSITIVE_UGF_ROWS=" nonpositive_ugf + 0
    print "METRIC\tN\tMEAN\tSAMPLE_SIGMA\tMIN\tMAX"

    for (column = 1; column <= 6; column++) {
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

    print "PERFORMANCE_ANALYSIS_END"
}
