import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import DefaultValue::*;
import GetPut::*;
import Clocks::*;
import Real::*;

import Params::*;
import RingBufferTypes::*;
import RingBuffer::*;

`include "ConnectalProjectConfig.bsv"

typedef struct {
    ServerIndex src_mac;
    ServerIndex dst_mac;
    ServerIndex src_ip;
    ServerIndex dst_ip;
    Bit#(16) seq_num;
    Bit#(11) remote_queue_len;
    Bit#(1) dummy_cell_bit;
} Header deriving(Bits, Eq); //64 bits

instance DefaultValue#(Header);
    defaultValue = Header {
        src_mac          : 0,
        dst_mac          : 0,
        src_ip           : 0,
        dst_ip           : 0,
        seq_num          : 0,
        remote_queue_len : 0,
        dummy_cell_bit   : 0
    };
endinstance

interface CellGenerator;
    interface Put#(void) dummy_cell_req;
    interface Get#(ReadResType) dummy_cell_res;
    interface Vector#(NUM_OF_SERVERS, Put#(void)) host_cell_req;
    interface Vector#(NUM_OF_SERVERS, Get#(ReadResType)) host_cell_res;

    method Action start(ServerIndex host_index, Bit#(16) rate);
    method Action stop();
endinterface

module mkCellGenerator#(Integer cell_size) (CellGenerator);

    Bool verbose = False;

    //interface buffers
    FIFOF#(void) dummy_cell_req_fifo <- mkBypassFIFOF;
    FIFOF#(ReadResType) dummy_cell_res_fifo <- mkBypassFIFOF;
    Vector#(NUM_OF_SERVERS, FIFOF#(void))
        host_cell_req_fifo <- replicateM(mkBypassFIFOF);
    Vector#(NUM_OF_SERVERS, FIFOF#(ReadResType))
        host_cell_res_fifo <- replicateM(mkFIFOF);

    //control registers
    Reg#(Bit#(1)) start_flag <- mkReg(0);
    Reg#(ServerIndex) host_index <- mkReg(maxBound);
    Reg#(Bit#(16)) rate_reg <- mkReg(0);
    Reg#(Bit#(16)) num_of_cycles_to_wait <- mkReg(maxBound);

    //host cell buffers
    Vector#(NUM_OF_SERVERS,
        RingBuffer#(ReadReqType, ReadResType, WriteReqType))
            host_buffer <- replicateM
                (mkRingBuffer(2, cell_size));

    //dummy cell buffer
    RingBuffer#(ReadReqType, ReadResType, WriteReqType)
        dummy_buffer <- mkRingBuffer(1, cell_size);

/*-------------------------------------------------------------------------------*/
    //put the dummy cell in the buffer
    Integer max_dummy_block_num = cell_size / valueof(BUS_WIDTH);
    Reg#(Bit#(16)) curr_dummy_block_num <- mkReg(maxBound);

    rule put_dummy_cell_in_buffer_initializer
        (start_flag == 1
        && (curr_dummy_block_num == maxBound
            || curr_dummy_block_num < fromInteger(max_dummy_block_num)));

        if (curr_dummy_block_num == maxBound)
            curr_dummy_block_num <= 0;
        else
            curr_dummy_block_num <= curr_dummy_block_num + 1;
    endrule

    for (Integer i = 0; i < max_dummy_block_num; i = i + 1)
    begin
        rule put_dummy_block_in_buffer (curr_dummy_block_num == fromInteger(i));
            Header h = defaultValue;
            if (i == 0)
            begin
                h.dummy_cell_bit = 1;
            end
            Bit#(HEADER_SIZE) hd = pack(h);
            Bit#(BUS_WIDTH) data = {hd, '0};
            Bit#(1) sop = 0;
            Bit#(1) eop = 0;
            if (curr_dummy_block_num == 0)
                sop = 1;
            if (curr_dummy_block_num == fromInteger(max_dummy_block_num) - 1)
                eop = 1;
            dummy_buffer.write_request.put(makeWriteReq(sop, eop, data));
            if (verbose)
                $display("[DMA %d] dummy data = %d %d %x",
                    host_index, sop, eop, data);
        endrule
    end

/*-------------------------------------------------------------------------------*/
    //put host cells in respective buffers
    Integer max_host_block_num = cell_size / valueof(BUS_WIDTH);
    Vector#(NUM_OF_SERVERS, Reg#(Bit#(16)))
        curr_host_block_num <- replicateM(mkReg(maxBound));
    Vector#(NUM_OF_SERVERS, Reg#(Bit#(16))) wait_period <- replicateM(mkReg(0));
    Vector#(NUM_OF_SERVERS, Reg#(Bit#(1)))
        prev_cell_put_in_buffer <- replicateM(mkReg(1));
    Vector#(NUM_OF_SERVERS, Reg#(Bit#(16)))
        curr_seq_num <- replicateM(mkReg(0));

    for (Integer i = 0; i < valueof(NUM_OF_SERVERS); i = i + 1)
    begin
        rule put_next_host_cell
            (start_flag == 1 && host_index != fromInteger(i)
                && prev_cell_put_in_buffer[i] == 1);

            if (wait_period[i] == num_of_cycles_to_wait)
            begin
                wait_period[i] <= 0;
                curr_host_block_num[i] <= 0;
                prev_cell_put_in_buffer[i] <= 0;
            end
            else
                wait_period[i] <= wait_period[i] + 1;
        endrule

        for (Integer j = 0; j < max_host_block_num; j = j + 1)
        begin
            rule put_host_block_in_buffer
                (curr_host_block_num[i] == fromInteger(j));

                Header h = defaultValue;
                if (j == 0)
                begin
                    h.src_ip = host_index;
                    h.dst_ip = fromInteger(i);
                    h.seq_num = curr_seq_num[i];
                    curr_seq_num[i] <= curr_seq_num[i] + 1;
                end
                Bit#(HEADER_SIZE) hd = pack(h);
                Bit#(BUS_WIDTH) data = {hd, '0};
                Bit#(1) sop = 0;
                Bit#(1) eop = 0;
                if (curr_host_block_num[i] == 0)
                    sop = 1;
                if (curr_host_block_num[i] == fromInteger(max_host_block_num) - 1)
                begin
                    eop = 1;
                    prev_cell_put_in_buffer[i] <= 1;
                end

                host_buffer[i].write_request.put(makeWriteReq(sop, eop, data));

                curr_host_block_num[i] <= curr_host_block_num[i] + 1;

                if (verbose && host_index == 1)
                    $display("[DMA %d->%d] seq = %d data = %d %d %x",
                        host_index, i, curr_seq_num[i], sop, eop, data);
            endrule
        end
    end

/*-------------------------------------------------------------------------------*/
    //formula = round(((cell size/(6.4 * rate) - (cell size/bus width))) - 1)
    function Integer cycles_to_wait(Integer rate);
        Real x = 6.4 * fromInteger(rate);
        Real y = fromInteger(cell_size)/x;
        Real z = y - (fromInteger(cell_size/valueof(BUS_WIDTH))) - 1;
        return round(z);
    endfunction

	Reg#(Bit#(1)) rate_set_flag <- mkReg(0);
	rule decodeRate (rate_set_flag == 1);
		case (rate_reg)
			10      : begin
					  num_of_cycles_to_wait <= fromInteger(cycles_to_wait(10));
				      end
			9       : begin
					  num_of_cycles_to_wait <= fromInteger(cycles_to_wait(9));
				      end
			8       : begin
					  num_of_cycles_to_wait <= fromInteger(cycles_to_wait(8));
				      end
			7       : begin
					  num_of_cycles_to_wait <= fromInteger(cycles_to_wait(7));
				      end
			6       : begin
					  num_of_cycles_to_wait <= fromInteger(cycles_to_wait(6));
				      end
			5       : begin
					  num_of_cycles_to_wait <= fromInteger(cycles_to_wait(5));
				      end
			4       : begin
					  num_of_cycles_to_wait <= fromInteger(cycles_to_wait(4));
				      end
			3       : begin
					  num_of_cycles_to_wait <= fromInteger(cycles_to_wait(3));
				      end
			2       : begin
					  num_of_cycles_to_wait <= fromInteger(cycles_to_wait(2));
				      end
			1       : begin
					  num_of_cycles_to_wait <= fromInteger(cycles_to_wait(1));
				      end
			default : begin
					  num_of_cycles_to_wait <= fromInteger(cycles_to_wait(10));
				      end
		endcase
		start_flag <= 1;
		rate_set_flag <= 0;
	endrule

/*-------------------------------------------------------------------------------*/
    rule handle_dummy_cell_req (start_flag == 1);
        let d <- toGet(dummy_cell_req_fifo).get;
        dummy_buffer.read_request.put(makeReadReq(PEEK));
    endrule

    rule handle_dummy_cell_res;
        let d <- dummy_buffer.read_response.get;
        dummy_cell_res_fifo.enq(d);
    endrule

    for (Integer i = 0; i < valueof(NUM_OF_SERVERS); i = i + 1)
    begin
        rule handle_host_cell_req (start_flag == 1);
            let d <- toGet(host_cell_req_fifo[i]).get;
            host_buffer[i].read_request.put(makeReadReq(READ));
        endrule

        rule handle_host_cell_res;
            let d <- host_buffer[i].read_response.get;
            host_cell_res_fifo[i].enq(d);
        endrule
    end

    Vector#(NUM_OF_SERVERS, Put#(void)) temp1;
    Vector#(NUM_OF_SERVERS, Get#(ReadResType)) temp2;

    for (Integer i = 0; i < valueof(NUM_OF_SERVERS); i = i + 1)
    begin
        temp1[i] = toPut(host_cell_req_fifo[i]);
        temp2[i] = toGet(host_cell_res_fifo[i]);
    end

    interface dummy_cell_req = toPut(dummy_cell_req_fifo);
    interface dummy_cell_res = toGet(dummy_cell_res_fifo);
    interface host_cell_req = temp1;
    interface host_cell_res = temp2;

    method Action start(ServerIndex idx, Bit#(16) rate);
        if (verbose)
            $display("[DMA (%d)] Starting..........................", idx);
		rate_reg <= rate;
		host_index <= idx;
		rate_set_flag <= 1;
    endmethod

    method Action stop();
        if (verbose)
            $display("[DMA (%d)] Stopping..........................", host_index);
        start_flag <= 0;
    endmethod

endmodule
