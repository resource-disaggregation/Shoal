import DefaultValue::*;

`include "ConnectalProjectConfig.bsv"

typedef 512 BUS_WIDTH;
typedef 9 BUS_WIDTH_POW_OF_2;

typedef Bit#(32) Address;

typedef enum {READ, PEEK, WRITE} Operation deriving(Bits, Eq);

typedef struct {
    Bit#(1) sop;
    Bit#(1) eop;
    Bit#(BUS_WIDTH) payload;
} RingBufferDataT deriving(Bits, Eq);

instance DefaultValue#(RingBufferDataT);
	defaultValue = RingBufferDataT {
		sop     : 0,
		eop     : 0,
		payload : 0
	};
endinstance

typedef struct {
    Operation op;
} ReadReqType deriving(Bits, Eq);

typedef struct {
    RingBufferDataT data;
} ReadResType deriving(Bits, Eq);

instance DefaultValue#(ReadResType);
    defaultValue = ReadResType {
        data : unpack(0)
    };
endinstance

typedef struct {
    RingBufferDataT data;
} WriteReqType deriving(Bits, Eq);

function ReadReqType makeReadReq(Operation op);
    return ReadReqType {
        op : op
    };
endfunction

function ReadResType makeReadRes(RingBufferDataT data);
    return ReadResType {
        data : data
    };
endfunction

function WriteReqType makeWriteReq
        (Bit#(1) sop, Bit#(1) eop, Bit#(BUS_WIDTH) payload);
    RingBufferDataT d = RingBufferDataT {
        sop     : sop,
        eop     : eop,
        payload : payload
    };

    return WriteReqType {
        data : d
    };
endfunction

