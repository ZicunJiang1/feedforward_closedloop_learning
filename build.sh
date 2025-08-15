#!/bin/sh
rm -rf CMakeCache.txt CMakeFiles build dist
cmake -B build
cmake --build build --parallel=4
cd build
make
cd ..
bash ./cp-resources.sh
