#!/bin/bash

export port=26258
export host=localhost
# export host=192.168.0.100
export t1=`date +%Y-%m-%d -d "-2 days"` ## yesterday sample
export t2=`date +%Y-%m-%d`              ## stop before today at midnight "today"

# export crdbsql="./cockroach sql --host ${host} --set "show_times=false" --format table --certs-dir ./certs"
export crdbsql="cockroach sql --host ${host} --set "show_times=false" --format table --format table --insecure"
export crdbtsdump="cockroach debug tsdump --host ${host} --format csv --insecure --from ${t1} --to ${t2}"
export tempsql=$(mktemp /tmp/tempsql.XXXXXX)

## Begin Reporting
echo "Gathinging Cluster Information at "`date`"...."
echo ""

## List Cluster Information
exec ${crdbsql}  --format table -e "SELECT field, value FROM crdb_internal.node_build_info" | sed \$d
echo ""

## Cluster Instance Type and Locality
exec ${crdbsql}  --format table -e "SELECT node_id, platform, locality FROM crdb_internal.kv_node_status" | sed \$d
echo ""

## Number of Nodes
cat << EOF > ${tempsql}
    SELECT value 
    FROM crdb_internal.node_metrics 
    WHERE name = 'liveness.livenodes';
EOF
export nodeCount=`exec ${crdbsql} -f ${tempsql} | sed "\$d" | tail -2 | head -1`

## Total vCPUs
cat << EOF > ${tempsql}
SELECT 
((SELECT value FROM crdb_internal.node_metrics WHERE name = 'sys.cpu.user.percent')
+
(SELECT value FROM crdb_internal.node_metrics WHERE name = 'sys.cpu.sys.percent'))
*
(SELECT value FROM crdb_internal.node_metrics WHERE name = 'liveness.livenodes')
/
(SELECT value FROM crdb_internal.node_metrics WHERE name = 'sys.cpu.combined.percent-normalized')
AS cluster_vcpus
;
EOF
export vCPUcount=`exec ${crdbsql} -f ${tempsql} | sed "\$d" | tail -2 | head -1`

## Changefeed count
cat << EOF > ${tempsql}
SELECT COUNT(*) 
FROM crdb_internal.jobs 
WHERE job_type='CHANGEFEED' and status='running';
EOF
export changefeedCnt=`exec ${crdbsql} -f ${tempsql} | sed "\$d" | tail -2 | head -1`

## Total Space Usage
cat << EOF > ${tempsql}
SELECT ROUND(sum(used)/(1024^3)) as used 
FROM crdb_internal.kv_store_status;
EOF
export spaceTotalGB=`exec ${crdbsql} -f ${tempsql} | sed "\$d" | tail -2 | head -1`


echo "Top table in Cluster..."
## Top Table 
cat << EOF > ${tempsql}
with tt as (
select table_id, table_name, ROUND(sum(range_size)/1024^3) as sizeGB
from crdb_internal.ranges
group by 1,2
having sum(range_size) > 1024*1024*1024
order by 3 desc
limit 1)
select sizeGB from tt;
EOF
export TTsize=`exec ${crdbsql} -f ${tempsql} | sed "\$d" | tail -2 | head -1`


echo ""
echo "      Total Nodes : "${nodeCount}
echo "       vCPU total : "${vCPUcount}
echo "  Total Disk (GB) : "${spaceTotalGB}
echo "Largest Table(GB) : "${TTsize}
echo "      Changefeeds : "${changefeedCnt}
echo ""

# ## Storage Space per Node
# cat << EOF > ${tempsql}
# SELECT node_id, store_id, ROUND(used*100/available) AS pct_used 
# FROM crdb_internal.kv_store_status;
# EOF
# echo "Space used per Node...."
# exec ${crdbsql} -f ${tempsql} | sed "\$d"
# echo ""

### Define Needed Metrics and Collect
cat << EOF > needed_metrics
cr.node.sys.cpu.combined.percent-normalized
cr.node.sys.rss
cr.node.sys.host.disk.iopsinprogress
cr.node.sys.host.disk.io.time
cr.node.sys.host.disk.weightedio.time
cr.node.sys.host.disk.read.bytes
cr.node.sys.host.disk.read.count
cr.node.sys.host.disk.read.time
cr.node.sys.host.disk.write.bytes
cr.node.sys.host.disk.write.count
cr.node.sys.host.disk.write.time
sql.delete.count
sql.select.count
sql.insert.count
sql.update.count
EOF

cat << EOF > instant_metrics
cr.node.sys.cpu.combined.percent-normalized
cr.node.sys.rss
cr.node.sys.host.disk.iopsinprogress
EOF

## Collect tsdump and filter out unneeded
echo "Collecting Needed Metrics...."
echo "  ${crdbtsdump}"
echo "  ......."

exec ${crdbtsdump} |
grep -wFf needed_metrics |
grep -v internal > tsdump_metrics_filtered.csv

## Calculate some values for CPU, RSS, IO response time
##
for m in `cat instant_metrics`
do
    # echo ${m}
    grep ${m} tsdump_metrics_filtered.csv |
    awk -F, 'BEGIN {
        max=0.0
        node=1
        ts=""
        sum=0.0
        sumsq=0.0
    }
    {
        sum += $4*1.0
        sumsq += ($4*1.0)^2
        s90[NR-1] = $4*1.0

        if ($4*1.0 > max) {
            max = $4*1.0
            node = $3
            ts = $2
        }
    }
    END {
        printf("%s\n", $1 )
        printf("\t  avg: %8.2f \n\t  std: %8.2f \n",sum/NR, sqrt((sumsq-sum^2/NR)/NR), max )
        printf("\t 90th: %8.2f \n\t  max: %8.2f \n", s90[int(NR*0.90)], max )
        # printf("\t\t max_node: %d, \t max_ts: %s\n", node, ts )
        # print s90[int(NR*0.90)]
    }' 
done

exit



cat tsdump_metrics_filtered.csv |
TZ=PST awk -F, '{ OFS = FS;
                  command="date -d" $2 " +%s";
                  command | getline $2;
                  close(command);
                  print}' > tsdump_metrics_filtered_epoch.csv

for m in `cat rate_metrics`
do
    grep ${m} tsdump_sample_filtered_epoch.csv |
    awk -F, '{
    if (NR == 2) counter[1]=$4
    counter[NR]=$4
    }
    END {
    for (i = 1; i <= NR; i++)
        if (i == 1 ) 
            printf("%d :: %s :: %d  \n", i, $1, 0)
        else
            printf("%d :: %s :: %d  \n", i, $1, (counter[i]-counter[i-1]))
    }' 
done

exit


#curl ${localhost}:${port}/_status/nodes | grep '"nodeId":' |awk -F ': ' '{print $2}'|sed "s/,//g" |uniq > n.txt
#token=$(cockroach auth-session login root --format=records 2>&1 | grep "authentication cookie" | sed 's/authentication cookie |//')

#for n in `cat n.txt`
#do
#   curl -s --output - -k --cookie \"$token\" ${localhost}:${port}/_status/diagnostics/${n}  > cluster_diag_sample_node_${n}.json
#done