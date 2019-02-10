import numpy
import sys

SAMPLE_SIZE = 1
NUM_OF_NODES = int(sys.argv[1])

for i in range(SAMPLE_SIZE):
    A = list(numpy.random.permutation(NUM_OF_NODES))
    print A
    for j in xrange(1, NUM_OF_NODES, 25):
        f = open('permutation-'+str(NUM_OF_NODES)+'/'+str(j)+'.dat', 'w')
        ID = 0
        for k in range(j):
            f.write(str(ID)+','+str(A[k])+','+str(A[(k+1)%len(A)])+','+'1000000000'+',0')
            f.write('\n')
            ID += 1
        f.close()
