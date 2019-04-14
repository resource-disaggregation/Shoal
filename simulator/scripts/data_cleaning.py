import os
import sys
import re
import argparse
import math

max_completion_time = [None for i in range(5)]

def parse_file(inp, small_size=0, big_size=1e10):
    completion_time_file = []
    goodput_file = []

    for i in range(5):
        completion_time_file.append(open('data/completion_time_'+str(i)+'.dat', 'w'))
        goodput_file.append(open('data/goodput_'+str(i)+'.dat','w'))

    count = 0
    completion_time_list = [[] for i in range(5)]
    completion_time_list_agg = [0.0 for i in range(5)]
    completion_time_list_count = [0 for i in range(5)]
    goodput_list = [[] for i in range(5)]
    goodput_list_agg = [0.0 for i in range(5)]
    goodput_list_count = [0 for i in range(5)]

    for line in inp:
        tokens = line.split(',')

        tokens1 = tokens[0].split(' ')
        regex = re.compile('(.*)pkt')
        match = regex.search(tokens1[1])
        size = match.group(1)

        regex =  re.compile('\((.*)->(.*)\)')
        match = regex.search(tokens1[0])
        src = int(match.group(1))
        dst = int(match.group(2))

        if len(tokens1) == 3:
            regex = re.compile('(.*)pkt')
            match = regex.search(tokens1[2])
            recvd_size = match.group(1)
        else:
            recvd_size = size

        regex1 = re.compile('(.*)us')
        regex2 = re.compile('(.*)Gbps')

        for i in range(1, len(tokens)):
            tok = tokens[i].strip()
            tokens1 = tok.split('/')

            match1 = regex1.search(tokens1[1])
            match2 = regex2.search(tokens1[2])

            if size == recvd_size and int(size) <= small_size:
                completion_time_list_agg[i-1] += float(match1.group(1))
                completion_time_list_count[i-1] += 1
                completion_time_list[i-1].append(float(match1.group(1)))
            if int(size) >= big_size:
                goodput_list_agg[i-1] += float(match2.group(1))
                goodput_list_count[i-1] += 1
                goodput_list[i-1].append(float(match2.group(1)))


    for i in range(5):
        completion_time_list[i].sort()
        if i == 4:
            completion_time_cdf = open("data/completion_time_cdf", "w")
            prev = 0
            for j in range(len(completion_time_list[i])):
                completion_time_cdf.write(str(completion_time_list[i][j]))
                completion_time_cdf.write("\n")
                #completion_time_cdf.write(str(completion_time_list[i][j]) + ",")
                #new = (1.0/len(completion_time_list[i])) + prev
                #completion_time_cdf.write(str(new) + "\n")
                #prev = new
            completion_time_cdf.close()
        goodput_list[i].sort()
        if i == 4:
            goodput_cdf = open("data/goodput_cdf", "w")
            prev = 0
            for j in range(len(goodput_list[i])):
                goodput_cdf.write(str(goodput_list[i][j]))
                goodput_cdf.write("\n")
                #goodput_cdf.write(str(goodput_list[i][j]) + ",")
                #new = (1.0/len(goodput_list[i])) + prev
                #goodput_cdf.write(str(new) + "\n")
                #prev = new
            goodput_cdf.close()
        if (len(completion_time_list[i]) > 0):
            max_completion_time[i] = completion_time_list[i][len(completion_time_list[i])-1]

    for i in [4]:
        for j in range(25):
            if (j == 24):
                if (completion_time_list_count[i] > 0):
                    avg_comp_time = completion_time_list_agg[i] / completion_time_list_count[i]
                else:
                    avg_comp_time = -1
                completion_time_file[i].write("avg " + str(avg_comp_time) + "\n")
                if (goodput_list_count[i] > 0):
                    avg_gput = goodput_list_agg[i] / goodput_list_count[i]
                else:
                    avg_gput = -1
                goodput_file[i].write("avg " + str(avg_gput) + "\n")
                continue
            if (j == 21):
                x = 0.99 * (len(completion_time_list[i])-1)
                y = 0.99 * (len(goodput_list[i])-1)
            elif (j == 22):
                x = 0.999 * (len(completion_time_list[i])-1)
                y = 0.999 * (len(goodput_list[i])-1)
            elif (j == 23):
                x = 0.9999 * (len(completion_time_list[i])-1)
                y = 0.9999 * (len(goodput_list[i])-1)
            else:
                x = ((j * 5) * (len(completion_time_list[i])-1))/100
                y = ((j * 5) * (len(goodput_list[i])-1))/100

            if len(completion_time_list[i]) > 0:
                c = completion_time_list[i][int(x)]
            else:
                c = -1
            if len(goodput_list[i]) > 0:
                g = goodput_list[i][int(y)]
            else:
                g = -1

            if (j == 21):
                completion_time_file[i].write("99" + " " + str(c) + "\n")
                goodput_file[i].write("99" + " " + str(g) + "\n")
            elif (j == 22):
                completion_time_file[i].write("99.9" + " " + str(c) + "\n")
                goodput_file[i].write("99.9" + " " + str(g) + "\n")
            elif (j == 23):
                completion_time_file[i].write("99.99" + " " + str(c) + "\n")
                goodput_file[i].write("99.99" + " " + str(g) + "\n")
            else:
                completion_time_file[i].write(str(j*5) + " " + str(c) + "\n")
                goodput_file[i].write(str(j*5) + " " + str(g) + "\n")

        completion_time_file[i].close()
        goodput_file[i].close()

def create_directory(directory):
    if (not os.path.isdir(directory)):
        try:
            os.mkdir(directory)
        except:
            print "error: could not create directory '" + directory + "'"
            sys.exit()
    #else:
    #    print "error: directory '" + directory + "' already exists"
    #    sys.exit()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-f', required=True)
    parser.add_argument('-s', default=100) #size in kb
    parser.add_argument('-l', default=1000) #size in kb
    parser.add_argument('-o', default=0) #packet overhead, in bytes
    parser.add_argument('-p', default=64) #packet size, in bytes
    args = parser.parse_args()

    usable_packet_size_bytes = (int(args.p) - int(args.o))
    short_flow_packets = int(math.ceil(int(args.s)*1024.0/usable_packet_size_bytes))
    long_flow_packets = int(math.ceil(int(args.l)*1024.0/usable_packet_size_bytes))
    filename = args.f

    try:
        inp = open(filename, 'r')
    except:
        print "error: could not open the file '" + filename + "'"
        sys.exit()

    tokens = filename.split('/')
    #directory = tokens[len(tokens)-1]
    #create_directory(directory)

    #os.chdir(directory)

    i=0
    for d in tokens:
        if i==0:
            i=1
            continue
        create_directory(d)
        os.chdir(d)

    create_directory('data')

    parse_file(inp,small_size=short_flow_packets,big_size=long_flow_packets)

    inp.close()

if __name__ == '__main__' : main()
