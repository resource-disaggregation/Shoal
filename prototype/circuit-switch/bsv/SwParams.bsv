`include "ConnectalProjectConfig.bsv"

typedef 4 NUM_OF_SWITCH_PORTS;
typedef Bit#(9) PortIndex;

typedef 64 BITS_PER_CYCLE; //for 10Gbps interface and 156.25MHz clock freq

typedef 2048 CELL_SIZE;
