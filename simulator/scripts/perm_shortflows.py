import sys
import numpy
import random

N = int(sys.argv[1])
SIZE = int(sys.argv[2])

NUM_OF_FLOWS = 50
flowsize = 130000 #in Bytes

A = list(numpy.random.permutation(N))
src = [A[i] for i in xrange(0,SIZE,1)]
dst = [A[i] for i in xrange(SIZE-1,-1,-1)]
assert(len(src)==SIZE and len(dst)==SIZE)
for i in range(SIZE):
    assert(src[i]>=0 and src[i]<N)
    assert(dst[i]>=0 and dst[i]<N)
    assert(src[i] != dst[i])
starttime = [[None for i in range(NUM_OF_FLOWS)] for j in range(SIZE)]

for i in range(SIZE):
    t = random.randint(0,10000) #in ns
    starttime[i][0] = t
    for j in xrange(1,NUM_OF_FLOWS,1):
        t = starttime[i][j-1] + random.randint(50000,60000)
        starttime[i][j] = t

flows = []
for i in range(SIZE):
    for j in range(NUM_OF_FLOWS):
        flows.append([src[i],dst[i],float(starttime[i][j])/1e9])

flows.sort(key=lambda x: x[2])
print flows
f = open('perm-shortflows-'+str(N)+'/'+str(SIZE)+'.csv', 'w')
ID=0
for flow in flows:
    f.write(str(ID)+','+str(flow[0])+','+str(flow[1])+','+str(flowsize)+','+str(flow[2]))
    f.write('\n')
    ID += 1
f.close()


