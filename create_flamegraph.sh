#!/bin/bash
set -ex

if [ -z "$1" ]; then
    echo "Usage: $0 <ip>"
    exit 1
fi

ssh root@$1 "perf record -F 99 -a -g -- sleep 60 > perf.data"
ssh root@$1 -t "perf script > out.perf"
scp root@$1:out.perf .
../FlameGraph/stackcollapse-perf.pl out.perf > out.folded
../FlameGraph/flamegraph.pl out.folded > "results/graphs/flamegraph-$(date +"%Y-%m-%d-%H-%M-%S").svg"
rm out.perf out.folded