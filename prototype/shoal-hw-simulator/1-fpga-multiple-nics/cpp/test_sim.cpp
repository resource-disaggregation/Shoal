#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <stdint.h>
#include <unistd.h>

#include "ShoalMultiSimTopIndication.h"
#include "ShoalMultiSimTopRequest.h"
#include "GeneratedTypes.h"

static uint32_t server_index = 0;
static uint32_t rate = 0; //rate of cell generation
static uint32_t timeslot = 0; //timeslot length
static uint64_t cycles = 0; //num of cycles to run exp for

static uint16_t chunk_num = 8;

static ShoalMultiSimTopRequestProxy *device = 0;

class ShoalMultiSimTopIndication : public ShoalMultiSimTopIndicationWrapper
{
public:
    virtual void display_tx_port_0_stats(uint64_t sop,
                                        uint64_t eop,
                                        uint64_t blocks,
                                        uint64_t cells)
    {
        fprintf(stderr, "Port-0 (tx): sop = %ld eop = %ld blks = %ld cells = %ld\n",
                sop, eop, blocks, cells);
    }

    virtual void display_tx_port_1_stats(uint64_t sop,
                                        uint64_t eop,
                                        uint64_t blocks,
                                        uint64_t cells)
    {
        fprintf(stderr, "Port-1 (tx): sop = %ld eop = %ld blks = %ld cells = %ld\n",
                sop, eop, blocks, cells);
    }

    virtual void display_tx_port_2_stats(uint64_t sop,
                                        uint64_t eop,
                                        uint64_t blocks,
                                        uint64_t cells)
    {
        fprintf(stderr, "Port-2 (tx): sop = %ld eop = %ld blks = %ld cells = %ld\n",
                sop, eop, blocks, cells);
    }

    virtual void display_tx_port_3_stats(uint64_t sop,
                                        uint64_t eop,
                                        uint64_t blocks,
                                        uint64_t cells)
    {
        fprintf(stderr, "Port-3 (tx): sop = %ld eop = %ld blks = %ld cells = %ld\n",
                sop, eop, blocks, cells);
    }

    virtual void display_rx_port_0_stats(uint64_t sop,
                                        uint64_t eop,
                                        uint64_t blocks,
                                        uint64_t cells)
    {
        fprintf(stderr, "Port-0 (rx): sop = %ld eop = %ld blks = %ld cells = %ld\n",
                sop, eop, blocks, cells);
    }

    virtual void display_rx_port_1_stats(uint64_t sop,
                                        uint64_t eop,
                                        uint64_t blocks,
                                        uint64_t cells)
    {
        fprintf(stderr, "Port-1 (rx): sop = %ld eop = %ld blks = %ld cells = %ld\n",
                sop, eop, blocks, cells);
    }

    virtual void display_rx_port_2_stats(uint64_t sop,
                                        uint64_t eop,
                                        uint64_t blocks,
                                        uint64_t cells)
    {
        fprintf(stderr, "Port-2 (rx): sop = %ld eop = %ld blks = %ld cells = %ld\n",
                sop, eop, blocks, cells);
    }

    virtual void display_rx_port_3_stats(uint64_t sop,
                                        uint64_t eop,
                                        uint64_t blocks,
                                        uint64_t cells)
    {
        fprintf(stderr, "Port-3 (rx): sop = %ld eop = %ld blks = %ld cells = %ld\n",
                sop, eop, blocks, cells);
    }

    virtual void display_latency_port_0_stats(uint64_t t)
    {
        fprintf(stderr, "Port-0 latency = %ld\n", t);
    }

    virtual void display_latency_port_1_stats(uint64_t t)
    {
        fprintf(stderr, "Port-1 latency = %ld\n", t);
    }

    virtual void display_latency_port_2_stats(uint64_t t)
    {
        fprintf(stderr, "Port-2 latency = %ld\n", t);
    }

    virtual void display_latency_port_3_stats(uint64_t t)
    {
        fprintf(stderr, "Port-3 latency = %ld\n", t);
    }

	virtual void display_time_slots_count_p0(uint64_t count) {
		fprintf(stderr, "[P0] TIME SLOTS = %lu\n", count);
	}
	virtual void display_sent_host_pkt_count_p0(uint64_t count) {
		fprintf(stderr, "[P0] SENT HOST PKT = %lu\n", count);
	}
	virtual void display_sent_fwd_pkt_count_p0(uint64_t count) {
		fprintf(stderr, "[P0] SENT FWD PKT = %lu\n", count);
	}
	virtual void display_received_host_pkt_count_p0(uint64_t count) {
		fprintf(stderr, "[P0] RECEIVED HOST PKT = %lu\n", count);
	}
	virtual void display_received_fwd_pkt_count_p0(uint64_t count) {
		fprintf(stderr, "[P0] RECEIVED FWD PKT = %lu\n", count);
	}
	virtual void display_received_corrupted_pkt_count_p0(uint64_t count) {
		fprintf(stderr, "[P0] RECEIVED CORRUPTED PKT = %lu\n", count);
	}
	virtual void display_received_wrong_dst_pkt_count_p0(uint64_t count) {
		fprintf(stderr, "[P0] RECEIVED WRONG DST PKT = %lu\n", count);
	}
    virtual void display_num_of_blocks_transmitted_from_mac_p0(uint64_t count) {
        fprintf(stderr, "[P0] BLOCKS TRANS FROM MAC = %lu (%lu)\n", count,
                count/chunk_num);
    }
    virtual void display_num_of_blocks_received_by_mac_p0(uint64_t count) {
        fprintf(stderr, "[P0] BLOCKS RECVD BY MAC = %lu (%lu)\n", count,
                count/chunk_num);
    }
    virtual void display_latency_p0(uint64_t count) {
        fprintf(stderr, "[P0] LATENCY = %lu cycles\n", count);
    }

	virtual void display_time_slots_count_p1(uint64_t count) {
		fprintf(stderr, "\n[P1] TIME SLOTS = %lu\n", count);
	}
	virtual void display_sent_host_pkt_count_p1(uint64_t count) {
		fprintf(stderr, "[P1] SENT HOST PKT = %lu\n", count);
	}
	virtual void display_sent_fwd_pkt_count_p1(uint64_t count) {
		fprintf(stderr, "[P1] SENT FWD PKT = %lu\n", count);
	}
	virtual void display_received_host_pkt_count_p1(uint64_t count) {
		fprintf(stderr, "[P1] RECEIVED HOST PKT = %lu\n", count);
	}
	virtual void display_received_fwd_pkt_count_p1(uint64_t count) {
		fprintf(stderr, "[P1] RECEIVED FWD PKT = %lu\n", count);
	}
	virtual void display_received_corrupted_pkt_count_p1(uint64_t count) {
		fprintf(stderr, "[P1] RECEIVED CORRUPTED PKT = %lu\n", count);
	}
	virtual void display_received_wrong_dst_pkt_count_p1(uint64_t count) {
		fprintf(stderr, "[P1] RECEIVED WRONG DST PKT = %lu\n", count);
	}
    virtual void display_num_of_blocks_transmitted_from_mac_p1(uint64_t count) {
        fprintf(stderr, "[P1] BLOCKS TRANS FROM MAC = %lu (%lu)\n", count,
                count/chunk_num);
    }
    virtual void display_num_of_blocks_received_by_mac_p1(uint64_t count) {
        fprintf(stderr, "[P1] BLOCKS RECVD BY MAC = %lu (%lu)\n", count,
                count/chunk_num);
    }
    virtual void display_latency_p1(uint64_t count) {
        fprintf(stderr, "[P1] LATENCY = %lu cycles\n", count);
    }

	virtual void display_time_slots_count_p2(uint64_t count) {
		fprintf(stderr, "\n[P2] TIME SLOTS = %lu\n", count);
	}
	virtual void display_sent_host_pkt_count_p2(uint64_t count) {
		fprintf(stderr, "[P2] SENT HOST PKT = %lu\n", count);
	}
	virtual void display_sent_fwd_pkt_count_p2(uint64_t count) {
		fprintf(stderr, "[P2] SENT FWD PKT = %lu\n", count);
	}
	virtual void display_received_host_pkt_count_p2(uint64_t count) {
		fprintf(stderr, "[P2] RECEIVED HOST PKT = %lu\n", count);
	}
	virtual void display_received_fwd_pkt_count_p2(uint64_t count) {
		fprintf(stderr, "[P2] RECEIVED FWD PKT = %lu\n", count);
	}
	virtual void display_received_corrupted_pkt_count_p2(uint64_t count) {
		fprintf(stderr, "[P2] RECEIVED CORRUPTED PKT = %lu\n", count);
	}
	virtual void display_received_wrong_dst_pkt_count_p2(uint64_t count) {
		fprintf(stderr, "[P2] RECEIVED WRONG DST PKT = %lu\n", count);
	}
    virtual void display_num_of_blocks_transmitted_from_mac_p2(uint64_t count) {
        fprintf(stderr, "[P2] BLOCKS TRANS FROM MAC = %lu (%lu)\n", count,
                count/chunk_num);
    }
    virtual void display_num_of_blocks_received_by_mac_p2(uint64_t count) {
        fprintf(stderr, "[P2] BLOCKS RECVD BY MAC = %lu (%lu)\n", count,
                count/chunk_num);
    }
    virtual void display_latency_p2(uint64_t count) {
        fprintf(stderr, "[P2] LATENCY = %lu cycles\n", count);
    }

	virtual void display_time_slots_count_p3(uint64_t count) {
		fprintf(stderr, "\n[P3] TIME SLOTS = %lu\n", count);
	}
	virtual void display_sent_host_pkt_count_p3(uint64_t count) {
		fprintf(stderr, "[P3] SENT HOST PKT = %lu\n", count);
	}
	virtual void display_sent_fwd_pkt_count_p3(uint64_t count) {
		fprintf(stderr, "[P3] SENT FWD PKT = %lu\n", count);
	}
	virtual void display_received_host_pkt_count_p3(uint64_t count) {
		fprintf(stderr, "[P3] RECEIVED HOST PKT = %lu\n", count);
	}
	virtual void display_received_fwd_pkt_count_p3(uint64_t count) {
		fprintf(stderr, "[P3] RECEIVED FWD PKT = %lu\n", count);
	}
	virtual void display_received_corrupted_pkt_count_p3(uint64_t count) {
		fprintf(stderr, "[P3] RECEIVED CORRUPTED PKT = %lu\n", count);
	}
	virtual void display_received_wrong_dst_pkt_count_p3(uint64_t count) {
		fprintf(stderr, "[P3] RECEIVED WRONG DST PKT = %lu\n", count);
	}
    virtual void display_num_of_blocks_transmitted_from_mac_p3(uint64_t count) {
        fprintf(stderr, "[P3] BLOCKS TRANS FROM MAC = %lu (%lu)\n", count,
                count/chunk_num);
    }
    virtual void display_num_of_blocks_received_by_mac_p3(uint64_t count) {
        fprintf(stderr, "[P3] BLOCKS RECVD BY MAC = %lu (%lu)\n", count,
                count/chunk_num);
    }
    virtual void display_latency_p3(uint64_t count) {
        fprintf(stderr, "[P3] LATENCY = %lu cycles\n", count);
    }
    ShoalMultiSimTopIndication(unsigned int id)
        : ShoalMultiSimTopIndicationWrapper(id) {}
};

int main(int argc, char **argv)
{
    ShoalMultiSimTopIndication echoIndication(IfcNames_ShoalMultiSimTopIndicationH2S);
    device = new ShoalMultiSimTopRequestProxy(IfcNames_ShoalMultiSimTopRequestS2H);

    int i;

    if (argc != 9) {
        printf("Wrong number of arguments\n");
        exit(0);
    } else {
        server_index = atoi(argv[4]);
        rate = atoi(argv[5]);
        timeslot = atoi(argv[6]);
        cycles = atol(argv[7]);

        chunk_num = (atoi(argv[8]) * 8) / 64;
    }

    for (i = 0; i < 3; ++i) {
        printf("********* Starting i = %d **********\n", i);
        device->startSwitching(atoi(argv[1]), atol(argv[2]));
        printf("********** Started Sw i = %d **********\n", i);
        sleep(2);
        device->start_shoal(server_index,
                            rate,
                            timeslot,
                            cycles);
        printf("********** Started NIC i = %d **********\n", i);
        sleep(atoi(argv[3]));
        device->printSwStats();
        printf("********* Sleeping for 15 sec i = %d **********\n", i);
        sleep(15);
    }

    while(1);
    return 0;
}
