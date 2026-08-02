#!/usr/bin/env bash

# Continue the sweep even if one run exits abnormally.
set -u

export LC_NUMERIC=C

MULTIPLIER="1.25"

# These values must match Linefollower.h.
MAX_STEPS=200000
ERROR_THRESHOLD="0.001"
SUCCESS_STEPS=1000

usage()
{
    echo "Usage:"
    echo "  $0 <start_lr> <upper_lr> <seed> <layers> [output_directory]"
    echo
    echo "Example:"
    echo "  $0 0.0001 0.001 42 9,6,6"
    echo "  $0 0.0001 0.001 42 3,3,6 /tmp/cldl_results"
}

if [[ $# -lt 4 || $# -gt 5 ]]; then
    usage
    exit 1
fi

START_LR="$(
    awk -v value="$1" '
        BEGIN {
            printf "%.6e", value + 0
        }
    '
)"

UPPER_LR="$(
    awk -v value="$2" '
        BEGIN {
            printf "%.6e", value + 0
        }
    '
)"

SEED="$3"
LAYERS="$4"

# This script is stored in the cldl source directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repository root is the parent directory of cldl/.
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Compiled CLDL executable.
BINARY="$REPO_ROOT/build/cldl/linefollowercldl"
BINARY_DIR="$(dirname "$BINARY")"

# The optional fifth argument specifies the base output directory.
# Every script instance creates its own unique sweep directory inside it.
BASE_OUTPUT_DIR="${5:-$SCRIPT_DIR/StatDataCldl}"

# Check the executable.
if [[ ! -x "$BINARY" ]]; then
    echo "Error: CLDL executable not found:" >&2
    echo "  $BINARY" >&2
    echo "Compile the project first using ./build.sh" >&2
    exit 1
fi

# Validate learning-rate range.
if ! awk -v start="$START_LR" -v upper="$UPPER_LR" '
    BEGIN {
        exit !(start > 0 && upper >= start)
    }
'; then
    echo "Error: learning rates must satisfy:" >&2
    echo "  start_lr > 0" >&2
    echo "  upper_lr >= start_lr" >&2
    exit 1
fi

# Validate seed.
if ! [[ "$SEED" =~ ^-?[0-9]+$ ]]; then
    echo "Error: seed must be an integer." >&2
    exit 1
fi

# Validate layer-vector format.
if [[ ! "$LAYERS" =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]]; then
    echo "Error: invalid layer vector: $LAYERS" >&2
    echo "Expected format such as: 9,6,6" >&2
    exit 1
fi

# Current steering code requires six output neurons.
if [[ "${LAYERS##*,}" != "6" ]]; then
    echo "Error: the final layer must contain exactly 6 neurons." >&2
    exit 1
fi

# Create and resolve the base output directory.
mkdir -p "$BASE_OUTPUT_DIR" || {
    echo "Error: cannot create output directory:" >&2
    echo "  $BASE_OUTPUT_DIR" >&2
    exit 1
}

BASE_OUTPUT_DIR="$(cd "$BASE_OUTPUT_DIR" && pwd)"

# Timestamp and process ID make each concurrent script instance unique.
TIMESTAMP="$(date '+%Y%m%d_%H%M%S_%N')"
SWEEP_ID="sweep_${TIMESTAMP}_pid$$"
SWEEP_DIR="$BASE_OUTPUT_DIR/$SWEEP_ID"

if ! mkdir "$SWEEP_DIR"; then
    echo "Error: cannot create sweep directory:" >&2
    echo "  $SWEEP_DIR" >&2
    exit 1
fi

STATS_FILE="$SWEEP_DIR/stats_${TIMESTAMP}.dat"

printf \
    "learningrate\tsteps\tavg_error\tseed\tlayers\n" \
    > "$STATS_FILE"

CURRENT_LR="$START_LR"
RUN_INDEX=0

echo "========================================"
echo "CLDL learning-rate sweep"
echo "Start learning rate : $START_LR"
echo "Upper limit         : $UPPER_LR"
echo "Multiplier          : $MULTIPLIER"
echo "Seed                : $SEED"
echo "Layers              : $LAYERS"
echo "Sweep directory     : $SWEEP_DIR"
echo "Statistics file     : $STATS_FILE"
echo "========================================"

# Run the starting learning rate and repeatedly multiply by 1.25.
# The upper limit is not added separately when it is not reached exactly.
while awk -v lr="$CURRENT_LR" -v upper="$UPPER_LR" '
    BEGIN {
        exit !(lr <= upper)
    }
'; do
    RUN_INDEX=$((RUN_INDEX + 1))
    RUN_NUMBER="$(printf "%03d" "$RUN_INDEX")"

    # Each learning rate receives its own directory.
    RUN_DIR="$SWEEP_DIR/run_${RUN_NUMBER}_lr_${CURRENT_LR}"

    if ! mkdir "$RUN_DIR"; then
        echo "Error: cannot create run directory:" >&2
        echo "  $RUN_DIR" >&2
        exit 1
    fi

    PROGRAM_LOG="$RUN_DIR/program.log"

    echo
    echo "Run $RUN_INDEX"
    echo "Learning rate: $CURRENT_LR"
    echo "Run directory: $RUN_DIR"

    # Run from build/cldl so loop.png and copied resources can be
    # found through their existing relative paths.
    #
    # Both stdout and stderr are captured in the run-specific log.
    (
        cd "$BINARY_DIR" || exit 1

        "$BINARY" \
            0 \
            "$CURRENT_LR" \
            "$SEED" \
            "$LAYERS" \
            "$RUN_DIR"
    ) > "$PROGRAM_LOG" 2>&1

    EXIT_CODE=$?

    STEPS=""
    AVG_ERROR=""

    # Prefer the final summary printed by singleRun().
    FINISHED_LINE="$(
        grep -F "Finished: learning_rate=" "$PROGRAM_LOG" |
        tail -n 1 ||
        true
    )"

    if [[ -n "$FINISHED_LINE" ]]; then
        STEPS="$(
            printf "%s\n" "$FINISHED_LINE" |
            sed -nE 's/.*steps=([0-9]+).*/\1/p'
        )"

        AVG_ERROR="$(
            printf "%s\n" "$FINISHED_LINE" |
            sed -nE 's/.*avg_error=([^,[:space:]]+).*/\1/p'
        )"
    fi

    # Fallback to this run's own flog.tsv only.
    # Current flog.tsv format:
    # column 1 = error
    # column 2 = average error
LOGGED_STEPS=""
SUCCESS_REACHED=0

if [[ -s "$RUN_DIR/flog.tsv" ]]; then
    # Reproduce the success-counter logic used by Linefollower.cpp.
    #
    # Output fields:
    #   1. Number of valid log rows
    #   2. Final average error
    #   3. Whether the success threshold was reached
    read -r LOGGED_STEPS LOGGED_AVG_ERROR SUCCESS_REACHED < <(
        awk \
            -v threshold="$ERROR_THRESHOLD" \
            -v required="$SUCCESS_STEPS" '
            NF >= 2 {
                count++

                finalAverageError = $2

                absoluteError = $2 + 0
                if (absoluteError < 0) {
                    absoluteError = -absoluteError
                }

                if (absoluteError <= threshold) {
                    consecutiveSuccessSteps++
                } else {
                    consecutiveSuccessSteps = 0
                }

                # Matches:
                # successCtr > STEPS_BELOW_ERR_THRESHOLD
                if (consecutiveSuccessSteps > required) {
                    successReached = 1
                }
            }

            END {
                if (count > 0) {
                    print count, finalAverageError, successReached + 0
                }
            }
        ' "$RUN_DIR/flog.tsv"
    )

    if [[ -z "$STEPS" ]]; then
        STEPS="$LOGGED_STEPS"
    fi

    if [[ -z "$AVG_ERROR" ]]; then
        AVG_ERROR="$LOGGED_AVG_ERROR"
    fi

    # Temporary termination inference:
    #
    # - fewer than MAX_STEPS logged;
    # - success condition was not reached;
    #
    # therefore treat the run as an off-track termination and report
    # MAX_STEPS, matching the assignment in Linefollower.cpp.
    if [[ "$LOGGED_STEPS" =~ ^[0-9]+$ ]] &&
       (( LOGGED_STEPS < MAX_STEPS )) &&
       [[ "$SUCCESS_REACHED" -eq 0 ]]; then
        STEPS="$MAX_STEPS"
    fi
fi

    if [[ -z "$STEPS" ]]; then
        STEPS="NA"
    fi

    if [[ -z "$AVG_ERROR" ]]; then
        AVG_ERROR="NA"
    fi

    printf \
        "%s\t%s\t%s\t%s\t%s\n" \
        "$CURRENT_LR" \
        "$STEPS" \
        "$AVG_ERROR" \
        "$SEED" \
        "$LAYERS" \
        >> "$STATS_FILE"

    echo "Steps:         $STEPS"
    echo "Average error: $AVG_ERROR"

    if [[ "$EXIT_CODE" -ne 0 ]]; then
        echo "Warning: linefollowercldl exited with code $EXIT_CODE" >&2
        echo "Program log:" >&2
        echo "  $PROGRAM_LOG" >&2
    fi

    NEXT_LR="$(
        awk -v lr="$CURRENT_LR" -v multiplier="$MULTIPLIER" '
            BEGIN {
                printf "%.6e", lr * multiplier
            }
        '
    )"

    # Prevent an infinite loop caused by an invalid floating-point result.
    if ! awk -v current="$CURRENT_LR" -v next_lr="$NEXT_LR" '
        BEGIN {
            exit !(next_lr > current)
        }
    '; then
        echo "Error: the next learning rate did not increase." >&2
        exit 1
    fi

    CURRENT_LR="$NEXT_LR"
done

echo
echo "========================================"
echo "CLDL sweep completed."
echo "Results saved to:"
echo "  $STATS_FILE"
echo "Detailed runs saved under:"
echo "  $SWEEP_DIR"
echo "========================================"
