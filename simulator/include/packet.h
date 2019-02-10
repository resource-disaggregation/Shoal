#ifndef __PACKET_H__
#define __PACKET_H__

#include <stdint.h>

#include "flow.h"
#include "params.h"

struct packet {
    int16_t src_mac;
    int16_t dst_mac;
    int16_t src_ip;
    int16_t dst_ip;
    int64_t flow_id;
    int64_t app_id;
    int64_t queue_len_prev;
    int64_t queue_len_curr;
    int64_t seq_num;
};

typedef struct packet* packet_t;

packet_t create_packet(int16_t, int16_t, int16_t, int16_t, int64_t, int64_t);
void free_packet(packet_t);

#endif
