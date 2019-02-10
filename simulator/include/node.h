#ifndef __NODE_H__
#define __NODE_H__

#include <stdint.h>

#include "bounded_buffer.h"
#include "min_priority_queue.h"
#include "link.h"
#include "packet.h"
#include "flow.h"
#include "params.h"
#include "arraylist.h"

struct flow_stats {
    int16_t src;
    int16_t dst;
    int64_t flow_size;
    int64_t sender_completion_time_1;//last sent - flow created
    int64_t sender_completion_time_2;//last sent - first sent
    int64_t receiver_completion_time;//last recvd - first recvd
    int64_t sender_receiver_completion_time;//last recvd - first sent
    int64_t actual_completion_time;//last recvd - flow created
};

typedef struct flow_stats* flow_stats_t;

typedef struct stats {
    int64_t host_pkt_transmitted;
    int64_t non_host_pkt_transmitted;
    int64_t dummy_pkt_transmitted;
    int64_t pkt_received;
    int64_t host_pkt_received;
    int64_t non_host_pkt_received;
    int64_t dummy_pkt_received;
    int64_t total_time_active;
    arraylist_t flow_stat_list;
    int16_t curr_incast_degree;
    int16_t max_incast_degree;
    int64_t max_queuing;
    int64_t current_agg_queue_size;
    int64_t queue_len_histogram[FWD_BUFFER_LEN];
#ifdef AGG_NODE_QUEUING
    int64_t ttl_queue_len_histogram[MAX_NODE_BUFFER_LEN];
#endif
} stats_t;

struct host_flow_queue_element {
    int16_t dst_index;
    int64_t throttle_value;
    int64_t start_time;
};

typedef struct host_flow_queue_element* host_flow_queue_element_t;

struct node {
    int16_t node_index;
    int16_t* schedule_table;

    // bit vector to check that got a packet from each node in each epoch
    int8_t packet_in_epoch[NUM_OF_NODES];

    // bit vector to keep track of active nodes, if node is inactive will not
    // send a packet to it
    int8_t active_node[NUM_OF_NODES];

    bounded_buffer_t fwd_buffer[NUM_OF_NODES];

    //list of all the active flows
    arraylist_t host_flow_queue[NUM_OF_NODES];
    //start index to schedule host flows in RR
    int start_idx[NUM_OF_NODES];
    int num_of_ready_host_flows[NUM_OF_NODES];

    //bit vectors for sanity check of queue bound invariant
    int8_t host_pkt_allocated[NUM_OF_NODES][NUM_OF_NODES];
    int8_t fwd_pkt_allocated[NUM_OF_NODES][NUM_OF_NODES];

    //number of host pkt allocated on a given link
    int16_t num_of_host_pkt_allocated[NUM_OF_NODES];

    //stores the last throttle value for a flow on a given link;
    //used when a new instance of the flow starts before throttle value goes to 0
    int64_t last_throttle_value[NUM_OF_NODES][NUM_OF_NODES];

    //used to store last pkt sent (recvd)
    int16_t last_to_last_pkt_sent[NUM_OF_NODES];
    int16_t last_pkt_sent[NUM_OF_NODES];
    int16_t last_to_last_pkt_sent_temp[NUM_OF_NODES];
    int16_t last_pkt_sent_temp[NUM_OF_NODES];
    int16_t last_to_last_pkt_recvd[NUM_OF_NODES];
    int16_t last_pkt_recvd[NUM_OF_NODES];

    link_t link[NUM_OF_NODES];

    flow_send_t host_flows[NUM_OF_NODES]; //flows starting at this node
                                          //indexed by flow-dst-index
    flow_recv_t dst_flows[NUM_OF_NODES]; //flows destined to this node
                                         //indexed by flow-src-index
    int64_t num_of_active_host_flows;
    int64_t num_of_active_network_host_flows;
    int64_t curr_num_of_sending_nodes;

    int16_t flow_dst_sent_in_curr_timeslot;

    stats_t stat;

    int64_t seq_num[NUM_OF_NODES];
    //re-ordering buffer
    arraylist_t re_order_buffer[NUM_OF_NODES];
    int64_t curr_seq_num[NUM_OF_NODES];
    int64_t max_re_order_buffer_size;
};

typedef struct node* node_t;

node_t create_node(int16_t, int16_t*);
void free_node(node_t);

#endif
