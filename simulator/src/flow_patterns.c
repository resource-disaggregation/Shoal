#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <assert.h>
#include <pthread.h>

#include "flow_patterns.h"
#include "queue_add_remove.h"

#define MALLOC_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d malloc() failed\n", __FILE__, line_num); \
        exit(0);}

struct tracefile_data {
    long flow_id;
    long timeslot;
    int src;
    int dst;
    int flow_size;
};

int16_t len = 0;
struct tracefile_data temp; //buffer for the 1st flow for the next timeslot.
int8_t buffer_data_present = 0;
struct tracefile_data flow_list[NUM_OF_NODES]; //stores the list of flows to be
                                               //started in curr timeslot.
pthread_spinlock_t update_incast_degree_lock[NUM_OF_NODES];
pthread_spinlock_t flow_count_lock;
int first = 1;

void read_from_tracefile()
{
    int16_t i = 0;
    int src, dst, flow_size;
    long flow_id, timeslot;

    if (first == 1) {
        first = 0;
        for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
            pthread_spin_init(&update_incast_degree_lock[i], 0);
        }
        pthread_spin_init(&flow_count_lock, 0);
    }

    len = 0;

    if (!flow_trace_scanned_completely && buffer_data_present) {
        if (curr_timeslot == temp.timeslot) {
            flow_list[i] = (struct tracefile_data) {
                .flow_id = temp.flow_id,
                .src = temp.src,
                .dst = temp.dst,
                .flow_size = temp.flow_size,
                .timeslot = temp.timeslot
            };

            len = ++i;
            buffer_data_present = 0;

        } else {
            return;
        }
    }

    while (!flow_trace_scanned_completely) {
        int8_t out = sscanf(ptr, "%ld,%d,%d,%d,%ld",
                &flow_id, &src, &dst, &flow_size, &timeslot);

        if (out == EOF) {
            printf("\nTrace file scanned completely\n\n");
            flow_trace_scanned_completely = 1;
            break;
        }

        if (out != 5) {
            perror("sscanf");
            exit(1);
        }

        while (*ptr != '\n') ++ptr;
        ++ptr;

        if (src == dst || src < percentage_failed_nodes*NUM_OF_NODES
                || dst < percentage_failed_nodes*NUM_OF_NODES)
            continue;

        if (timeslot == curr_timeslot) {
            flow_list[i] = (struct tracefile_data) {
                .flow_id = flow_id,
                .src = src,
                .dst = dst,
                .flow_size = flow_size,
                .timeslot = timeslot
            };

            len = ++i;

        } else {
            //buffer the data
            temp = (struct tracefile_data) {
                .flow_id = flow_id,
                .src = src,
                .dst = dst,
                .flow_size = flow_size,
                .timeslot = timeslot
            };

            buffer_data_present = 1;
            break;
        }
    }
}

void tracefile(node_t node)
{
    for (int16_t i = 0; i < len; ++i) {
        if (flow_list[i].src == node->node_index) {
            int16_t dst_flow_index = flow_list[i].dst;
            flow_send_t f = node->host_flows[dst_flow_index];
            flow_recv_t f1 = nodes[dst_flow_index]->dst_flows[node->node_index];

            ++(node->num_of_active_host_flows);

            if (f->active == 0) { //prev instance of flow has ended at sender
                //add the new flow to the first empty slot
                for (int16_t j = 0; j < MAX_FLOW_ID; ++j) {
                    if (f->flow_stat_logger_sender_list[j].flow_id == -1) {
                        f->flow_stat_logger_sender_list[j].flow_id
                            = f->curr_flow_id;

                        flow_stat_logger_sender_app_t temp
                            = (flow_stat_logger_sender_app_t)
                                malloc(sizeof(struct flow_stat_logger_sender_app));
                        MALLOC_TEST(temp, __LINE__);
                        *temp = (struct flow_stat_logger_sender_app) {
                                .app_id = flow_list[i].flow_id,
                                .app_flow_size = flow_list[i].flow_size,
                                .app_pkt_transmitted = 0,
                                .time_app_flow_created = curr_timeslot,
                                .time_first_pkt_sent = -1,
                                .time_last_pkt_sent = -1
                            };

                        arraylist_add(f->flow_stat_logger_sender_list[j]
                                .flow_stat_logger_sender_app_list, temp);

                        break;
                    }
                }

                f->flow_size = flow_list[i].flow_size;

#ifdef SHORTEST_FLOW_FIRST
                f->curr_min_flow_size = f->flow_size;
#endif

                f->active = 1;
                f->pkt_transmitted = 0;
                f->pkt_received = 0;

                add_flow_to_host_flow_queues(node, f->dst);

#ifdef debug
                printf("[%ld] (%d -> %d) started, size = %ld\n",
                        curr_timeslot, f->src, f->dst, f->flow_size);
#endif

                pthread_spin_lock(&flow_count_lock);
                ++flows_started_in_epoch;
                pthread_spin_unlock(&flow_count_lock);

                ++(node->num_of_active_network_host_flows);

                //if (flow_list[i].flow_size >= 18725) {
                    pthread_spin_lock(&update_incast_degree_lock[dst_flow_index]);
                    ++(nodes[dst_flow_index]->curr_num_of_sending_nodes);
                    pthread_spin_unlock(&update_incast_degree_lock[dst_flow_index]);
                //}

                if (f->num_flow_in_progress == 0) {
                    pthread_spin_lock(&update_incast_degree_lock[dst_flow_index]);
                    int16_t d = ++(nodes[dst_flow_index]->stat.curr_incast_degree);
                    if (d > nodes[dst_flow_index]->stat.max_incast_degree) {
                        nodes[dst_flow_index]->stat.max_incast_degree = d;
                    }
                    pthread_spin_unlock(&update_incast_degree_lock[dst_flow_index]);
                }
                ++(f->num_flow_in_progress);


            } else {
                f->flow_size += flow_list[i].flow_size;

#ifdef SHORTEST_FLOW_FIRST
                if (flow_list[i].flow_size < f->curr_min_flow_size) {
                    f->curr_min_flow_size = flow_list[i].flow_size;
                }
#endif

                //if (flow_list[i].flow_size >= 18725) {
                    pthread_spin_lock(&update_incast_degree_lock[dst_flow_index]);
                    ++(nodes[dst_flow_index]->curr_num_of_sending_nodes);
                    pthread_spin_unlock(&update_incast_degree_lock[dst_flow_index]);
                //}

                int8_t found = 0;
                flow_stat_logger_sender_t s_list
                    = f->flow_stat_logger_sender_list;

                for (int16_t j = 0; j < MAX_FLOW_ID; ++j) {
                    if (s_list[j].flow_id == f->curr_flow_id) {
                        flow_stat_logger_sender_app_t temp
                            = (flow_stat_logger_sender_app_t)
                                malloc(sizeof(struct flow_stat_logger_sender_app));
                        MALLOC_TEST(temp, __LINE__);
                        *temp = (struct flow_stat_logger_sender_app) {
                                .app_id = flow_list[i].flow_id,
                                .app_pkt_transmitted = 0,
                                .app_flow_size = flow_list[i].flow_size,
                                .time_app_flow_created = curr_timeslot,
                                .time_first_pkt_sent = -1,
                                .time_last_pkt_sent = -1
                            };

                        arraylist_add(s_list[j].flow_stat_logger_sender_app_list,
                                temp);

                        found = 1;
                        break;
                    }
                }

                assert(found);

#ifdef debug
                printf("[%ld] UPDATE (%d -> %d) size increased by %d\n",
                    curr_timeslot, f->src, f->dst, flow_list[i].flow_size);
#endif
            }

            //always create a receive logger for each app layer flow
            flow_stat_logger_receiver_t temp = (flow_stat_logger_receiver_t)
                malloc(sizeof(struct flow_stat_logger_receiver));
            MALLOC_TEST(temp, __LINE__);
            *temp = (struct flow_stat_logger_receiver) {
                    .flow_id = f->curr_flow_id,
                    .app_id = flow_list[i].flow_id,
                    .app_flow_size = flow_list[i].flow_size,
                    .pkt_recvd = 0,
                    .time_app_created = curr_timeslot,
                    .pkt_recvd_since_logging_started = 0,
                    .time_first_pkt_recvd = -1,
                    .time_last_pkt_recvd = -1
                };

#ifdef debug
            printf("adding recv logger (%d -> %d) flow %ld app %ld\n",
                    f1->src, f1->dst, temp->flow_id, temp->app_id);
#endif

            arraylist_add(f1->flow_stat_logger_receiver_list, temp);

        }
    }
}

