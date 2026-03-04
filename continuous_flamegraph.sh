#!/bin/bash
set -ex

for run in $(seq 1 20); do
    ./create_flamegraph.sh $1 "results/graphs/flamegraph_$run.svg"
done