# roachinfo scratchpad

This is a scratchpad used during the development of `roachinfo`.

## Metrics

### sizing

**Avaliable via SQL:**

+ number of nodes
+ Node Build Info
+ vCPUs per node
+ total data size
+ largest single table size
+ total number of tables
+ total number of changefeeds

**NOT available in SQL:**

+ memory per node
+ stores per node
+ data size per node
+ Cloud Provider

### peak values (hourly or ??)

+ Memory utilization
  + per node
+ CPU utilization % (usr+sys)
  + per node
+ queries/sec
  + select
  + insert
  + update
  + delete
+ Disk utilization (reads and writes)
  + MB/sec
  + IOPS
  + InProgress

## Gathering Statistics

### via SQL

```sql
-- Find ClusterId
SELECT value FROM crdb_internal.node_build_info WHERE field = 'ClusterID';

SELECT * FROM crdb_internal.node_build_info;  --ALL build info

  node_id |    field     |                                       value
----------+--------------+-------------------------------------------------------------------------------------
        1 | Name         | CockroachDB
        1 | ClusterID    | 34454c6c-0d95-4625-b8b5-1816bde0e223
        1 | Organization | Cockroach Labs - Production Testing
        1 | Build        | CockroachDB CCL v22.1.0 (x86_64-pc-linux-gnu, built 2022/05/23 16:27:47, go1.17.6)
        1 | Version      | v22.1.0
        1 | Channel      | official-binary


SELECT value 
FROM crdb_internal.node_build_info
WHERE field = 'ClusterID';

SELECT value 
FROM crdb_internal.node_build_info
WHERE field = 'Version';

SELECT value 
FROM crdb_internal.node_build_info
WHERE field = 'Organization';

SELECT value 
FROM crdb_internal.node_build_info
WHERE field = 'Build';

-- Number of Nodes
select distinct "nodeID" from system.lease;

-- vCPUs
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


-- #nodes
SELECT value FROM crdb_internal.node_metrics WHERE name = 'liveness.livenodes';

-- Sizing
FROM crdb_internal.tables
FROM crdb_internal.ranges
FROM crdb_internal.ranges_no_leases


-- Changefeeds
select job_id, job_type, status, running_status 
from crdb_internal.jobs 
where job_type='CHANGEFEED' and status='running';

        job_id       |  job_type  | status  |              running_status
---------------------+------------+---------+-------------------------------------------
  746911665568481520 | CHANGEFEED | running | running: resolved=1661446223.092962262,0
  746912283570733278 | CHANGEFEED | running | running: resolved=1661446321.525616983,0
  746912924857860327 | CHANGEFEED | running | running: resolved=1661446437.596805033,0
  746915275863916789 | CHANGEFEED | running | running: resolved=1661446538.998757803,0
  746915659053859070 | CHANGEFEED | running | running: resolved=1661446583.331163434,0
  746917882372620524 | CHANGEFEED | running | running: resolved=1661446392.405302615,0
  746927026252153083 | CHANGEFEED | running | running: resolved=1661446510.234668114,0
  786816756784988394 | CHANGEFEED | running | running: resolved=1661446424.624630005,0
  786816757405450481 | CHANGEFEED | running | running: resolved=1661446490.938112546,0
  786816757977317611 | CHANGEFEED | running | running: resolved=1661446424.624630005,0

-- Changefeed count
select count(*) 
from crdb_internal.jobs 
where job_type='CHANGEFEED' and status='running';

  count
---------
     10


-- Ranges
select lease_holder, count(*) 
from crdb_internal.ranges 
group by 1;

  lease_holder | count
---------------+--------
             1 |   427
             2 |   413
             3 |   428

-- Total Number of Tables
-- select name from crdb_internal.tables where database_name not in ('system','postgres');
select count(*) from crdb_internal.tables where database_name not in ('system','postgres');

-- Total Sizes
  select sum(range_size)/1024^3 from crdb_internal.ranges;
        ?column?
-------------------------
  193.16608634311705828

-- Table Sizes
select table_id, table_name, sum(range_size)/1024^3 as sizeGB
from crdb_internal.ranges
group by 1,2
having sum(range_size) > 1024*1024*1024
order by 3 desc
limit 5;

-- Top Table Size only
with tt as (
select table_id, table_name, ROUND(sum(range_size)/1024^3) as sizeGB
from crdb_internal.ranges
group by 1,2
having sum(range_size) > 1024*1024*1024
order by 3 desc
limit 1)
select sizeGB from tt;


  table_id | table_name |        sizegb
-----------+------------+------------------------
        66 | stock      | 78.142741632647812366
        59 | order_line | 51.308185704052448273
        65 | customer   | 44.964672948233783245

-- Node Status Query
root@192.168.0.100:26257/system> select node_id, platform, locality from crdb_internal.kv_node_status;
  node_id |  platform   | locality
----------+-------------+-----------
        1 | linux amd64 |
        2 | linux amd64 |
        3 | linux amd64 |
(3 rows)

-- Node Status
root@192.168.0.100:26257/system> select node_id, platform, locality, env, args from crdb_internal.kv_node_status where node_id=1;
  node_id |  platform   | locality |                                      env                                      |                                                                                                args
----------+-------------+----------+-------------------------------------------------------------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
        1 | linux amd64 |          | ["COCKROACH_BACKGROUND_RESTART=1", "LANG=en_US.UTF-8", "TERM=xterm-256color"] | ["cockroach", "start", "--insecure", "--store=node1", "--listen-addr=192.168.0.100:26257", "--http-addr=192.168.0.100:8080", "--join=192.168.0.100:26257,192.168.0.100:26258,192.168.0.100:26259"]
(1 row)

-- KV stores
root@localhost:26257/defaultdb> select node_id, store_id, used*100/available as pct_used from crdb_internal.kv_store_status;
  node_id | store_id |       pct_used
----------+----------+------------------------
        1 |        1 | 38.870683002377541166
        2 |        2 | 57.053083203901461603
        3 |        3 | 43.450994814730748265
        4 |        4 | 41.955373600026577731
        5 |        5 | 46.855536314159159778
        6 |        6 | 27.740834916423527743
        7 |        7 | 31.826505617555350828
        8 |        8 | 19.880878818070876707
        9 |        9 | 49.873103110696671109

root@192.168.0.100:26257/system> select node_id, count(store_id) from crdb_internal.kv_store_status group by 1;
  node_id | count
----------+--------
        1 |     1
        2 |     1
        3 |     1

root@localhost:26257/defaultdb> select node_id, metrics->>'sys.rss' from crdb_internal.kv_node_status;
  node_id |    ?column?
----------+------------------
        1 | 16091426816
        2 | 17288142848
        3 | 16019206144
        4 | 1.602230272E+10
        5 | 1.579853824E+10
        6 | 16609816576
        7 | 15252717568
        8 | 16190222336
        9 | 1.568548864E+10

```

### Gather from TSDUMP

#### TS metrics

```bash
cockroach debug tsdump  --host 192.168.0.100 --format csv --insecure --from '2022-08-23 00:00:00' |grep cr.node.sys.cpu.combined.percent-normalized

...
cr.node.sys.cpu.combined.percent-normalized,2022-08-24T22:01:20Z,3,0.005698873279183296
cr.node.sys.cpu.combined.percent-normalized,2022-08-24T22:01:30Z,3,0.006101161669723541
cr.node.sys.cpu.combined.percent-normalized,2022-08-24T22:01:40Z,3,0.005948724405507768
cr.node.sys.cpu.combined.percent-normalized,2022-08-24T22:01:50Z,3,0.006931348375047988
...

cockroach debug tsdump  --host 192.168.0.100 --format csv --insecure --from '2022-08-23 00:00:00' | 
awk -F ',' 'BEGIN {cpumax=0.0} /^cr.node.sys.cpu.combined.percent-normalized/ {if ($4 > cpumax) cpumax=$4;} END {print $cpumax}'
cockroach debug tsdump  --host 192.168.0.100 --format csv --insecure --from '2022-08-23 00:00:00' | 
awk -F "," 'BEGIN {cpumax=0.0} /^cr.node.sys.cpu.combined.percent-normalized/ {if ($4 > cpumax) cpumax=$4;} END {print cpumax}'

cockroach debug tsdump  --host 192.168.0.100 --format csv --insecure --from '2022-08-24 00:00:00' --to '2022-08-24 01:00:00' > tsdump_1hr.csv


## Metrics

# instant
cr.node.sys.cpu.combined.percent-normalized
cr.node.sys.rss

cr.node.sys.host.disk.iopsinprogress

## rate
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

## Grep

cat << EOF > list_of_metrics
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
sql.delete.count,
sql.select.count,
sql.insert.count,
sql.update.count,
EOF

grep -wFf list_of_metrics tsdump_1hr.csv > tsdump_1hr_filtered.csv

TZ=PST awk -F, '{ OFS = FS;
                  command="date -d" $2 " +%s";
                  command | getline $2;
                  close(command);
                  print}'

# Convert to EPOCH for math
glenn@ubuntu-fawcett:~$ TZ=PST awk -F, '{ OFS = FS;
>                   command="date -d" $2 " +%s";
>                   command | getline $2;
>                   close(command);
>                   print}' ts_rate_testdata.csv
cr.node.sql.delete.count.internal,1661300080,1,89766
cr.node.sql.delete.count.internal,1661300090,1,89766
cr.node.sql.delete.count.internal,1661300100,1,89766
cr.node.sql.delete.count.internal,1661300110,1,89766
cr.node.sql.delete.count.internal,1661300120,1,89766

   counter[$NF]=$2

awk -F, '{
  # print NR
   if (NR == 1) counter[NR]=0 
   else 
    # print $4
    counter[NR]=$4
}
END {
  for (i = 1; i <= NR; i++)
    # printf("%d\n", i)
    if (i != 1 && i != 2) printf("%d :: %d   \n", i, (counter[i]-counter[i-1]))
}' ts_rate_testdata_epoch.csv

awk -F, '{
   if (NR == 2) counter[$3,1]=$4
   counter[$3,NR]=$4
}
END {
  for (n = 1; n <= 3; n++)
    for (i = 1; i <= NR; i=i+1)
      # printf("%d\n", i)
      if (i == 1 ) 
        printf("%d :: %d :: %d   \n", i, n, 0)
      else
        printf("%d :: %d :: %d   \n", i, n, (counter[n,i]-counter[n,i-1]))
}' tsdump_sample_filtered_epoch.csv

ts_rate_testdata_epoch.csv

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
}' tsdump_sample_filtered_epoch.csv

ts_rate_testdata_epoch.csv

cr.node.sys.cpu.combined.percent-normalized
cr.node.sys.rss
cr.node.sys.host.disk.iopsinprogress



```


```sql

CREATE TABLE cluster_usage (
  sample_date TIMESTAMPTZ NOT NULL,
  cluster_id UUID NOT NULL,
  organization TEXT,
  version TEXT,
  build TEXT,
  node_count INT,
  vcpu_count INT,
  disk_gb INT,
  largest_table_gb INT,
  changefeeds INT,
  cpu_pct INT,
  mem_pct INT,
  qps INT,
  PRIMARY KEY (sample_date, cluster_id)
);

```

cockroach debug zip ./debug.zip  --redact-logs --files-from='2021-07-01 15:00'
https://www.cockroachlabs.com/docs/v22.1/cockroach-debug-zip

cockroach debug zip ./cockroach-data/logs/debug.zip --redact-logs


cockroach debug tsdump --host localhost --format csv --insecure --from '2022-10-12 00:00' --to '2022-10-13 00:00' |gzip > tsdump.csv.gz

--files-from='2021-07-01 15:00'
