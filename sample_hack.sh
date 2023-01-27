#!/bin/bash

export port=26258
export localhost=127.0.0.1

curl ${localhost}:${port}/_status/nodes | grep '"nodeId":' |awk -F ': ' '{print $2}'|sed "s/,//g" |uniq > n.txt

token=$(cockroach auth-session login root --format=records 2>&1 | grep "authentication cookie" | sed 's/authentication cookie |//')

for n in `cat n.txt`
do
   curl -s --output - -k --cookie \"$token\" ${localhost}:${port}/_status/diagnostics/${n}  > cluster_diag_sample_node_${n}.json
   #curl -s --output - -k --cookie \"$token\"
done


