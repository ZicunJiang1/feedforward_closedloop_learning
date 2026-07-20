#!/usr/bin/env sh

cp linefollower/loop.png build/linefollower
cp linefollower/plotweights.py build/linefollower
cp linefollower/plot_abs_error.py build/linefollower
cp linefollower/plot_weight_distance.plt build/linefollower

# for CLDL version of LineFollower.
cp linefollower/loop.png build/cldl
cp linefollower/plotweights.py build/cldl
cp linefollower/plot_abs_error.py build/cldl
cp linefollower/plot_weight_distance.plt build/cldl
