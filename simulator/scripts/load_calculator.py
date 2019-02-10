import sys

num_of_nodes = int(sys.argv[1])
f = open(sys.argv[2], "r")

bytes_recvd = [0 for i in range(num_of_nodes)]

i = 0
for line in f:
    if i == 0:
        i = i + 1
        continue
    tokens = line.split(',')
    dst = int(tokens[2].strip())
    t = float(tokens[4].strip())
    bytes_recvd[dst] += float(tokens[3].strip())
f.close()

total_rate = 0
for i in range(num_of_nodes):
    total_rate += (float(bytes_recvd[i]*8)/float(t)) * 1e-9
    print i, ((float(bytes_recvd[i]*8)/float(t)) * 1e-9)
print "avg recv rate = " + str(total_rate/num_of_nodes) + " Gbps"
