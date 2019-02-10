#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <stdint.h>
#include <unistd.h>

#include "SchedulerTopSimIndication.h"
#include "SchedulerTopSimRequest.h"
#include "GeneratedTypes.h"

static uint32_t server_index = 0;
static uint32_t rate = 0; //rate of cell generation
static uint8_t timeslot = 0; //timeslot length
static uint64_t cycles = 0; //num of cycles to run exp for

static uint16_t chunk_num = 8;

static SchedulerTopSimRequestProxy *device = 0;

class SchedulerTopSimIndication : public SchedulerTopSimIndicationWrapper
{
public:
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

    SchedulerTopSimIndication(unsigned int id)
        : SchedulerTopSimIndicationWrapper(id) {}
};

void configure_scheduler(SchedulerTopSimRequestProxy* device) {
	device->start_shoal(server_index,
						rate,
                        timeslot,
						cycles);
}

int main(int argc, char **argv)
{
    SchedulerTopSimIndication echoIndication(IfcNames_SchedulerTopSimIndicationH2S);
    device = new SchedulerTopSimRequestProxy(IfcNames_SchedulerTopSimRequestS2H);

    int i;

    if (argc != 6) {
        printf("Wrong number of arguments\n");
        exit(0);
    } else {
        server_index = atoi(argv[1]);
        rate = atoi(argv[2]);
        timeslot = atoi(argv[3]);
        cycles = atol(argv[4]);

        chunk_num = (atoi(argv[5]) * 8) / 64;
    }

    for (i = 0; i < 3; ++i) {
        configure_scheduler(device);
        sleep(45);
    }

    while(1);
    return 0;
}
