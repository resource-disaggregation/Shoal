#ifndef __FLOW_H__
#define __FLOW_H__

#include <stdint.h>

#include "arraylist.h"
#include "params.h"

struct flow_stat_logger_sender_app {
    int64_t app_id;
    int64_t app_flow_size;
    int64_t app_pkt_transmitted;
    int64_t time_app_flow_created;
    int64_t time_first_pkt_sent;
    int64_t time_last_pkt_sent;
};

typedef struct flow_stat_logger_sender_app* flow_stat_logger_sender_app_t;

struct flow_stat_logger_sender {
    int64_t flow_id;
    arraylist_t flow_stat_logger_sender_app_list;
};

typedef struct flow_stat_logger_sender* flow_stat_logger_sender_t;

struct flow_params_sender {
    int8_t active; //1 as soon as flow is put on the notification fifo
                   //0 as soon as the flow ends
    int16_t num_flow_in_progress;
    int64_t flow_size;
    int64_t pkt_transmitted; //during single instance of the flow
    int64_t pkt_received;
    struct flow_stat_logger_sender flow_stat_logger_sender_list[MAX_FLOW_ID];
    int16_t src;
    int16_t dst;
    int64_t curr_flow_id;
#ifdef SHORTEST_FLOW_FIRST
    int64_t curr_min_flow_size;
#endif
};

typedef struct flow_params_sender* flow_send_t;

struct flow_stat_logger_receiver {
    int64_t flow_id;
    int64_t app_id;
    int64_t app_flow_size;
    int64_t pkt_recvd;
    int64_t time_app_created;
    int64_t pkt_recvd_since_logging_started;
    int64_t time_first_pkt_recvd;
    int64_t time_last_pkt_recvd;
};

typedef struct flow_stat_logger_receiver* flow_stat_logger_receiver_t;

struct flow_params_receiver {
    arraylist_t flow_stat_logger_receiver_list;
    int16_t src;
    int16_t dst;
};

typedef struct flow_params_receiver* flow_recv_t;

struct flow_params_short_flow {
    int16_t dst;
    struct flow_params_short_flow* next;
};

typedef struct flow_params_short_flow* short_flow_t;

flow_send_t create_host_flow(int16_t, int16_t);
flow_recv_t create_dst_flow(int16_t, int16_t);
void free_host_flow(flow_send_t);
void free_dst_flow(flow_recv_t);

#endif
