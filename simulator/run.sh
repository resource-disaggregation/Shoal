#!/bin/bash

function usage {
    echo 'usage: ./run.sh -f <filename> [-e <epochs> -w <0/1> -b <link bandwidth> -t <time slot> -c <cell size> -h <header size> -s <short flow size> -l <long flow size> -n <num of flows> -d <percentage failed nodes> -i <interval>][-a -r -p]'
    echo '-e: to run the exp till specified num of epochs'
    echo '-w: 1 = static workload; 0 = dynamic workload'
    echo '-b: link bandwidth in Gbps (float)'
    echo '-t: length of a time slot in ns (float)'
    echo '-c: packet(cell) size in Bytes'
    echo '-h: cell header size in Bytes'
    echo '-s: small flow size in KB'
    echo '-l: long flow size in KB'
    echo '-n: stop experiment after these many flows have finished'
    echo '-d: percentage failed nodes'
    echo '-i: interval'
    echo '-r: to run shoal'
    echo '-p: to plot graphs'
    echo '-a: to do both run and plot at once'
    exit 1
}

filepath=""
filename=""
epochs="0"

option=false
run=false
plot=false
static_workload=1
bandwidth=100
slot_time=5.12
short_size_in_kb=100
long_size_in_kb=1000
packet_size=64
header_size=8
numflowsfinish=500000
failednodespercent=0
interval=0
while getopts "h:f:e:w:b:t:s:l:c:n:d:i:rpa" OPTION
do
    echo $OPTION $OPTARG;
    case $OPTION in
        e) epochs=$OPTARG
            ;;
        f) filepath=$OPTARG
            ;;
        b) bandwidth=$OPTARG
            ;;
        h) header_size=$OPTARG
            ;;
        t) slot_time=$OPTARG
            ;;
        w) static_workload=$OPTARG
           ;;
        s) short_size_in_kb=$OPTARG
           ;;
        l) long_size_in_kb=$OPTARG
           ;;
        c) packet_size=$OPTARG
           ;;
        n) numflowsfinish=$OPTARG
           ;;
        d) failednodespercent=$OPTARG
           ;;
        i) interval=$OPTARG
            ;;
        r) run=true
           option=true
            ;;
        p) plot=true
           option=true
            ;;
        a) compile=true
           run=true
           plot=true
           option=true
            ;;
        *) usage
            ;;
    esac
done

if [ "$filepath" == "" ];
then
    usage
fi

if ! $option ;
then
    usage
fi

filename=$(basename "${filepath}") #extract the filename from the path

if $run ;
then
    echo -e "\n*** Running [./bin/driver -f "${filepath}" -e "${epochs}" -w "${static_workload}" -b "${bandwidth}" -t "${slot_time}" -c "${packet_size}" -h "${header_size}" -n "${numflowsfinish}" -d "${failednodespercent}" -i "${interval}"] ***\n"
    ./bin/driver -f "${filepath}" -e "${epochs}" -w "${static_workload}" -b "${bandwidth}" -t "${slot_time}" -c "${packet_size}" -h "${header_size}" -n "${numflowsfinish}" -d "${failednodespercent}" -i "${interval}"
fi

if $plot ;
then
    echo -e "\n*** Data cleaning [python scripts/data_cleaning.py -f "${filepath}".out] -s "${short_size_in_kb}" -l "${long_size_in_kb}" -o "${header_size}" -p "${packet_size}" ***\n"
    if [ ! -e "experiments" ];
    then
        mkdir experiments
    fi
    cd experiments/
    python ../scripts/data_cleaning.py -f ../"${filepath}".out -s "${short_size_in_kb}" -l "${long_size_in_kb}" -o "${header_size}" -p "${packet_size}"
fi
