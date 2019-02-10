#!/bin/bash

tput_file='system_tput'
queue_file='queue_len_999'

if [ -e ${tput_file} ];
then
    rm ${tput_file}
fi

if [ -e ${queue_file} ];
then
    rm ${queue_file}
fi

for (( i = 0; i < 29; i = i + 1 ));
do
    echo "python parse_outfile.py ${i}"
    python parse_outfile.py ${i}
done
