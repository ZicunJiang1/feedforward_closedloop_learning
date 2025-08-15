# FCL Linefollower

The line follower demonstrates as a simple scenario how
FCL works. The robot has a default steering mechanism
to track the line and this generates the error signal for FCL.

FCL then learns with the help of this error signal to
improve its behaviour. The inputs to FCL are two rows
of sensors in front of the robot.

## Pre-requisites

  - Ubuntu Linux LTS

  - QT5 development libraries with openGL and GLU

  - ENKI (just install the packages: `libenki-dev` and `libenki2`)

  - iir filter library: https://github.com/berndporr/iir1
  Install with `cmake .` -- `make` -- `sudo make install`

## Compilation

`cmake .` and `make` to compile it.

## Running the line follower

Copy the image file of the racetrack and the scripts for plotting
into the directory containing the `linefollower` binary.

The line follower has two modes: single run or stats run.
* In the single run mode it runs until the squared average of the
error signal is below a certain threshold (`SQ_ERROR_THRES`). The
single run mode can be executed using `./linefollower 0`

* In the stats run it performs a logarithmic sweep of different
learning rates and counts the simulation steps till success. The
stats run mode can be executed using `./linefollower 1`

## Data logging

There is one log file: `flog.tsv`. The data is space separated and every time
step has one row.

### flog.tsv

This log records the steering actions and the following data.

`unamplified_error average_error absolute_error steering_left steering_right layer_1_weight_dist layer_2_weight_dist … layer_N_weight_dist`

The error signal can be seen as the performance measure
of learning and it slowly decays to zero which is logged here:

The script `plot_abs_error.py` plots the error signal while
the line follower is running.

### turnslog.tsv

This file records the steps at which the robot was turned around manually.
If the robot was turned around at a specific step, the corresponding record
has a value of 1.

### Weights

Run the script `plotweights.py` which plots the weights while
the line follower is running.
