#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <semaphore.h>
#include <pthread.h>
#include <sys/time.h>
#include <ctype.h>
#include <unistd.h>
#include <string.h>
#include <assert.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <errno.h>
#include <math.h>

#include "node.h"
#include "arraylist.h"
#include "bounded_buffer.h"
#include "link.h"
#include "packet.h"
#include "flow.h"
#include "params.h"
#include "flow_patterns.h"
#include "queue_add_remove.h"

#include "driver.h"

#define MALLOC_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d malloc() failed\n", __FILE__, line_num); \
        exit(0);}

static int16_t** global_schedule_table;
node_t* nodes; //extern variable
volatile int64_t curr_timeslot = 0; //extern variable
volatile int64_t curr_epoch = 0; //extern variable

static int64_t time_to_start_logging = INT64_MAX;
static int8_t start_logging = 0;
int static_workload = 1;

static int16_t max_host_flows = NUM_OF_NODES-1;
static int32_t max_epochs_to_run;

static int16_t arrived = 0;
static int16_t working = 0;
static volatile int8_t terminate = 0;
static volatile int8_t terminate1 = 0;
static volatile int8_t terminate2 = 0;
static volatile int64_t num_of_flows_finished[NUM_OF_THREADS] = {0};

static pthread_mutex_t arrived_mutex;
static pthread_cond_t arrived_cv;
static pthread_mutex_t working_mutex;
static pthread_cond_t working_cv;

static pthread_spinlock_t update_active_flows[NUM_OF_NODES];
static pthread_spinlock_t incast_degree_lock[NUM_OF_NODES];

//needed for tracefile workloads
char* ptr; //points to the mmaped trace file
int8_t flow_trace_scanned_completely = 0; //extern variable
int64_t flows_started_in_epoch = 0;
int64_t total_flows_started = 0;
int64_t ttl_num_flows_in_sim = 1000000;

// Default values for simulation
float slot_len = 5.12;
float link_bandwidth = 100;
int packet_size = 64; // default packet size is 64 bytes
int packet_overhead = 8; //default packet overhead is 8 bytes
float percentage_failed_nodes = 0.0; //extern variable
int interval = 0;

static FILE* out; //all the stats are logged in this file

static int8_t thread_job_finished[NUM_OF_THREADS];
static int8_t run_till_max_epoch = 0;

struct rx_update {
    int16_t dst_index;
    packet_t pkt;
};

typedef struct rx_update* rx_update_t;

static rx_update_t rx_update_buffer[NUM_OF_THREADS]; //stores recvd pkt used to
                                                   //update dst node in the end

struct thread_params {
    int16_t tid;
    int16_t start; //first node index in the loop (inclusive)
    int16_t end; //last node index in the loop (not inclusive)
    add_host_flows_t add_host_flows;
};


/**
Failures thing:
1. detect if didn't get a packet (even dummy one) from a node every epoch
2. if didn't get a packet:
  2.1. drop all forwarding packets (need some way to tell that to forwarded nodes)
  2.2. append all local packets once more
  2.3. mark slot to failed node as unusable
  2.4. don't expect to get a packet from that node ever again

Recovering from failures:
1. if see a packet from a failed node:
  1.1 mark it's slot as ok
  1.2 can start sending packets to it

**/


typedef struct thread_params* thread_params_t;

static inline void check_perm_matrix()
{
    for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
        int8_t bitmap[NUM_OF_NODES] = {0};

        for (int16_t j = 0; j < NUM_OF_NODES; ++j) {
            assert(bitmap[j] == 0);
        }

        for (int16_t j = 0; j < NUM_OF_NODES-1; ++j) {
            ++(bitmap[global_schedule_table[i][j]]);
        }

        for (int16_t j = 0; j < NUM_OF_NODES-1; ++j) {
            if (j == i) assert(bitmap[j] == 0);
            else assert(bitmap[j] == 1);
        }
    }

    for (int16_t j = 0; j < NUM_OF_NODES-1; ++j) {
        int8_t bitmap[NUM_OF_NODES] = {0};

        for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
            assert(bitmap[i] == 0);
        }

        for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
            ++(bitmap[global_schedule_table[i][j]]);
        }

        for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
            assert(bitmap[i] == 1);
        }
    }
}

static inline void initialize_global_schedule_table(FILE* inp)
{
    global_schedule_table = (int16_t**) malloc(NUM_OF_NODES * sizeof(int16_t*));
    MALLOC_TEST(global_schedule_table, __LINE__);

    for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
        global_schedule_table[i]
            = (int16_t*) malloc((NUM_OF_NODES - 1) * sizeof(int16_t));
        MALLOC_TEST(global_schedule_table[i], __LINE__);
    }

    for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
        for (int16_t j = 0; j < NUM_OF_NODES - 1; ++j) {
            global_schedule_table[i][j] = (i + j + 1) % NUM_OF_NODES;
            //int ret = fscanf(inp, "%d ", &global_schedule_table[i][j]);
            //assert(ret == 1);
        }
    }

    check_perm_matrix();
}

static inline void randomize_global_schedule_table()
{
    for (int16_t j = 0; j < NUM_OF_NODES-1; ++j) {
        int16_t k = rand() % (NUM_OF_NODES-1);
        for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
            int16_t temp = global_schedule_table[i][j];
            global_schedule_table[i][j] = global_schedule_table[i][k];
            global_schedule_table[i][k] = temp;
        }
    }

    check_perm_matrix();
}

static inline void free_global_schedule_table()
{
    for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
        free(global_schedule_table[i]);
    }

    free(global_schedule_table);
}

static inline void print_system_tput()
{
    double node_gput[NUM_OF_NODES] = {0};
    double fwd_gput[NUM_OF_NODES] = {0};
    double wasted_gput[NUM_OF_NODES] = {0};
    int count = 0;
    double total_system_gput = 0;
    double fwd_system_gput = 0;
    double wasted_system_gput = 0;
    double avg_system_gput = 0;
    double avg_fwd_gput = 0;
    double avg_wasted_gput = 0;
    double max_system_gput = 0;
    double min_system_gput = link_bandwidth; //INTERFACE_BANDWIDTH;

    for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
        if (nodes[i]->stat.total_time_active > 0) {
            node_gput[i] = (nodes[i]->stat.host_pkt_received * packet_size * 8)
                / (nodes[i]->stat.total_time_active * slot_len * 1.0);
            fwd_gput[i] = (nodes[i]->stat.non_host_pkt_received * packet_size * 8)
                / (nodes[i]->stat.total_time_active * slot_len * 1.0);
            wasted_gput[i] = (nodes[i]->stat.dummy_pkt_received * packet_size * 8)
                / (nodes[i]->stat.total_time_active * slot_len * 1.0);
            total_system_gput += node_gput[i];
            fwd_system_gput += fwd_gput[i];
            wasted_system_gput += wasted_gput[i];
            if (node_gput[i] > max_system_gput) {
                max_system_gput = node_gput[i];
            }
            if (node_gput[i] < min_system_gput) {
                min_system_gput = node_gput[i];
            }
            ++count;
        }
    }

    avg_system_gput = total_system_gput / count;
    avg_fwd_gput = fwd_system_gput / count;
    avg_wasted_gput = wasted_system_gput / count;
    printf("\nSystem tput (recvd) in Gbps [%d] = %0.3lf/%0.3lf/%0.3lf\n\n",
            count, avg_system_gput, avg_fwd_gput, avg_wasted_gput);
    fflush(stdout);
}

static inline int64_t get_app_to_send_next(node_t node, flow_send_t host_flow)
{
    int8_t found = 0;
    flow_stat_logger_sender_t s;
    flow_stat_logger_sender_t s_list
        = host_flow->flow_stat_logger_sender_list;

    for (int16_t j = 0; j < MAX_FLOW_ID; ++j) {
        if (s_list[j].flow_id == host_flow->curr_flow_id) {
            s = &(s_list[j]);
            found = 1;
            break;
        }
    }
    assert(found);

    int64_t size = arraylist_size(s->flow_stat_logger_sender_app_list);
    assert(size > 0);

    int64_t index = 0;
    flow_stat_logger_sender_app_t curr_app = NULL;

#ifdef ROUND_ROBIN
    do {
        curr_app = (flow_stat_logger_sender_app_t)
            arraylist_get(s->flow_stat_logger_sender_app_list, 0);
        arraylist_remove(s->flow_stat_logger_sender_app_list, 0);
        arraylist_add(s->flow_stat_logger_sender_app_list, curr_app);
        ++index;
    } while (curr_app->app_pkt_transmitted == curr_app->app_flow_size
            && index < size);
#endif

#ifdef SHORTEST_FLOW_FIRST
    do {
        curr_app = (flow_stat_logger_sender_app_t)
            arraylist_get(s->flow_stat_logger_sender_app_list, index);
        if (curr_app->app_pkt_transmitted < curr_app->app_flow_size) {
            if (curr_app->app_flow_size == host_flow->curr_min_flow_size) {
                break;
            }
        }
        ++index;

    } while (index < size);
#endif

    assert(index <= size && curr_app != NULL);

    if (curr_app->time_first_pkt_sent == -1) {
        curr_app->time_first_pkt_sent = curr_timeslot;
    }

    ++(curr_app->app_pkt_transmitted);

    if (curr_app->app_pkt_transmitted == curr_app->app_flow_size) {
        curr_app->time_last_pkt_sent = curr_timeslot;

#ifdef SHORTEST_FLOW_FIRST
        flow_stat_logger_sender_app_t temp_app = NULL;
        index = 0;
        int64_t min_flow_size = -1;
        int64_t empty = 0;
        do {
            temp_app = (flow_stat_logger_sender_app_t)
                arraylist_get(s->flow_stat_logger_sender_app_list, index);
            if (temp_app->app_pkt_transmitted < temp_app->app_flow_size) {
                if (min_flow_size == -1
                    || (temp_app->app_flow_size < min_flow_size)) {
                    min_flow_size = temp_app->app_flow_size;
                }
            } else ++empty;

            ++index;

        } while (index < size);

        assert(min_flow_size != -1 || empty == size);

        host_flow->curr_min_flow_size = min_flow_size;
#endif

    }

    return curr_app->app_id;

}

static inline int8_t subtract_one(int16_t src, int16_t mid, int16_t dst,
        int8_t sent_host_pkt, int64_t queue_len)
{
    int16_t curr_time = (curr_timeslot - 1 - PROPAGATION_DELAY) % (NUM_OF_NODES-1);
    int16_t src_to_mid_time = -1;
    int16_t mid_to_dst_time = -1;

    for (int16_t i = 0; i < NUM_OF_NODES-1; ++i) {
        if (nodes[src]->schedule_table[i] == mid) {
            src_to_mid_time = i;
        }
        if (nodes[mid]->schedule_table[i] == dst) {
            mid_to_dst_time = i;
        }
    }

    assert (src_to_mid_time != -1 && (mid_to_dst_time != -1 || mid == dst));

    if (mid == dst) {
        if (src_to_mid_time <= curr_time) {
            return 0;

        } else {
            return 0;
        }
    }

    if (curr_time < mid_to_dst_time && mid_to_dst_time <= src_to_mid_time) {
        if (queue_len == 0) return 0;
        else return 1;
    }

    if (curr_time < src_to_mid_time && src_to_mid_time < mid_to_dst_time) {
        return 0;
    }

    if (mid_to_dst_time < src_to_mid_time && src_to_mid_time < curr_time) {
        if (queue_len == 0) return 0;
        else return 1;
    }

    if (mid_to_dst_time < src_to_mid_time && src_to_mid_time == curr_time) {
        if (sent_host_pkt) return 0;
        else {
            if (queue_len == 0) return 0;
            else return 1;
        }
    }

    if (src_to_mid_time < mid_to_dst_time && mid_to_dst_time < curr_time) {
        return 0;
    }

    if (src_to_mid_time == mid_to_dst_time && mid_to_dst_time < curr_time) {
        return 0;
    }

    if (mid_to_dst_time < curr_time && curr_time < src_to_mid_time) {
        return 0;
    }

    if (src_to_mid_time < curr_time && curr_time < mid_to_dst_time) {
        if (queue_len == 0) return 0;
        else return 1;
    }

    if (src_to_mid_time == curr_time && curr_time < mid_to_dst_time) {
        if (queue_len == 0) return 0;
        else {
            if (sent_host_pkt) return 0;
            else return 1;
        }
    }

    return 0;
}

void* work_per_timeslot(void* arg)
{
    while (1) {
        //barrier synchronization prologue
        pthread_mutex_lock(&arrived_mutex);
        ++arrived;
        if (arrived == NUM_OF_THREADS) {
            working = NUM_OF_THREADS;
            pthread_cond_broadcast(&arrived_cv);

        } else {
            while (arrived < NUM_OF_THREADS) {
                pthread_cond_wait(&arrived_cv, &arrived_mutex);
            }
        }
        pthread_mutex_unlock(&arrived_mutex);

        thread_params_t params = (thread_params_t) arg;
        int16_t tid = params->tid;
        for (int16_t i = params->start; i < params->end; ++i) {
            int16_t host_index = i;
            node_t host_node = nodes[host_index];

            params->add_host_flows(host_node);

            //Tx Pipeline
            int64_t x = curr_timeslot % (NUM_OF_NODES - 1);
            int16_t dst_index = host_node->schedule_table[x];

            int64_t prev_x = (curr_timeslot > 0)
                ? (curr_timeslot - 1) % (NUM_OF_NODES - 1) : 0;
            int16_t prev_dst_index = host_node->schedule_table[prev_x];

            bounded_buffer_t fwd_buffer = host_node->fwd_buffer[dst_index];

            //record the queue length
            int32_t len = bounded_buffer_num_of_elements(fwd_buffer);
            int32_t fwd_len = len-host_node->num_of_host_pkt_allocated[dst_index];
            ++(host_node->stat.queue_len_histogram[len]);
            //host node is a failed node
            if (host_index < percentage_failed_nodes*NUM_OF_NODES) {
                assert(len == 0 && fwd_len == 0);
            }

#ifdef AGG_NODE_QUEUING
            //record total queue len
            int64_t curr_queuing = 0;
            for (int16_t j = 0; j < NUM_OF_NODES; ++j) {
                int32_t size
                    = bounded_buffer_num_of_elements(host_node->fwd_buffer[j]);
                curr_queuing += size;
            }
            ++(host_node->stat.ttl_queue_len_histogram[curr_queuing]);
            if (curr_queuing > host_node->stat.max_queuing) {
                host_node->stat.max_queuing = curr_queuing;
            }
#endif
            //schedule packets only if the host node has not failed
            //and the intermediate node has not failed
            if (host_index >= percentage_failed_nodes*NUM_OF_NODES
                    && dst_index >= percentage_failed_nodes*NUM_OF_NODES) {

                arraylist_t queue = host_node->host_flow_queue[dst_index];

                arraylist_t host_flow_pkts_to_be_added_to_fwd_queue
                    = create_arraylist();

                int32_t size = arraylist_size(queue);
                int j = (host_node->start_idx[dst_index] < size)
                    ? host_node->start_idx[dst_index] : 0;
                host_node->num_of_ready_host_flows[dst_index] = 0;
                for (int32_t k = 0; k < size; ++k) {
                    host_flow_queue_element_t x
                        = (host_flow_queue_element_t) arraylist_get(queue, j);

                    //should not schedule packets destined to failed node
                    if (x->dst_index < percentage_failed_nodes*NUM_OF_NODES)
                        continue;

                    if (host_node->num_of_host_pkt_allocated[dst_index]
                            < max_host_flows && len >= x->throttle_value) {

                        //ensures at most one host flow pkt per fwd queue
                        if (host_node->num_of_host_pkt_allocated[dst_index] == 0) {
#ifdef SELECTIVE_SCHEDULING
                            int64_t age = NUM_OF_NODES;
                            if (interval != 0) {
                                age = (curr_timeslot - x->start_time)/interval;
                            }
                            assert(age >= 0);
                            if (age >= log2(NUM_OF_NODES) || len <= pow(2,age)) {
                                arraylist_add(host_flow_pkts_to_be_added_to_fwd_queue, x);
                                ++(host_node->num_of_host_pkt_allocated[dst_index]);
                                assert(host_node->num_of_host_pkt_allocated[dst_index]
                                        <= 1);
                                host_node->start_idx[dst_index] = (j + 1)%size;
                            } else {
                                ++(host_node->num_of_ready_host_flows[dst_index]);
                            }
#else
                            arraylist_add(host_flow_pkts_to_be_added_to_fwd_queue, x);
                            ++(host_node->num_of_host_pkt_allocated[dst_index]);
                            assert(host_node->num_of_host_pkt_allocated[dst_index]
                                    <= 1);
                            host_node->start_idx[dst_index] = (j + 1)%size;
#endif
                        } else {
                            ++(host_node->num_of_ready_host_flows[dst_index]);
                        }
                    }
                    if (x->throttle_value != INT64_MAX && x->throttle_value != 0) {
                        x->throttle_value -= 1;
                    }
                    assert(x->throttle_value >= 0);
                    j = (j + 1)%size;
                }

                size = arraylist_size(host_flow_pkts_to_be_added_to_fwd_queue);
                for (int32_t j = 0; j < size; ++j) {
                    host_flow_queue_element_t x =
                        arraylist_get(host_flow_pkts_to_be_added_to_fwd_queue, j);

                    int16_t flow_dst_index = x->dst_index;
                    flow_send_t host_flow = host_node->host_flows[flow_dst_index];

                    x->throttle_value = INT64_MAX;

                    assert(host_flow->active == 1);

                    //create the pkt and put it in the FWD buffer
                    packet_t pkt = create_packet(host_index, dst_index,
                        host_index, flow_dst_index, host_flow->curr_flow_id,
                        (host_node->seq_num[flow_dst_index])++);
                    pkt->app_id = get_app_to_send_next(host_node, host_flow);
                    bounded_buffer_put(fwd_buffer, pkt);

                    ++(host_node->host_pkt_allocated[dst_index][flow_dst_index]);
                    assert(host_node
                            ->host_pkt_allocated[dst_index][flow_dst_index] == 1);

#ifdef debug
                    if (host_index == 484 && dst_index == 298) {
                        printf("[%ld/%ld] ADDING HOST PKT of %d to FWD QUEUE\
                            dst-index = %d flow-dst-index = %d throt = %ld (%ld)\n",
                                curr_timeslot, curr_epoch, host_index, dst_index,
                                flow_dst_index, x->throttle_value,
                                host_flow->curr_flow_id);
                    }
#endif
                    //update flow params
                    ++(host_flow->pkt_transmitted);

                    //flow has ended
                    if (host_flow->pkt_transmitted == host_flow->flow_size) {
                        host_flow->active = 0;

                        ++(host_flow->curr_flow_id);

                        --(host_node->num_of_active_network_host_flows);

                        remove_flow_from_host_flow_queues(host_node, flow_dst_index);
                    }
                }

                free_arraylist(host_flow_pkts_to_be_added_to_fwd_queue);
            }

            for (int16_t j = 0; j < NUM_OF_NODES; ++j) {
                if (host_node->last_throttle_value[dst_index][j] != INT64_MAX
                        && host_node->last_throttle_value[dst_index][j] > 0) {
                    --(host_node->last_throttle_value[dst_index][j]);
                    assert(host_node->last_throttle_value[dst_index][j] >= 0);
                }
            }

            host_node->last_to_last_pkt_sent[prev_dst_index]
                = host_node->last_to_last_pkt_sent_temp[prev_dst_index];
            host_node->last_pkt_sent[prev_dst_index]
                = host_node->last_pkt_sent_temp[prev_dst_index];

            int8_t packet_sent = 0;
            host_node->flow_dst_sent_in_curr_timeslot = -1;

            //forward packet
            packet_t fwd_pkt = bounded_buffer_get(fwd_buffer);
            //intermediate node has failed, hence no fwd buffer should be NULL
            if (dst_index < percentage_failed_nodes*NUM_OF_NODES) {
                assert(fwd_pkt == NULL);
            }
            if (fwd_pkt != NULL) {
                fwd_pkt->src_mac = host_index;
                fwd_pkt->dst_mac = dst_index;
                int16_t prev_queue_index
                    = host_node->last_to_last_pkt_recvd[dst_index];
                fwd_pkt->queue_len_prev = (prev_queue_index == -1) ? 0
                    : bounded_buffer_num_of_elements
                        (host_node->fwd_buffer[prev_queue_index])
                    + host_node->num_of_ready_host_flows[prev_queue_index];
                int16_t curr_queue_index
                    = host_node->last_pkt_recvd[dst_index];
                fwd_pkt->queue_len_curr = (curr_queue_index == -1) ? 0
                    : bounded_buffer_num_of_elements
                        (host_node->fwd_buffer[curr_queue_index])
                    + host_node->num_of_ready_host_flows[curr_queue_index];
                link_enqueue(host_node->link[dst_index], fwd_pkt);
                ++(host_node->stat.non_host_pkt_transmitted);

                host_node->last_to_last_pkt_sent_temp[dst_index]
                    = host_node->last_pkt_sent[dst_index];

                if (fwd_pkt->src_ip == host_index) {
                    host_node->last_pkt_sent_temp[dst_index]
                        = fwd_pkt->dst_ip;
                    host_node->flow_dst_sent_in_curr_timeslot = fwd_pkt->dst_ip;

                    ++(host_node->stat.host_pkt_transmitted);

                    --(host_node->host_pkt_allocated[dst_index][fwd_pkt->dst_ip]);
                    assert(host_node
                            ->host_pkt_allocated[dst_index][fwd_pkt->dst_ip] == 0);
                    --(host_node->num_of_host_pkt_allocated[dst_index]);
                    assert(host_node->num_of_host_pkt_allocated[dst_index] >= 0);

#ifdef debug
                    //if ((fwd_pkt->src_mac == 1 && fwd_pkt->dst_mac == 2)
                    //    || (fwd_pkt->src_mac == 2 && fwd_pkt->dst_mac == 1)) {
                    if (host_index == 0) {
                        printf("[%ld/%ld]SENT HOST PKT %d to %d (%d->%d)<%d,%d>\n",
                                curr_timeslot, curr_epoch,
                                fwd_pkt->src_mac, fwd_pkt->dst_mac,
                                fwd_pkt->src_ip, fwd_pkt->dst_ip,
                                host_node->last_to_last_pkt_sent_temp[dst_index],
                                fwd_pkt->dst_ip);
                    }
#endif

                } else {
#ifdef debug
                    //if ((fwd_pkt->src_mac == 1 && fwd_pkt->dst_mac == 2)
                    //    || (fwd_pkt->src_mac == 2 && fwd_pkt->dst_mac == 1)) {
                    if (host_index == 0) {
                        printf("[%ld/%ld]SENT FWD PKT %d to %d (%d->%d)<%d,%d>\n",
                                curr_timeslot, curr_epoch,
                                fwd_pkt->src_mac, fwd_pkt->dst_mac,
                                fwd_pkt->src_ip, fwd_pkt->dst_ip,
                                host_node->last_to_last_pkt_sent_temp[dst_index],
                                fwd_pkt->dst_ip);
                    }
#endif
                    host_node->last_pkt_sent_temp[dst_index] = -1;

                    --(host_node
                        ->fwd_pkt_allocated[fwd_pkt->dst_ip][fwd_pkt->src_ip]);
                    assert(host_node
                       ->fwd_pkt_allocated[fwd_pkt->dst_ip][fwd_pkt->src_ip] == 0);
                }

                packet_sent += 1;

            } else {
                //send dummy packet
                packet_t pkt = create_packet(host_index, dst_index, -1, -1, -1, -1);
                pkt->app_id = -1;
                int16_t prev_queue_index
                    = host_node->last_to_last_pkt_recvd[dst_index];
                pkt->queue_len_prev = (prev_queue_index == -1) ? 0
                    : bounded_buffer_num_of_elements
                        (host_node->fwd_buffer[prev_queue_index])
                    + host_node->num_of_ready_host_flows[prev_queue_index];
                int16_t curr_queue_index
                    = host_node->last_pkt_recvd[dst_index];
                pkt->queue_len_curr = (curr_queue_index == -1) ? 0
                    : bounded_buffer_num_of_elements
                        (host_node->fwd_buffer[curr_queue_index])
                    + host_node->num_of_ready_host_flows[curr_queue_index];
                link_enqueue(host_node->link[dst_index], pkt);
                ++(host_node->stat.dummy_pkt_transmitted);

                host_node->last_to_last_pkt_sent_temp[dst_index]
                    = host_node->last_pkt_sent[dst_index];
                host_node->last_pkt_sent_temp[dst_index] = -1;

                packet_sent += 1;
#ifdef debug
                    if ((pkt->src_mac == 1 && pkt->dst_mac == 2)
                        || (pkt->src_mac == 2 && pkt->dst_mac == 1)) {
                        printf("[%ld,%ld] SENT DUMMY PKT %d to %d <%d, %d>\n",
                                curr_timeslot, curr_epoch,
                                pkt->src_mac, pkt->dst_mac,
                                host_node->last_to_last_pkt_sent_temp[dst_index],
                                pkt->dst_ip);
                    }
#endif
            }

            assert(packet_sent == 1);

            //Rx Pipeline
            if (curr_timeslot - PROPAGATION_DELAY >= 0) {
                int64_t x = (curr_timeslot - PROPAGATION_DELAY)%(NUM_OF_NODES-1);
                dst_index = host_node->schedule_table[x];

                packet_t pkt = (packet_t)
                    link_dequeue(host_node->link[dst_index]);

                //buffer the pkt to make updates at the end of timeslot
                int16_t idx = i - params->start;
                rx_update_buffer[tid][idx].dst_index = dst_index;
                rx_update_buffer[tid][idx].pkt = pkt;

            } else {
                //buffer the pkt to make updates at the end of timeslot
                int16_t idx = i - params->start;
                rx_update_buffer[tid][idx].dst_index = -1;
                rx_update_buffer[tid][idx].pkt = NULL;
            }
        }

        //barrier synchronizaton epilogue
        pthread_mutex_lock(&working_mutex);
        --working;

        //checking if there are any active flows on this thread
        int16_t finished = 1;
        thread_job_finished[tid] = 0;

        for (int16_t i = params->start; i < params->end; ++i) {
            if (nodes[i]->num_of_active_host_flows > 0) {
                finished = 0;
                break;
            }
        }
        if (finished) thread_job_finished[tid] = 1;

        if (working == 0) { //all threads finished for curr timeslot
            arrived = 0;

            if( static_workload == 1){
                if (flow_trace_scanned_completely
                    && time_to_start_logging == INT64_MAX) {
                    time_to_start_logging = curr_timeslot + (10 * (NUM_OF_NODES-1));
                }

                if (curr_timeslot == time_to_start_logging) {
                    start_logging = 1;
                    printf("Started logging at epoch = %ld\n", curr_epoch);
                    fflush(stdout);
                }
            }

            finished = 1;
            for (int16_t i = 0; i < NUM_OF_THREADS; ++i) {
                if (thread_job_finished[i] != 1) {
                    finished = 0;
                    break;
                }
            }
            if (finished && flow_trace_scanned_completely) terminate = 1;

            int64_t total = 0;
            for (int8_t i = 0; i < NUM_OF_THREADS; ++i) {
                total += num_of_flows_finished[i];
            }
            if (total >= ttl_num_flows_in_sim) terminate1 = 1;

            ++curr_timeslot;
            if (curr_timeslot % (NUM_OF_NODES-1) == 0) {
                ++curr_epoch;
                if (curr_epoch % 10 == 0) {
                    total_flows_started += flows_started_in_epoch;
                    flows_started_in_epoch = 0;
                    int count = 0;
                    int count1 = 0;
                    for (int16_t j = 0; j < NUM_OF_NODES; ++j) {
                        count += nodes[j]->num_of_active_host_flows;
                    }
                    for (int16_t j = 0; j < NUM_OF_NODES; ++j) {
                        count1 += nodes[j]->curr_num_of_sending_nodes;
                    }
                    printf("epoch = %ld active app flows = %d ", curr_epoch, count);
                    printf("active net flows = %d ", count1);
                    printf("finished flows = %ld\n", total);

                    print_system_tput();
                }
            }

            read_from_tracefile();

            pthread_cond_broadcast(&working_cv);

        } else { //some threads are still working in the curr timeslot
            while (working > 0) {
                pthread_cond_wait(&working_cv, &working_mutex);
            }
        }

        if (run_till_max_epoch && curr_timeslot
                == (max_epochs_to_run * (NUM_OF_NODES-1))) {

            terminate2 = 1;
        }

        //Termination condition - 1
        if (terminate || terminate1 || terminate2) {
            pthread_mutex_unlock(&working_mutex);
            pthread_exit(NULL);
        } else {
            pthread_mutex_unlock(&working_mutex);
        }

        //update rx nodes here
        for (int16_t i = 0; i < params->end - params->start; ++i) {
            int16_t dst_index = rx_update_buffer[tid][i].dst_index;
            if (dst_index == -1) continue;
            node_t dst_node = nodes[rx_update_buffer[tid][i].dst_index];
            packet_t pkt = rx_update_buffer[tid][i].pkt;

            if (dst_node->curr_num_of_sending_nodes > 0) {
                ++(dst_node->stat.total_time_active);
            }

            assert(pkt != NULL);

            ++(dst_node->stat.pkt_received);

#ifdef debug
            //if ((pkt->src_mac == 484 && pkt->dst_mac == 298)
            //    || (pkt->src_mac == 298 && pkt->dst_mac == 484)) {
            if (pkt->dst_mac == 15) {
                printf("[%ld/%ld] %d RECEIVED PKT FROM %d (%d->%d) <%d, %d>\n",
                        curr_timeslot-1, curr_epoch, pkt->dst_mac, pkt->src_mac,
                        pkt->src_ip, pkt->dst_ip,
                        pkt->queue_len_prev,
                        pkt->queue_len_curr);
            }
#endif
            //Update host flow queues
            int16_t flow_dst_sent
                = dst_node->flow_dst_sent_in_curr_timeslot;

            int16_t temp1 = -1;
            int16_t temp2 = -1;
            for (int16_t i = 0; i < NUM_OF_NODES-1; ++i) {
                if (nodes[pkt->dst_mac]->schedule_table[i] == pkt->src_mac) {
                    temp1 = i;
                }
                if (nodes[pkt->src_mac]->schedule_table[i] == pkt->dst_mac) {
                    temp2 = i;
                }
            }

            if (temp1 != temp2) {
                flow_dst_sent = dst_node->last_pkt_sent[pkt->src_mac];
            }

            int32_t size = arraylist_size
                (dst_node->host_flow_queue[pkt->src_mac]);

            int8_t found = 0;
            for (int32_t j = 0; j < size; ++j) {
                host_flow_queue_element_t e = (host_flow_queue_element_t)
                    arraylist_get
                        (dst_node->host_flow_queue[pkt->src_mac], j);

                int16_t flow_dst_index = e->dst_index;

                if (flow_dst_index
                        == dst_node->last_to_last_pkt_sent[pkt->src_mac]) {

                    found = 1;

                    if (dst_node->host_pkt_allocated
                            [pkt->src_mac][flow_dst_index] == 0) {

                        if (flow_dst_index == pkt->src_mac) {
                            assert(pkt->queue_len_prev == 0);
                        }

                        e->throttle_value = pkt->queue_len_prev
                            - subtract_one(dst_index,
                                           pkt->src_mac,
                                           flow_dst_index,
                                           (flow_dst_index == flow_dst_sent)
                                                ? 1 : 0,
                                           pkt->queue_len_prev);
                        assert(e->throttle_value >= 0);
                    }

                    break;
                }
            }

            if (found == 0 && dst_node->last_to_last_pkt_sent[pkt->src_mac]!=-1) {
                int16_t flow_dst_index
                    = dst_node->last_to_last_pkt_sent[pkt->src_mac];

                if (dst_node->host_pkt_allocated
                        [pkt->src_mac][flow_dst_index] == 0) {

                    dst_node->last_throttle_value[pkt->src_mac][flow_dst_index]
                        = pkt->queue_len_prev
                                - subtract_one(dst_index,
                                               pkt->src_mac,
                                               flow_dst_index,
                                               (flow_dst_index == flow_dst_sent)
                                                    ? 1 : 0,
                                               pkt->queue_len_prev);
#ifdef debug
                    if (pkt->src_mac == 330 && dst_index == 361) {
                        printf("[%ld/%ld] temp_pri[%d][%d] = %d\n",
                                curr_timeslot-1, curr_epoch,
                                pkt->src_mac,
                                flow_dst_index,
                                dst_node->last_throttle_value
                                    [pkt->src_mac][flow_dst_index]);
                    }
#endif
                }
            }

            found = 0;
            for (int32_t j = 0; j < size; ++j) {
                host_flow_queue_element_t e = (host_flow_queue_element_t)
                    arraylist_get
                        (dst_node->host_flow_queue[pkt->src_mac], j);

                int16_t flow_dst_index = e->dst_index;

                if (flow_dst_index
                        == dst_node->last_pkt_sent[pkt->src_mac]) {

                    found = 1;

                    if (dst_node->host_pkt_allocated
                            [pkt->src_mac][flow_dst_index] == 0) {

                        if (flow_dst_index == pkt->src_mac) {
                            assert(pkt->queue_len_curr == 0);
                        }

                        e->throttle_value = pkt->queue_len_curr
                            - subtract_one(dst_index,
                                           pkt->src_mac,
                                           flow_dst_index,
                                           (flow_dst_index == flow_dst_sent)
                                                ? 1 : 0,
                                           pkt->queue_len_curr);
                        assert(e->throttle_value >= 0);
                    }

                    break;
                }
            }

            if (found == 0 && dst_node->last_pkt_sent[pkt->src_mac] != -1) {
                int16_t flow_dst_index
                    = dst_node->last_pkt_sent[pkt->src_mac];

                if (dst_node->host_pkt_allocated
                        [pkt->src_mac][flow_dst_index] == 0) {

                    dst_node->last_throttle_value[pkt->src_mac][flow_dst_index]
                        = pkt->queue_len_curr
                                - subtract_one(dst_index,
                                               pkt->src_mac,
                                               flow_dst_index,
                                               (flow_dst_index == flow_dst_sent)
                                                    ? 1 : 0,
                                               pkt->queue_len_curr);
#ifdef debug
                    if (pkt->src_mac == 330 && dst_index == 361) {
                        printf("[%ld/%ld] temp_pri[%d][%d] = %d\n",
                                curr_timeslot-1, curr_epoch,
                                pkt->src_mac,
                                flow_dst_index,
                                dst_node->last_throttle_value
                                    [pkt->src_mac][flow_dst_index]);
                    }
#endif
                }
            }

            //the pkt has either reached it's dst OR it is a dummy pkt
            if (pkt->dst_ip == dst_index || pkt->dst_ip == -1) {

                //if failed node, should only receive dummy packet
                if (dst_index < percentage_failed_nodes*NUM_OF_NODES) {
                    assert(pkt->dst_ip == -1);
                }

                dst_node->last_to_last_pkt_recvd[pkt->src_mac]
                    = dst_node->last_pkt_recvd[pkt->src_mac];
                if (pkt->dst_ip == -1) {
                    dst_node->last_pkt_recvd[pkt->src_mac]
                        = -1;
                } else {
                    dst_node->last_pkt_recvd[pkt->src_mac]
                        = dst_index;
                }

#ifdef debug
                if (pkt->src_mac == 261 && pkt->dst_mac == 5) {
                    printf("[%ld] %d UPDATED REC TO <%d, %d>\n",
                            curr_timeslot-1, dst_index,
                            dst_node->last_to_last_pkt_recvd[pkt->src_mac],
                            dst_node->last_pkt_recvd[pkt->src_mac]);
                }
#endif

                if (pkt->dst_ip == -1 && dst_node->curr_num_of_sending_nodes > 0) {
                    ++(dst_node->stat.dummy_pkt_received);
                }

                if (pkt->dst_ip == dst_index) {

                    //re-ordering buffer
                    if (pkt->seq_num != dst_node->curr_seq_num[pkt->src_ip]) {
                        //add to re-order buffer
                        int64_t* x = (int64_t*) malloc(sizeof(int64_t));
                        *x = pkt->seq_num;
                        arraylist_add(dst_node->re_order_buffer[pkt->src_ip], x);
                        int64_t size = arraylist_size
                            (dst_node->re_order_buffer[pkt->src_ip]);
                        if (size > dst_node->max_re_order_buffer_size) {
                            dst_node->max_re_order_buffer_size = size;
                        }

                    } else {
                        //start freeing packets from the re-order buffer
                        ++(dst_node->curr_seq_num[pkt->src_ip]);
                        int64_t prev_seq_num = -1;
                        while (dst_node->curr_seq_num[pkt->src_ip]!=prev_seq_num) {
                            prev_seq_num = dst_node->curr_seq_num[pkt->src_ip];
                            int64_t size = arraylist_size
                                (dst_node->re_order_buffer[pkt->src_ip]);
                            for (int j = 0; j < size; ++j) {
                                int64_t* x = (int64_t*) arraylist_get
                                    (dst_node->re_order_buffer[pkt->src_ip], j);
                                if (*x == dst_node->curr_seq_num[pkt->src_ip]) {
                                    ++(dst_node->curr_seq_num[pkt->src_ip]);
                                    arraylist_remove
                                        (dst_node->re_order_buffer[pkt->src_ip],j);
                                    free(x);
                                    break;
                                }
                            }
                        }

                    }

                    if (dst_node->curr_num_of_sending_nodes > 0) {
                        ++(dst_node->stat.host_pkt_received);
                    }

#ifdef debug
                    if (dst_index == 1) {
                        printf("[%ld/%ld] RECEIVED PKT FROM %d flow %ld app %ld\n",
                                curr_timeslot-1, curr_epoch,
                                pkt->src_mac, pkt->flow_id,
                                pkt->app_id);
                    }
#endif
                    flow_recv_t dst_flow = dst_node->dst_flows[pkt->src_ip];

                    //find the recv stat logger corres to curr app level flow
                    int8_t found = 0;
                    flow_stat_logger_receiver_t r;
                    int64_t r_index;
                    arraylist_t r_list
                        = dst_flow->flow_stat_logger_receiver_list;
                    int64_t size = arraylist_size(r_list);

                    for (int16_t j = 0; j < size; ++j) {
                        flow_stat_logger_receiver_t temp
                            = (flow_stat_logger_receiver_t)
                                arraylist_get(r_list, j);
                        if (temp->flow_id == pkt->flow_id
                            && temp->app_id == pkt->app_id) {
                            found = 1;
                            r = temp;
                            r_index = j;
                            break;
                        }
                    }
                    if (found == 0) {
                        printf("(%d -> %d) flow %ld app %ld\n",
                                pkt->src_ip, pkt->dst_ip, pkt->flow_id,
                                pkt->app_id);
                        fflush(stdout);
                    }
                    assert(found == 1);

                    if( static_workload == 1) {
                        if (start_logging) {
                             ++(r->pkt_recvd_since_logging_started);
                        }
                    }

                    if (r->pkt_recvd == 0) { //first pkt recvd
                        r->time_first_pkt_recvd = curr_timeslot - 1;
                    }

                    ++(r->pkt_recvd);

                    if (r->pkt_recvd == r->app_flow_size) { //last pkt recvd

                        //if (r->app_flow_size >= 18725) {
                            --(dst_node->curr_num_of_sending_nodes);
                        //}
#ifdef debug
                        printf("[%ld] *** (%d -> %d) app %ld flow-id %ld ended,\
                                size = %ld ***\n",
                                curr_timeslot-1, pkt->src_ip,
                                pkt->dst_ip, r->app_id, r->flow_id,
                                r->app_flow_size);
#endif
                        r->time_last_pkt_recvd = curr_timeslot - 1;

                        flow_stats_t fstat = (flow_stats_t)
                            malloc(sizeof(struct flow_stats));
                        MALLOC_TEST(fstat, __LINE__);

                        node_t src_node = nodes[pkt->src_ip];
                        pthread_spin_lock(&update_active_flows[pkt->src_ip]);
                        --(src_node->num_of_active_host_flows);
                        pthread_spin_unlock(&update_active_flows[pkt->src_ip]);

                        //log all the completion times
                        flow_send_t src_flow
                            = src_node->host_flows[dst_index];

                        found = 0;
                        flow_stat_logger_sender_t s;
                        flow_stat_logger_sender_t s_list
                            = src_flow->flow_stat_logger_sender_list;

                        for (int16_t j = 0; j < MAX_FLOW_ID; ++j) {
                            if (s_list[j].flow_id == pkt->flow_id) {
                                found = 1;
                                s = &(s_list[j]);
                                break;
                            }
                        }
                        assert(found == 1);

                        arraylist_t app_list
                            = s->flow_stat_logger_sender_app_list;
                        int64_t app_list_size = arraylist_size(app_list);

                        found = 0;
                        flow_stat_logger_sender_app_t app;
                        int64_t app_index;

                        for (int64_t j = 0; j < app_list_size; ++j) {
                            flow_stat_logger_sender_app_t temp
                                = (flow_stat_logger_sender_app_t)
                                    arraylist_get(app_list, j);
                            if (temp->app_id == pkt->app_id) {
                                found = 1;
                                app = temp;
                                app_index = j;
                                break;
                            }
                        }
                        assert(found == 1);

                        //if (app->app_id < 500000) {
                            num_of_flows_finished[tid] += 1;

                            *fstat = (struct flow_stats) {
                                .src = dst_flow->src,
                                .dst = dst_flow->dst,
                                .flow_size = r->app_flow_size,
                                .sender_completion_time_1
                                    = (app->time_last_pkt_sent
                                        - app->time_app_flow_created + 1),
                                .sender_completion_time_2
                                    = (app->time_last_pkt_sent
                                        - app->time_first_pkt_sent + 1),
                                .receiver_completion_time
                                    = (r->time_last_pkt_recvd
                                        - r->time_first_pkt_recvd + 1),
                                .sender_receiver_completion_time
                                    = (r->time_last_pkt_recvd
                                        - app->time_first_pkt_sent + 1),
                                .actual_completion_time
                                    = (r->time_last_pkt_recvd
                                        - app->time_app_flow_created + 1)
                            };

                            pthread_spin_lock
                                (&update_active_flows[pkt->src_ip]);

                            arraylist_add
                                (src_node->stat.flow_stat_list, fstat);

                            pthread_spin_unlock
                                (&update_active_flows[pkt->src_ip]);
                        //}

                        //invalidating the entries
                        arraylist_remove(r_list, r_index);
                        arraylist_remove(app_list, app_index);

                        //network level flow has ended
                        if (arraylist_size(app_list) == 0) {
                            s->flow_id = -1;

                            flow_send_t fs = src_node->host_flows[dst_index];
                            --(fs->num_flow_in_progress);
                            if (fs->num_flow_in_progress == 0) {
                                --(dst_node->stat.curr_incast_degree);
                            }
                        }

                    }
                }

                free_packet(pkt);

            } else { //put the pkt in the FWD buffer
                //should not receive packet destined to a failed node
                assert(pkt->dst_ip >= percentage_failed_nodes*NUM_OF_NODES);
                if (dst_node->curr_num_of_sending_nodes > 0) {
                    ++(dst_node->stat.non_host_pkt_received);
                }
                bounded_buffer_put(dst_node->fwd_buffer[pkt->dst_ip], pkt);
                assert(pkt->src_mac == pkt->src_ip);
                dst_node->last_to_last_pkt_recvd[pkt->src_mac]
                    = dst_node->last_pkt_recvd[pkt->src_mac];
                dst_node->last_pkt_recvd[pkt->src_mac]
                    = pkt->dst_ip;

                ++(dst_node->fwd_pkt_allocated[pkt->dst_ip][pkt->src_ip]);
//#ifdef debug
                if (dst_node->fwd_pkt_allocated[pkt->dst_ip][pkt->src_ip] != 1) {
                    printf("[%ld/%ld] %d (%d -> %d, %ld) at %d\n", curr_timeslot,
                            curr_epoch,
                            dst_node->fwd_pkt_allocated[pkt->dst_ip][pkt->src_ip],
                            pkt->src_ip, pkt->dst_ip, pkt->flow_id, pkt->dst_mac);
                    int32_t size = bounded_buffer_num_of_elements
                        (dst_node->fwd_buffer[pkt->dst_ip]);
                    for (int32_t k = 0; k < size; ++k) {
                        packet_t p = (packet_t) bounded_buffer_peek
                            (dst_node->fwd_buffer[pkt->dst_ip], k);
                        if (p->src_ip == pkt->src_ip && p->dst_ip == pkt->dst_ip) {
                            printf("[%ld/%ld] DUP PKT (%d -> %d, %ld)",
                                    curr_timeslot-1, curr_epoch,
                                    p->src_ip, p->dst_ip, p->flow_id);
                            break;
                        }
                    }
                }
//#endif
                assert(dst_node
                        ->fwd_pkt_allocated[pkt->dst_ip][pkt->src_ip] == 1);

#ifdef debug
                if (pkt->src_mac == 393 && pkt->dst_mac == 137) {
                    printf("[%ld] %d UPDATED REC TO <%d, %d>\n",
                            curr_timeslot-1, dst_index,
                            dst_node->last_to_last_pkt_recvd[pkt->src_mac],
                            dst_node->last_pkt_recvd[pkt->src_mac]);
                }
#endif
            }

        }

    }

    return NULL;
}

static inline void time_elapsed(uint32_t sec)
{
    uint32_t hour = sec/3600;
    uint32_t min = (sec % 3600)/60;
    sec = (sec % 3600) % 60;
    printf("\nTime elapsed = %u:%u:%u\n", hour, min, sec);
    fflush(stdout);
}

static inline void log_active_flows()
{
    for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
        for (int16_t j = 0; j < NUM_OF_NODES; ++j) {
            arraylist_t r_list
                = nodes[i]->dst_flows[j]->flow_stat_logger_receiver_list;
            assert(i == nodes[i]->dst_flows[j]->dst);
            int64_t size = arraylist_size(r_list);

            for (int16_t k = 0; k < size; ++k) {
                long time_active;
                flow_stat_logger_receiver_t r
                    = (flow_stat_logger_receiver_t) arraylist_get(r_list, k);
                if( static_workload == 1){
                    time_active = curr_timeslot - time_to_start_logging;
                } else{
                    time_active = curr_timeslot - r->time_app_created;
                }
                double throughput = 0;
                if (time_active > 0) {
                    if( static_workload == 1){
                        throughput = ((double)r->pkt_recvd_since_logging_started
                            / (double)time_active) * link_bandwidth;
                    } else{
                        throughput = ((double)r->pkt_recvd / (double)time_active)
                            * link_bandwidth;
                    }
                }

                if (static_workload == 1) {
                    fprintf(out, "(%d->%d) %ld/%ldpkt %ld, 1/1us/1Gbps, "
                        "1/1us/1Gbps, 1/1us/1Gbps, 1/1us/1Gbps, "
                        "%ld/%0.3lfus/%0.3lfGbps\n",
                        nodes[i]->dst_flows[j]->src,
                        nodes[i]->dst_flows[j]->dst,
                        nodes[j]->host_flows[i]->pkt_transmitted,
                        r->pkt_recvd_since_logging_started, r->app_id, time_active,
                        (time_active * slot_len * 1e-3), throughput);

                } else {
                   fprintf(out, "(%d->%d) %ldpkt %ldpkt, "
                            "1/1us/1Gbps, 1/1us/1Gbps, "
                            "1/1us/1Gbps, 1/1us/1Gbps, %ld/%0.3lfus/%0.3lfGbps\n",
                        nodes[i]->dst_flows[j]->src,
                        nodes[i]->dst_flows[j]->dst,
                        r->app_flow_size,
                        r->pkt_recvd,
                        //r->app_id,
                        time_active,
                        (time_active * slot_len * 1e-3),
                        throughput
                            * (((double)packet_size - (double)packet_overhead)
                                / (double)packet_size)
                        );
                }
            }
        }
    }
}

static void print_summary_stats()
{
    int64_t max_queuing = 0;
    int payload = (packet_size - packet_overhead)*8;
    for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
        arraylist_t fstat_list = nodes[i]->stat.flow_stat_list;
        int64_t len = arraylist_size(fstat_list);
        for (int64_t j = 0; j < len; ++j) {
            flow_stats_t fstat = (flow_stats_t) arraylist_get(fstat_list, j);
            double completion_time_1
                = fstat->sender_completion_time_1 * slot_len; //TIMESLOT_LEN;
            double goodput_1 = (fstat->flow_size * payload)/completion_time_1;
            double completion_time_2
                = fstat->sender_completion_time_2 * slot_len; //TIMESLOT_LEN;
            double goodput_2 = (fstat->flow_size * payload)/completion_time_2;
            double completion_time_3
                = fstat->receiver_completion_time * slot_len; //TIMESLOT_LEN;
            double goodput_3 = (fstat->flow_size * payload)/completion_time_3;
            double completion_time_4
                = fstat->sender_receiver_completion_time * slot_len; //TIMESLOT_LEN;
            double goodput_4 = (fstat->flow_size * payload)/completion_time_4;
            double completion_time_5
                = fstat->actual_completion_time * slot_len; //TIMESLOT_LEN;
            double goodput_5 = (fstat->flow_size * payload)/completion_time_5;

            fprintf(out, "(%d->%d) %ldpkt, %ld/%0.3lfus/%0.3lfGbps, %ld/%0.3lfus/%0.3lfGbps, %ld/%0.3lfus/%0.3lfGbps, %ld/%0.3lfus/%0.3lfGbps, %ld/%0.3lfus/%0.3lfGbps\n", fstat->src, fstat->dst, fstat->flow_size, fstat->sender_completion_time_1, completion_time_1 * 1e-3, goodput_1, fstat->sender_completion_time_2, completion_time_2 * 1e-3, goodput_2, fstat->receiver_completion_time, completion_time_3 * 1e-3, goodput_3, fstat->sender_receiver_completion_time, completion_time_4 * 1e-3, goodput_4, fstat->actual_completion_time, completion_time_5 * 1e-3, goodput_5);

        }

        //printf("Max queuing at node %d = %ld\n", i, nodes[i]->stat.max_queuing);
        int64_t curr_node_queuing = nodes[i]->stat.max_queuing;
        if (curr_node_queuing > max_queuing) {
            max_queuing = curr_node_queuing;
        }
    }

    printf("\nMax queuing across all nodes = %ld\n", max_queuing);

    log_active_flows();

    fclose(out);

    print_system_tput();

    if (curr_epoch > 0) {
        printf("\nAvg number of flows started per epoch = %lf\n",
                (double)total_flows_started / (double)curr_epoch);
    }

    int16_t max_queue_len=0;
    int16_t _999_percentile=0;
    int16_t _99_percentile=0;
    int16_t _95_percentile=0;
    int16_t _90_percentile=0;

    int64_t agg_histogram[FWD_BUFFER_LEN] = {0};
#ifdef AGG_NODE_QUEUING
    int64_t agg_ttl_histogram[MAX_NODE_BUFFER_LEN] = {0};
#endif

    for (int16_t j = 0; j < FWD_BUFFER_LEN; ++j) {
        for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
            agg_histogram[j] += nodes[i]->stat.queue_len_histogram[j];
        }
        if (agg_histogram[j] != 0)
            printf("agg_queue_histogram[%d] = %ld\n", j, agg_histogram[j]);
    }

#ifdef AGG_NODE_QUEUING
   for (int64_t j = 0; j < MAX_NODE_BUFFER_LEN; ++j) {
        for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
            agg_ttl_histogram[j] += nodes[i]->stat.ttl_queue_len_histogram[j];
        }
        if (agg_ttl_histogram[j] != 0)
            printf("agg_ttl_queue_histogram[%ld] = %ld\n", j, agg_ttl_histogram[j]);
    }
#endif

    for (int16_t i = 0; i < FWD_BUFFER_LEN; ++i) {
        if (agg_histogram[i] != 0) {
            max_queue_len = i;
        }
        if (i != 0) agg_histogram[i] += agg_histogram[i-1];
    }

    int64_t total = agg_histogram[FWD_BUFFER_LEN-1];
    double w = 0.999 * total;
    double x = 0.99 * total;
    double y = 0.95 * total;
    double z = 0.90 * total;

    for (int16_t i = FWD_BUFFER_LEN-1; i >= 0; --i) {
        if (w < agg_histogram[i]) {
            _999_percentile = i;
        }
        if (x < agg_histogram[i]) {
            _99_percentile = i;
        }
        if (y < agg_histogram[i]) {
            _95_percentile = i;
        }
        if (z < agg_histogram[i]) {
            _90_percentile = i;
        }
    }

    printf("\n********** FIFO QUEUE LEN **********\n");
    printf("90th percentile = %d\n", _90_percentile);
    printf("95th percentile = %d\n", _95_percentile);
    printf("99th percentile = %d\n", _99_percentile);
    printf("99.9th percentile = %d\n", _999_percentile);
    printf("Maximum = %d\n", max_queue_len);

    int64_t max_re_ordering = 0;
    for (int i = 0; i < NUM_OF_NODES; ++i) {
        if (nodes[i]->max_re_order_buffer_size > max_re_ordering) {
            max_re_ordering = nodes[i]->max_re_order_buffer_size;
        }
    }
    printf("\nMax re-ordering = %ld cells\n", max_re_ordering);

    printf("\n********** MAX INCAST AT EACH NODE **********\n");
    printf("[");
    for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
        printf("%d, ", nodes[i]->stat.max_incast_degree);
    }
    printf("]\n");

}

static inline void usage()
{
    printf("\nError: -f <filename> does not exist;"
        " filename must be < 5000 char long\n");
    exit(1);
}

int main(int argc, char** argv)
{
    //parse command-line arguments
    int c;
    char filename[5000] = "";
    add_host_flows_t func = NULL;
    char out_filename[5000] = "";

    while ((c = getopt(argc, argv, "w:h:c:t:b:e:f:n:d:i:")) != -1) {
        switch(c) {
            case 'w': static_workload=atoi(optarg);
                      if(static_workload == 0){
                         printf("Running a non-static workload file!\n");
                      } else{
                         printf("Running a static workload file!\n");
                      }
                      break;
            case 'h': packet_overhead = atoi(optarg);
                      printf("Using packet overhead of %d bytes\n",packet_overhead);
                      break;
            case 'd': percentage_failed_nodes = (atof(optarg))/100.0;
                      printf("Percentage failed nodes is %f\n",
                              percentage_failed_nodes);
                      break;
            case 'c': packet_size = atoi(optarg);
                      printf("A packet is of size: %d bytes\n", packet_size);
                      break;
            case 'i': interval = atoi(optarg);
                      printf("Scheduling interval: %d timeslots\n", interval);
                      break;
            case 'n': ttl_num_flows_in_sim = atol(optarg);
                      printf("Stop after %ld flows have finished\n",
                              ttl_num_flows_in_sim);
                      break;
            case 't': slot_len = atof(optarg);
                      printf("Running with a slot time of: %f with guardband: %f\n",
                              slot_len, 1.1*slot_len);
                      break;
            case 'b': link_bandwidth = atof(optarg);
                      printf("Running with a link bandwidth of: %f\n",
                              link_bandwidth);
                      break;
            case 'e': max_epochs_to_run = atoi(optarg);
                      if (max_epochs_to_run < 0) {
                          usage();
                      } else if (max_epochs_to_run != 0) {
                          run_till_max_epoch = 1;
                          printf("\nRunning till max epoch = %d\n",
                                  max_epochs_to_run);
                      }
                      break;
            case 'f': if (strlen(optarg) < 5000)
                          strcpy(filename, optarg);
                      else
                          usage();
                      func = tracefile;
                      flow_trace_scanned_completely = 0;
                      break;
            default: usage();
        }
    }

    // Calculate actual throughput we could get using this slot time + guardband
    float new_slot = 1.1*slot_len;
    float old_band = link_bandwidth;
    link_bandwidth = link_bandwidth*(slot_len/new_slot);
    printf("Thought we had %fGbps but actually have %fGbps (baurdband)",
            old_band,link_bandwidth);
    slot_len = new_slot;

    int fd;
    struct stat fstat;
    char* saved_ptr;
    if (strcmp(filename, "")) {
        fd = open(filename, O_RDONLY);
        if (fd == -1) {
            perror("open");
            usage();
        } else {
            if (stat(filename, &fstat) == -1) {
                perror("stat");
                exit(1);
            }

            ptr = mmap((caddr_t)0, fstat.st_size, PROT_READ, MAP_SHARED, fd, 0);
            if (ptr == (caddr_t)-1) {
                perror("mmap");
                exit(1);
            }
            saved_ptr = ptr;

            read_from_tracefile();
            strcpy(out_filename, filename);
            strcat(out_filename, ".out");
            out = fopen(out_filename, "w");
        }
    } else {
        usage();
    }

    cpu_set_t cpuset;

    struct timeval tv1;
    struct timeval tv2;

    gettimeofday(&tv1, 0);

    pthread_mutex_init(&arrived_mutex, NULL);
    pthread_cond_init(&arrived_cv, NULL);
    pthread_mutex_init(&working_mutex, NULL);
    pthread_cond_init(&working_cv, NULL);

    initialize_global_schedule_table(NULL);

    //create nodes
    nodes = (node_t*) malloc(NUM_OF_NODES * sizeof(node_t));
    MALLOC_TEST(nodes, __LINE__);
    for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
        nodes[i] = create_node(i, global_schedule_table[i]);
        pthread_spin_init(&update_active_flows[i], 0);
        pthread_spin_init(&incast_degree_lock[i], 0);
    }

    pthread_t threads[NUM_OF_THREADS];

    for (int16_t i = 0; i < NUM_OF_THREADS; ++i) {
        int16_t s = i * (NUM_OF_NODES / NUM_OF_THREADS);
        int16_t e = s + (NUM_OF_NODES / NUM_OF_THREADS);
        if (i == NUM_OF_THREADS - 1) {
            e = NUM_OF_NODES;
        }

        rx_update_buffer[i] = (rx_update_t)
            malloc((e - s) * sizeof(struct rx_update));
        MALLOC_TEST(rx_update_buffer[i], __LINE__);

        thread_params_t arg =
            (thread_params_t) malloc(sizeof(struct thread_params));
        MALLOC_TEST(arg, __LINE__);
        *arg = (struct thread_params) {
            .tid = i,
            .start = s,
            .end = e,
            .add_host_flows = func,
        };
        int rc = pthread_create(&threads[i], NULL, work_per_timeslot, arg);
        if (rc) {
            perror("pthread_create");
            exit(1);
        }

        CPU_ZERO(&cpuset);
        CPU_SET((i % NUM_OF_CORES), &cpuset);
        pthread_setaffinity_np(threads[i], sizeof(cpu_set_t), &cpuset);
    }

    for (int16_t i = 0; i < NUM_OF_THREADS; ++i) {
        pthread_join(threads[i], NULL);
    }

    print_summary_stats();

    for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
        free_node(nodes[i]);
        pthread_spin_destroy(&update_active_flows[i]);
        pthread_spin_destroy(&incast_degree_lock[i]);
    }

    free_global_schedule_table();

    pthread_mutex_destroy(&arrived_mutex);
    pthread_cond_destroy(&arrived_cv);
    pthread_mutex_destroy(&working_mutex);
    pthread_cond_destroy(&working_cv);

    if (munmap(saved_ptr, fstat.st_size) == -1) {
        perror("unmap");
        exit(1);
    }

    close(fd);

    printf("\nAll done..\n");

    gettimeofday(&tv2, 0);
    time_elapsed(tv2.tv_sec - tv1.tv_sec);
    printf("\n");

    return 0;
}
