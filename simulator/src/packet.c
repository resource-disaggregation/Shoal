#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#include "packet.h"

#define MALLOC_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d malloc() failed\n", __FILE__, line_num); \
        exit(0);}

packet_t create_packet(int16_t src_mac, int16_t dst_mac,
        int16_t src_ip, int16_t dst_ip, int64_t id, int64_t seq_num)
{
    packet_t self = (packet_t) malloc(sizeof(struct packet));
    MALLOC_TEST(self, __LINE__);
    self->src_mac = src_mac;
    self->dst_mac = dst_mac;
    self->src_ip = src_ip;
    self->dst_ip = dst_ip;
    self->flow_id = id;
    self->seq_num = seq_num;
    return self;
}

void free_packet(packet_t self)
{
    if (self != NULL) free(self);
}
