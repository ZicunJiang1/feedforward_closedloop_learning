#!/usr/bin/env python3
"""Plot steps to threshold against learning rate for all discovered seeds.

Data are read from stat*.tsv or stat*.dat files inside sweep* directories
located beside this script. Steps above 200,000 are reported at the cap.
"""

import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import StrMethodFormatter


def read_data():
    """Read learning rates and every seed's steps in discovery order."""
    data_dir = Path(__file__).resolve().parent
    stats_files = sorted(
        list(data_dir.glob("sweep*/stat*.tsv"))
        + list(data_dir.glob("sweep*/stat*.dat"))
    )
    if not stats_files:
        raise FileNotFoundError(
            "No sweep*/stat*.tsv or sweep*/stat*.dat files were found"
        )
    data = {}

    for stats_path in stats_files:
        with stats_path.open("r", encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle, delimiter="\t"):
                seed = int(row["seed"])
                learning_rate = float(row["learningrate"])
                data.setdefault(seed, {})[learning_rate] = min(
                    int(row["steps"]), 200000
                )

    if not data:
        raise ValueError("No seed data were found")

    learning_rates = sorted({rate for values in data.values() for rate in values})
    steps_by_seed = [
        [values.get(rate, float("nan")) for rate in learning_rates]
        for values in data.values()
    ]
    return learning_rates, steps_by_seed


def plot_steps(learning_rates, steps_by_seed, output_path="steps_to_threshold.png"):
    """Create one minimalist step-to-threshold scatter plot."""
    if any(len(steps) != len(learning_rates) for steps in steps_by_seed):
        raise ValueError("Each seed must match the learning-rate list length")

    fig, ax = plt.subplots(figsize=(6.4, 4.4))

    point_style = {
        "marker": "o",
        "s": 22,
        "facecolors": "black",
        "edgecolors": "black",
        "linewidths": 0.4,
    }
    for steps in steps_by_seed:
        ax.scatter(learning_rates, steps, **point_style)

    ax.set_xscale("log")
    ax.set_xlim(7.5e-6, 1.25e-1)
    ax.set_ylim(0, 205000)
    ax.set_yticks((0, 50000, 100000, 150000, 200000))
    ax.set_xlabel("Learning rate")
    ax.set_ylabel("Steps to threshold")
    ax.yaxis.set_major_formatter(StrMethodFormatter("{x:,.0f}"))

    ax.grid(False)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    fig.tight_layout()
    fig.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    learning_rates, steps_by_seed = read_data()
    plot_steps(learning_rates, steps_by_seed)
