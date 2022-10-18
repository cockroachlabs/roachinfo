#!/bin/bash

export port=26258
export host=localhost
export sample_date=`date '+%Y%m%d'|sed 's/^ //g'`

# export crdbsql="./cockroach sql --host ${host} --set "show_times=false" --format table --certs-dir ./certs"
export crdbsql="cockroach sql --host ${host} --set "show_times=false" --format table --format table --insecure"
export crdbtsdump="cockroach debug tsdump --host ${host} --format csv --insecure --from ${t1} --to ${t2}"
export tempsql=$(mktemp /tmp/tempsql.XXXXXX)

# function to get one return value from SQL
getval () {
    sed "\$d" | tail -1 | sed 's/^[ \t]*//'
}

## Begin Reporting
echo "Gathinging Cluster Information on "`date`"...."
echo ""

# ## List Cluster Information
# exec ${crdbsql} -e "SELECT field, value FROM crdb_internal.node_build_info" | sed \$d
# echo ""

# ## Cluster Instance Type and Locality
# exec ${crdbsql}  -e "SELECT node_id, platform, locality FROM crdb_internal.kv_node_status" | sed \$d
# echo ""

## ClusterId
export cid=`exec ${crdbsql} -e "SELECT value FROM crdb_internal.node_build_info WHERE field = 'ClusterID'" | getval`

## Version
export ver=`exec ${crdbsql} -e "SELECT value FROM crdb_internal.node_build_info WHERE field = 'Version'" | getval`
## Organizaion
export org=`exec ${crdbsql} -e "SELECT value FROM crdb_internal.node_build_info WHERE field = 'Organization'" | getval`
## Organizaion
export build=`exec ${crdbsql} -e "SELECT value FROM crdb_internal.node_build_info WHERE field = 'Build'" | getval`
## Number of Nodes
cat << EOF > ${tempsql}
    SELECT value 
    FROM crdb_internal.node_metrics 
    WHERE name = 'liveness.livenodes';
EOF
export nodeCount=`exec ${crdbsql} -f ${tempsql} | getval`

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
export vCPUcount=`exec ${crdbsql} -f ${tempsql} | getval`

## Changefeed count
cat << EOF > ${tempsql}
SELECT COUNT(*) 
FROM crdb_internal.jobs 
WHERE job_type='CHANGEFEED' and status='running';
EOF
export changefeedCnt=`exec ${crdbsql} -f ${tempsql} | getval`

## Total Space Usage
cat << EOF > ${tempsql}
SELECT ROUND(sum(used)/(1024^3)) as used 
FROM crdb_internal.kv_store_status;
EOF
export spaceTotalGB=`exec ${crdbsql} -f ${tempsql} | getval`


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
export TTsize=`exec ${crdbsql} -f ${tempsql} | getval`

echo "Please enter some observations from the DB console..."
echo ""
read -p "CPU% peak observation : " cpuPct
read -p "Memory% peak observation : " memPct
read -p "QPS peak observation : " qps

echo ""
echo "Summary of Cluster Statistics via SQL..."
echo ""
echo "              Sample Date : "${sample_date}
echo "                ClusterID : "${cid}
echo "             Organization : "${org}
echo "                  Version : "${ver}
echo "                    Build : "${build}
echo "              Total Nodes : "${nodeCount}
echo "               vCPU total : "${vCPUcount}
echo "          Total Disk (GB) : "${spaceTotalGB}
echo "        Largest Table(GB) : "${TTsize}
echo "              Changefeeds : "${changefeedCnt}
echo "    CPU% peak observation : "${cpuPct}
echo " Memory% peak observation : "${memPct}
echo "     QPS peak observation : "${qps}
echo ""

export outfile=${sample_date}_${cid}.tsv
echo "... Send Sample File to Cockroach Enterprise Architect : "${outfile}
echo -e "date\tClusterId\tOrganization\tVersion\tBuild\tNodes\tvCPU\tDiskGB\tTableGB\tChangfeeds\tcpuPCT\tmemPct\tqps" > ${outfile}
echo -e ${sample_date}"\t"${cid}"\t"${org}"\t"${ver}"\t"${build}"\t"${nodeCount}"\t"${vCPUcount}"\t"${spaceTotalGB}"\t"${TTsize}"\t"${changefeedCnt}"\t"${cpuPct}"\t"${memPct}"\t"$qps >> ${outfile}