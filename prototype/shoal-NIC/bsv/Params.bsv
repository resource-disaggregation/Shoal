`include "ConnectalProjectConfig.bsv"

typedef 64 BITS_PER_CYCLE; //for 10Gbps interface and 156.25MHz clock freq
typedef BITS_PER_CYCLE HEADER_SIZE; //size of cell header

typedef 4 NUM_OF_SERVERS;
typedef Bit#(9) ServerIndex;

`ifdef MULTI_NIC
typedef 4 NUM_OF_ALTERA_PORTS;
`else
typedef 1 NUM_OF_ALTERA_PORTS;
`endif
typedef Bit#(9) PortIndex;

typedef 2048 CELL_SIZE; //in bits; must be a multiple of BUS_WIDTH

typedef NUM_OF_SERVERS FWD_BUFFER_SIZE;
