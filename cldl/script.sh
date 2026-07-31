#!/usr/bin/env bash

set -u

# Seed and network structure can be supplied as command-line arguments.
#
# Usage:
#   ./launch_cldl_parallel.sh [seed] [layers]
#
# Example:
#   ./launch_cldl_parallel.sh 42 9,6,6

SEED="${1:-42}"
LAYERS="${2:-9,6,6}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWEEP_SCRIPT="$SCRIPT_DIR/cldls.sh"

if [[ ! -x "$SWEEP_SCRIPT" ]]; then
    echo "Error: CLDL sweep script is not executable:" >&2
    echo "  $SWEEP_SCRIPT" >&2
    echo "Run: chmod +x \"$SWEEP_SCRIPT\"" >&2
    exit 1
fi

if ! command -v gnome-terminal >/dev/null 2>&1; then
    echo "Error: gnome-terminal was not found." >&2
    exit 1
fi

if ! [[ "$SEED" =~ ^-?[0-9]+$ ]]; then
    echo "Error: seed must be an integer." >&2
    exit 1
fi

if [[ ! "$LAYERS" =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]]; then
    echo "Error: invalid layer vector: $LAYERS" >&2
    exit 1
fi

START_RATES=(
    "1.000000e-05"
    "2.441406e-05"
    "5.960464e-05"
    "1.455191e-04"
    "3.552713e-04"
    "8.673615e-04"
    "2.117582e-03"
    "5.169876e-03"
    "1.262176e-02"
    "3.851856e-02"
)

UPPER_RATES=(
    "1.953125e-05"
    "4.768371e-05"
    "1.164153e-04"
    "2.842170e-04"
    "6.938892e-04"
    "1.694066e-03"
    "4.135901e-03"
    "1.009741e-02"
    "3.081485e-02"
    "9.403945e-02"
)

TERMINAL_COUNT="${#START_RATES[@]}"

for ((i = 0; i < TERMINAL_COUNT; i++)); do
    TERMINAL_NUMBER=$((i + 1))
    START_LR="${START_RATES[$i]}"
    UPPER_LR="${UPPER_RATES[$i]}"

    TITLE="CLDL sweep ${TERMINAL_NUMBER}"

    # printf %q safely quotes arguments for the new Bash process.
    COMMAND="$(
        printf \
            'cd %q && %q %q %q %q %q; echo; echo "Terminal %d finished."; exec bash' \
            "$SCRIPT_DIR" \
            "$SWEEP_SCRIPT" \
            "$START_LR" \
            "$UPPER_LR" \
            "$SEED" \
            "$LAYERS" \
            "$TERMINAL_NUMBER"
    )"

    echo "Terminal $TERMINAL_NUMBER:"
    echo "  $START_LR -> $UPPER_LR"

    gnome-terminal \
        --window \
        --title="$TITLE" \
        -- bash -lc "$COMMAND"

    # Avoid opening all GUI processes at exactly the same instant.
    sleep 0.5
done

echo
echo "All terminal windows have been launched."
