#!/bin/bash


function emptyfiles_create()
{
   mkdir -p $PG/emptyfiles;
   for i in $(seq 1 $smallfilecount); do
       : > $PG/emptyfiles/file.$i;
   done
}


function emptyfiles_delete()
{
    rm -rf $PG/emptyfiles;
}


function emptydirs_create()
{
    mkdir -p $PG/emptydirs;

    eval "echo $PG/emptydirs/top.{1..$emptytops}" | xargs mkdir -p;
    for top in $(seq 1 $emptytops); do
        eval "echo $PG/emptydirs/top.$top/dir.{1..$emptydirs}" | xargs mkdir -p;
    done
}


function emptydirs_delete()
{
    rm -rf $PG/emptydirs;
}


function smallfiles_create()
{
    mkdir -p $PG/smallfiles;
    for i in $(seq 1 $smallfilecount); do
	echo -n $smallblob >$PG/smallfiles/file.$i
    done
}


function smallfiles_rewrite()
{
    smallfiles_create "$@";
}


function smallfiles_read()
{
    for i in $(seq 1 $smallfilecount); do
	cat $PG/smallfiles/file.$i > /dev/null
    done
}


function smallfiles_reread()
{
    smallfiles_read "$@";
}


function smallfiles_delete()
{
    rm -rf $PG/smallfiles;
}


function largefile_create()
{
    mkdir -p $PG/largefile;
    dd if=/dev/zero of=$PG/largefile/large_file bs=$largeblock count=$largecount 2>/dev/null;
}


function largefile_rewrite()
{
    largefile_create "$@";
}


function largefile_read()
{
    dd if=$PG/largefile/large_file of=/dev/null bs=$largeblock count=$largecount 2>/dev/null;
}


function largefile_reread()
{
     largefile_read "$@";
}


function largefile_delete()
{
    rm -rf $PG/largefile
}


function crawl_create_recurse()
{
    local subpath;
    local depth;

    subpath="$1";
    depth="$2";

    if [ $depth -eq 0 ]; then
	for i in $(seq 1 $leafcount); do
	    : > $subpath/file.$i;
	done
	return
    fi

    depth=$(($depth - 1));

    eval "echo  $subpath/dir.{1..$crawlwidth}" | xargs mkdir -p;

    for i in $(seq 1 $crawlwidth); do
	crawl_create_recurse "$subpath/dir.$i" $depth;
    done
}


function directory_crawl_create ()
{
    crawl_create_recurse "$PG/crawl" $crawldepth;
}


function directory_crawl()
{
    ls -lR "$PG/crawl" >/dev/null
}


function directory_recrawl()
{
    directory_crawl "$@";
}


function directory_crawl_delete()
{
    rm -rf "$PG/crawl";
}


function metadata_modify ()
{
    chmod -R 777 "$PG/crawl";
    chown -R 1234 "$PG/crawl";
}


function run_tests()
{
    run emptyfiles_create;
    run emptyfiles_delete;


    # run emptydirs_create;
    # run emptydirs_delete;


    run smallfiles_create;
    run smallfiles_rewrite;
    echo 3 > /proc/sys/vm/drop_caches;
    sleep 10;
    run smallfiles_read;
    run smallfiles_reread;
    run smallfiles_delete;


    run largefile_create;
    run largefile_rewrite;
    echo 3 > /proc/sys/vm/drop_caches;
    sleep 10;
    run largefile_read;
    run largefile_reread;
    run largefile_delete;


    run directory_crawl_create;
    echo 3 > /proc/sys/vm/drop_caches;
    sleep 10;
    run directory_crawl;
    run directory_recrawl;
    run metadata_modify;
    run directory_crawl_delete;
}


#####################################################
############ Framework code #########################
#####################################################


function cleanup_playground()
{
    rm -rvf $PG;
    mkdir -p $PG;
}


function params_init()
{
    emptytops=10;
    emptydirs=10000;

    smallfilecount=100000;
    smallblock=4096;

    largeblock=64K;
    largecount=16K;

    crawlwidth=10;
    crawldepth=3;
    leafcount=100;

    smallblob=;
    for i in $(seq 1 $smallblock); do
	smallblob=a$smallblob
    done
}


function _init()
{
    params_init;

    TSTDOUT=251
    TSTDERR=252
    LOGFD=253
    LOGFILE=/tmp/perf$$

    eval "exec $TSTDOUT>&1"
    eval "exec $TSTDERR>&2"
    eval "exec $LOGFD<>$LOGFILE";
}


function parse_cmdline()
{
    MOUNT=;

    if [ "x$1" == "x" ] ; then
        echo "Usage: $0 /gluster/mount"
        exit 1
    fi

    MOUNT="$1";
    PG=$MOUNT/playground;
}


function wrap()
{
    "$@" 1>&$TSTDOUT 2>&$TSTDERR;
}


function measure()
{
    set -o pipefail;
    (time -p wrap "$@") 2>&1 >/dev/null | tail -n 3 | head -n 1 | cut -f2 -d' '
}


function log()
{
    local t;
    local rest;

    t=$1;
    shift;
    rest="$@";

    echo "$rest $t" >&$LOGFD;
}


function run()
{
    local t;

    echo -n "running $@ ... "
    t=$(measure "$@");

    if [ $? -eq 0 ]; then
        echo "done ($t secs)";
        log "$t" "$@";
    else
        echo "FAILED!!!"
    fi
}


function verify_mount()
{
    if [ ! -d "$MOUNT" ] ; then
        echo "Can't access '$MOUNT'"
        exit 1
    fi
}


function show_report()
{
    (echo "Testname Time"; cat $LOGFILE) | column -t;
    rm -f $LOGFILE;
}


function main()
{
    parse_cmdline "$@";

    verify_mount;

    cleanup_playground;

    run_tests;

    show_report;
}


_init && main "$@"
