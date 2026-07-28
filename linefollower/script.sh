#!/usr/bin/env bash

# Continue the sweep even if one run exits abnormally.
set -u

export LC_NUMERIC=C

MULTIPLIER="1.25"

usage()
{
    echo "Usage:"
    echo "  $0 <start_lr> <upper_lr> <seed> <layers> [output_directory]"
    echo
    echo "Example:"
    echo "  $0 0.0001 0.001 42 9,6,6"
    echo "  $0 0.0001 0.001 42 3,3,6 results/test"
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

# This script is stored in the same directory as Linefollower.cpp.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repository root is the parent directory of linefollower/.
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Compiled executable.
BINARY="$REPO_ROOT/build/linefollower/linefollower"
BINARY_DIR="$(dirname "$BINARY")"

# By default, save results in the directory containing this script.
OUTPUT_DIR="${5:-$SCRIPT_DIR}"

# Check the executable.
if [[ ! -x "$BINARY" ]]; then
    echo "Error: executable not found:" >&2
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

# Create and resolve output directory.
mkdir -p "$OUTPUT_DIR"

OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

# Timestamp includes nanoseconds to avoid collisions between rapid executions.
TIMESTAMP="$(date '+%Y%m%d_%H%M%S_%N')"
STATS_FILE="$OUTPUT_DIR/stats_${TIMESTAMP}.tsv"

# Each script execution replaces the previous stats.tsv.
printf \
    "learningrate\tsteps\tavg_error\tseed\tlayers\n" \
    > "$STATS_FILE"

CURRENT_LR="$START_LR"
RUN_INDEX=0

echo "========================================"
echo "FCL learning-rate sweep"
echo "Start learning rate : $START_LR"
echo "Upper limit         : $UPPER_LR"
echo "Multiplier          : $MULTIPLIER"
echo "Seed                : $SEED"
echo "Layers              : $LAYERS"
echo "Output              : $STATS_FILE"
echo "========================================"

# Run the starting learning rate and then repeatedly multiply by 1.25.
# The upper limit is not added separately when it is not reached exactly.
while awk -v lr="$CURRENT_LR" -v upper="$UPPER_LR" '
    BEGIN {
        exit !(lr <= upper)
    }
'; do
    RUN_INDEX=$((RUN_INDEX + 1))

    echo
    echo "Run $RUN_INDEX"
    echo "Learning rate: $CURRENT_LR"

    # Remove detailed files from the previous run.
    # This prevents stale data being read if the next run fails early.
    rm -f \
        "$OUTPUT_DIR/flog.tsv" \
        "$OUTPUT_DIR/coord.tsv" \
        "$OUTPUT_DIR/turnslog.tsv" \
        "$OUTPUT_DIR"/layer*.dat

    TEMP_LOG="$(mktemp)"

    # Run from build/linefollower so that loop.png and other copied
    # resources can still be found through their relative paths.
    (
        cd "$BINARY_DIR" || exit 1

        "$BINARY" \
            0 \
            "$CURRENT_LR" \
            "$SEED" \
            "$LAYERS" \
            "$OUTPUT_DIR"
    ) > /dev/null 2> "$TEMP_LOG"

    EXIT_CODE=$?

    STEPS=""
    AVG_ERROR=""

    # Prefer the final summary printed by singleRun(), for example:
    #
    # Finished: learning_rate=0.0001, seed=42,
    # steps=5000, avg_error=0.0008
    FINISHED_LINE="$(
        grep -F "Finished: learning_rate=" "$TEMP_LOG" |
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
            sed -nE 's/.*avg_error=([^[:space:]]+).*/\1/p'
        )"
    fi

    # Fallback when singleRun() does not print the expected summary.
    # Current flog.tsv format:
    # column 1 = error
    # column 2 = average error
    if [[ -z "$STEPS" && -s "$OUTPUT_DIR/flog.tsv" ]]; then
        STEPS="$(
            awk 'END { print NR }' "$OUTPUT_DIR/flog.tsv"
        )"

        AVG_ERROR="$(
            awk '
                NF {
                    finalAverageError = $2
                }

                END {
                    if (NR > 0) {
                        print finalAverageError
                    }
                }
            ' "$OUTPUT_DIR/flog.tsv"
        )"
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

    echo "Steps:       $STEPS"
    echo "Average error: $AVG_ERROR"

    if [[ "$EXIT_CODE" -ne 0 ]]; then
        echo "Warning: linefollower exited with code $EXIT_CODE" >&2
        echo "See temporary log output below:" >&2
        cat "$TEMP_LOG" >&2
    fi

    rm -f "$TEMP_LOG"

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
echo "Sweep completed."
echo "Results saved to:"
echo "  $STATS_FILE"
echo "========================================"