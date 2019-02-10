import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import BRAM::*;
import GetPut::*;
import DefaultValue::*;

import RingBufferTypes::*;

`include "ConnectalProjectConfig.bsv"

interface RingBuffer#(type readReqType, type readResType, type writeReqType);
    interface Put#(readReqType) read_request;
    interface Put#(writeReqType) write_request;
    interface Get#(readResType) read_response;

    method Bool empty();
    method Bool full();
    method Action clear();
    method Bit#(64) elements();
endinterface

module mkRingBuffer#(Integer buffer_size, Integer cell_size)
        (RingBuffer#(ReadReqType, ReadResType, WriteReqType));

    function BRAMRequest#(Address, Bit#(BUS_WIDTH))
      makeBRAMDataRequest(Bool write, Address addr, Bit#(BUS_WIDTH) data);
        return BRAMRequest {
                            write           : write,
                            responseOnWrite : False,
                            address         : addr,
                            datain          : data
                            };
    endfunction

    BRAM_Configure cfg = defaultValue;
    cfg.memorySize = fromInteger(buffer_size) * fromInteger(cell_size);

    BRAM2Port#(Address, Bit#(BUS_WIDTH)) ring_buffer <- mkBRAM2Server(cfg);

/*-------------------------------------------------------------------------------*/
    Integer cell_size_pow_of_2 = log2(cell_size);

    Reg#(Bit#(64)) head <- mkReg(0);
    Reg#(Bit#(64)) tail <- mkReg(0);

    Bool is_empty = (head == tail);
    Bool is_full = (head == tail + fromInteger(buffer_size));

    FIFO#(ReadReqType) read_request_fifo <- mkBypassFIFO;
    FIFO#(ReadResType) read_response_fifo <- mkBypassFIFO;
    FIFO#(WriteReqType) write_request_fifo <- mkFIFO;

/*-------------------------------------------------------------------------------*/
    Reg#(Bit#(1)) write_in_progress <- mkReg(0);
    Reg#(Address) w_offset <- mkReg(0);
    Reg#(Bit#(32)) length <- mkReg(0);

    rule write_req (!is_full);
        let w_req <- toGet(write_request_fifo).get;

        Bool write_flag = False;

        if (w_req.data.sop == 1 && w_req.data.eop == 0)
        begin
            write_in_progress <= 1;
            write_flag = False;
            w_offset <= 1;
            length <= fromInteger(valueof(BUS_WIDTH));
            Address addr = ((truncate(head) & (fromInteger(buffer_size)-1))
                     << fromInteger(cell_size_pow_of_2));
            ring_buffer.portA.request.put(makeBRAMDataRequest(True, addr,
                                                    w_req.data.payload));
        end

        else if ((w_req.data.sop == 0 && w_req.data.eop == 0)
                && write_in_progress == 1)
        begin
            //ensures I do not write cells larger in size than cell_size
            if (length == fromInteger(cell_size) - fromInteger(valueof(BUS_WIDTH)))
            begin
                write_flag = False;
                write_in_progress <= 0;
            end

            else
            begin
                write_flag = True;
                w_offset <= w_offset + 1;
                length <= length + fromInteger(valueof(BUS_WIDTH));
            end
        end

        else if ((w_req.data.sop == 0 && w_req.data.eop == 1)
                && write_in_progress == 1)
        begin
            write_in_progress <= 0;
            write_flag = True;
            //ensures I do not write cells smaller in size than cell_size
            if (length == fromInteger(cell_size) - fromInteger(valueof(BUS_WIDTH)))
                head <= head + 1;
        end

        else if (w_req.data.sop == 1 && w_req.data.eop == 1)
        begin
            write_in_progress <= 0;
            write_flag = False;
            //ensures I only write if cell_size is exactly equal to BUS_WIDTH
            if (cell_size == valueof(BUS_WIDTH))
            begin
                head <= head + 1;
                Address addr = ((truncate(head) & (fromInteger(buffer_size)-1))
                         << fromInteger(cell_size_pow_of_2));
                ring_buffer.portA.request.put(makeBRAMDataRequest(True, addr,
                                                        w_req.data.payload));
            end
        end

        if (write_flag == True)
        begin
            Address addr = ((truncate(head) & (fromInteger(buffer_size)-1))
                         << fromInteger(cell_size_pow_of_2))
                         + (w_offset << fromInteger(valueof(BUS_WIDTH_POW_OF_2)));
            ring_buffer.portA.request.put(makeBRAMDataRequest(True, addr,
                                                        w_req.data.payload));
        end

    endrule

/*-------------------------------------------------------------------------------*/

    Reg#(Bit#(1)) read_in_progress <- mkReg(0);
    Reg#(Address) r_offset <- mkReg(0);
    Reg#(Address) r_offset_1 <- mkReg(0);
    Reg#(Address) r_max_offset <- mkReg(0);

    Reg#(Bit#(1)) peek <- mkReg(0);

    rule read_req (read_in_progress == 0);
        let r_req <- toGet(read_request_fifo).get;

        if (!is_empty)
        begin
            read_in_progress <= 1;
            r_offset <= 0;
            r_offset_1 <= 0;
            r_max_offset <= fromInteger(cell_size)
                >> fromInteger(valueof(BUS_WIDTH_POW_OF_2));
            if (r_req.op == PEEK)
                peek <= 1;
            else
                peek <= 0;
        end
    endrule

    rule read_data_req (r_offset < r_max_offset);
        Address addr = ((truncate(tail) & (fromInteger(buffer_size)-1))
                     << fromInteger(cell_size_pow_of_2))
                     + (r_offset << fromInteger(valueof(BUS_WIDTH_POW_OF_2)));
        ring_buffer.portB.request.put(makeBRAMDataRequest(False, addr, 0));
        r_offset <= r_offset + 1;
    endrule

    rule read_data_res;
        let d <- ring_buffer.portB.response.get;

		r_offset_1 <= r_offset_1 + 1;

        if (r_offset_1 == 0 && r_offset_1 == r_max_offset - 1)
        begin
            RingBufferDataT data = RingBufferDataT {
                              sop : 1,
                              eop : 1,
                              payload : d
                             };
            read_response_fifo.enq(makeReadRes(data));
            read_in_progress <= 0;
            if (peek == 0)
                tail <= tail + 1;
        end

        if (r_offset_1 == 0 && r_offset_1 < r_max_offset - 1)
        begin
            RingBufferDataT data = RingBufferDataT {
                              sop : 1,
                              eop : 0,
                              payload : d
                             };
            read_response_fifo.enq(makeReadRes(data));
        end

        else if (r_offset_1  > 0 && r_offset_1 < r_max_offset - 1)
        begin
            RingBufferDataT data = RingBufferDataT {
                              sop : 0,
                              eop : 0,
                              payload : d
                             };
            read_response_fifo.enq(makeReadRes(data));
        end

        else if (r_offset_1 > 0 && r_offset_1 == r_max_offset - 1)
        begin
            RingBufferDataT data = RingBufferDataT {
                              sop : 0,
                              eop : 1,
                              payload : d
                             };
            read_response_fifo.enq(makeReadRes(data));
            read_in_progress <= 0;
            if (peek == 0)
                tail <= tail + 1;
        end

    endrule

/*-------------------------------------------------------------------------------*/

    method Bool empty();
        return is_empty;
    endmethod

    method Bool full();
        return is_full;
    endmethod

    method Action clear() if (read_in_progress == 0);
        head <= 0;
        tail <= 0;
    endmethod

    method Bit#(64) elements();
        return (head - tail);
    endmethod

    interface Put read_request = toPut(read_request_fifo);
    interface Put write_request = toPut(write_request_fifo);
    interface Get read_response = toGet(read_response_fifo);
endmodule

