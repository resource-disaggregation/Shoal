import numpy
import random
import sys

SAMPLE_SIZE = 1
NUM_OF_NODES = int(sys.argv[1])
INCAST_DEGREE = int(sys.argv[2])

for i in range(SAMPLE_SIZE):
    f = open('incast-'+str(NUM_OF_NODES)+'/'+str(INCAST_DEGREE)+'.dat', 'w')
    ID = 0
    #dst = random.randint(0, NUM_OF_NODES)
    dst = NUM_OF_NODES-1
    for j in range(INCAST_DEGREE):
        if j != dst:
            f.write(str(ID)+','+str(j)+','+str(dst)+','+'511'+',0')
            f.write('\n')
            ID += 1
    #for j in range(INCAST_DEGREE):
    #    if j != dst:
    #        f.write(str(ID)+','+str(dst)+','+str(j)+','+'70'+',0')
    #        f.write('\n')
    #        ID += 1
    f.close()
