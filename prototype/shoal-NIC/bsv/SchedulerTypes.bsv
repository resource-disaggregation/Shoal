import Params::*;
import DefaultValue::*;

`include "ConnectalProjectConfig.bsv"

typedef enum {HOST, FWD, DUMMY} BufType deriving(Bits, Eq);

typedef 11 THROTTLE_BITS;

typedef struct {
    Bit#(THROTTLE_BITS) throttle_value;
    Bit#(64) start_epoch;
    Bit#(1) schedulable;
} HostFlowT deriving(Bits, Eq);

instance DefaultValue#(HostFlowT);
    defaultValue = HostFlowT {
        throttle_value : 0,
        start_epoch    : 0,
        schedulable    : 1
    };
endinstance

typedef struct {
    ServerIndex host_flow_index;
    Bit#(64) time_to_send;
} HostFlowTokenT deriving(Bits, Eq);

instance DefaultValue#(HostFlowTokenT);
    defaultValue = HostFlowTokenT {
        host_flow_index : fromInteger(valueof(NUM_OF_SERVERS)),
        time_to_send    : maxBound
    };
endinstance
