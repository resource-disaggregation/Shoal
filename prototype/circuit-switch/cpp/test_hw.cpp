#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <stdint.h>
#include <unistd.h>

#include "CircuitSwTopIndication.h"
#include "CircuitSwTopRequest.h"
#include "GeneratedTypes.h"

static CircuitSwTopRequestProxy *device = 0;

class CircuitSwTopIndication : public CircuitSwTopIndicationWrapper
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

    CircuitSwTopIndication(unsigned int id) :
        CircuitSwTopIndicationWrapper(id) {}
};


int main(int argc, char **argv)
{
    CircuitSwTopIndication echoIndication(IfcNames_CircuitSwTopIndicationH2S);
    device = new CircuitSwTopRequestProxy(IfcNames_CircuitSwTopRequestS2H);

    if (argc != 4) {
        printf("Wrong number of arguments");
        exit(0);
    }

    device->startSwitching(atoi(argv[1]), atol(argv[2]));

    sleep(atoi(argv[3]));

    device->printStats();

    while(1);
    return 0;
}
