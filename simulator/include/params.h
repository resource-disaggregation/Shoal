#ifndef __PARAMS_H__
#define __PARAMS_H__

#define NUM_OF_NODES 512
#define MAX_FLOW_ID 255
#define FWD_BUFFER_LEN (2*NUM_OF_NODES)
#define MAX_NODE_BUFFER_LEN (FWD_BUFFER_LEN*NUM_OF_NODES)
#define PROPAGATION_DELAY 0 //in units of time slot
#define LINK_CAPACITY (PROPAGATION_DELAY + 1)

#define NUM_OF_THREADS 4
#define NUM_OF_CORES 8

#endif
