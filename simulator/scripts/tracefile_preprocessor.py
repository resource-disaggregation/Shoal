import os
import sys
import re
import argparse
import math

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-f', required=True)
    parser.add_argument('-t', default=5.12) # timeslot, in ns.
    parser.add_argument('-o', default=8) #packet overhead, in bytes
    parser.add_argument('-s', default=64) #packet size, in bytes
    parser.add_argument('-g', default=0.1) #guardband for slot size
    args = parser.parse_args()

    filename = args.f
    slot_time = (1+float(args.g)) * float(args.t)
    usable_packet_size_bits = (int(args.s) - int(args.o))*8
    try:
        inp = open(filename, 'r')
        out = open(filename+".processed", 'w')

        count = 0
        for line in inp:
            if count != 0:
                tokens = line.split(',')
                out.write(tokens[0].strip())
                out.write(',')
                out.write(tokens[1].strip())
                out.write(',')
                out.write(tokens[2].strip())
                out.write(',')
                pkt_size = int(math.ceil((float(tokens[3].strip())*8)/usable_packet_size_bits))
                out.write(str(pkt_size))
                out.write(',')
                timeslot = int(math.ceil((float(tokens[4].strip()) * 1e9)/slot_time)) #5.12 for 100G
                out.write(str(timeslot))
                out.write('\n')
            count += 1

        inp.close()
        out.close()

    except:
        print "error: could not open the file '" + filename + "'"
        sys.exit()


if __name__ == '__main__' : main()
