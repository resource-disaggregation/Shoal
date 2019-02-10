import Vector::*;
import FIFO::*;
import FIFOF::*;
import ClientServer::*;
import SpecialFIFOs::*;
import BRAM::*;
import GetPut::*;
import DefaultValue::*;
import Clocks::*;

import Params::*;
import SchedulerTypes::*;
import RingBufferTypes::*;
import RingBuffer::*;
import CellGenerator::*;
import Mac::*;

`include "ConnectalProjectConfig.bsv"

interface Scheduler;
	interface Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64)))
        time_slots_res;
	interface Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64)))
        sent_host_pkt_res;
	interface Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64)))
        sent_fwd_pkt_res;
	interface Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64)))
        received_host_pkt_res;
	interface Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64)))
        received_fwd_pkt_res;
	interface Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64)))
        received_corrupted_pkt_res;
	interface Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64)))
        received_wrong_dst_pkt_res;
	interface Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64)))
        latency_res;

    method Action timeSlotsCount();
	method Action sentHostPktCount();
	method Action sentFwdPktCount();
	method Action receivedHostPktCount();
	method Action receivedFwdPktCount();
	method Action receivedCorruptedPktCount();
	method Action receivedWrongDstPktCount();
    method Action latency();

    method Action start(ServerIndex first_host_index, Bit#(8) t);
    method Action stop();
endinterface

module mkScheduler#(Mac mac, Vector#(NUM_OF_ALTERA_PORTS, CellGenerator) cg,
                Clock pcieClock, Reset pcieReset) (Scheduler);

    Bool verbose = False;

    Clock defaultClock <- exposeCurrentClock();
    Reset defaultReset <- exposeCurrentReset();

    Reg#(Bit#(8)) timeslot_len <- mkReg(0);

    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(1))) start_flag <- replicateM(mkReg(0));

    Vector#(NUM_OF_ALTERA_PORTS, Reg#(ServerIndex)) host_index
        <- replicateM(mkReg(maxBound));

    /* Schedule */
	Vector#(NUM_OF_SERVERS, Vector#(NUM_OF_SERVERS, Reg#(ServerIndex)))
        schedule_table <- replicateM(replicateM(mkReg(0)));

    Reg#(Bit#(1)) once <- mkReg(1);

    rule populate_schedule_table (once == 1);
        once <= 0;
        for (Integer i = 0; i < valueof(NUM_OF_SERVERS); i = i + 1) //Port
        begin
            for (Integer j = 0; j < valueof(NUM_OF_SERVERS)-1; j = j + 1) //t
            begin
                schedule_table[i][j] <= (fromInteger(i) + fromInteger(j) + 1)
                        % fromInteger(valueof(NUM_OF_SERVERS));
            end
        end
    endrule

    /* Stats */
	Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(Bit#(64))) time_slots_fifo
	        <- replicateM(mkSyncFIFO(1, defaultClock, defaultReset, pcieClock));
	Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(Bit#(64))) sent_host_pkt_fifo
	        <- replicateM(mkSyncFIFO(1, defaultClock, defaultReset, pcieClock));
	Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(Bit#(64))) sent_fwd_pkt_fifo
	        <- replicateM(mkSyncFIFO(1, defaultClock, defaultReset, pcieClock));
	Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(Bit#(64))) received_host_pkt_fifo
	        <- replicateM(mkSyncFIFO(1, defaultClock, defaultReset, pcieClock));
	Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(Bit#(64))) received_fwd_pkt_fifo
	        <- replicateM(mkSyncFIFO(1, defaultClock, defaultReset, pcieClock));
	Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(Bit#(64))) received_corrupted_pkt_fifo
	        <- replicateM(mkSyncFIFO(1, defaultClock, defaultReset, pcieClock));
	Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(Bit#(64))) received_wrong_dst_pkt_fifo
	        <- replicateM(mkSyncFIFO(1, defaultClock, defaultReset, pcieClock));
	Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(Bit#(64))) latency_fifo
	        <- replicateM(mkSyncFIFO(1, defaultClock, defaultReset, pcieClock));

	Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(64))) num_of_time_slots_used_reg
        <- replicateM(mkReg(0));
	Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(64))) host_pkt_transmitted_reg
        <- replicateM(mkReg(0));
	Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(64))) non_host_pkt_transmitted_reg
        <- replicateM(mkReg(0));
	Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(64)))
        num_of_host_pkt_received_reg <- replicateM(mkReg(0));
	Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(64)))
        num_of_fwd_pkt_received_reg <- replicateM(mkReg(0));
	Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(64)))
        num_of_corrupted_pkt_received_reg <- replicateM(mkReg(0));
	Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(64)))
        num_of_wrong_dst_pkt_received_reg <- replicateM(mkReg(0));
	Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(64)))
        latency_reg <- replicateM(mkReg(0));

/*------------------------------------------------------------------------------*/

                                /* Clock */

/*------------------------------------------------------------------------------*/

    Reg#(Bit#(64)) curr_time <- mkReg(0);

    rule clk;
        curr_time <= curr_time + 1;
    endrule

/*------------------------------------------------------------------------------*/

                                /* Tx Path */

/*------------------------------------------------------------------------------*/

    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(8)))
        counter <- replicateM(mkReg(0));
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(ServerIndex))
        time_slot <- replicateM(mkReg(0));
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(64)))
        curr_epoch <- replicateM(mkReg(0));
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(ServerIndex))
        interm_dst <- replicateM(mkReg(maxBound));

    //fwd cell buffers
    Vector#(NUM_OF_ALTERA_PORTS, Vector#(NUM_OF_SERVERS,
        RingBuffer#(ReadReqType, ReadResType, WriteReqType)))
            fwd_buffer <- replicateM(replicateM
                (mkRingBuffer(valueof(FWD_BUFFER_SIZE), valueof(CELL_SIZE))));
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(BufType))
        buffer_type <- replicateM(mkReg(HOST));
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(ServerIndex))
        buffer_index <- replicateM(mkReg(maxBound));
    Vector#(NUM_OF_ALTERA_PORTS, FIFO#(ReadResType))
        cell_to_send_fifo <- replicateM(mkSizedFIFO(2));
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(HEADER_SIZE)))
        curr_header <- replicateM(mkReg(0));

`ifdef SHOAL
    Vector#(NUM_OF_ALTERA_PORTS, Vector#(NUM_OF_SERVERS, FIFOF#(ServerIndex)))
        last_cell_sent_to
            <- replicateM(replicateM(mkSizedFIFOF(valueof(FWD_BUFFER_SIZE))));

    Vector#(NUM_OF_ALTERA_PORTS, Vector#(NUM_OF_SERVERS, FIFOF#(ServerIndex)))
        last_cell_recvd_from
            <- replicateM(replicateM(mkSizedFIFOF(valueof(FWD_BUFFER_SIZE))));

    Vector#(NUM_OF_ALTERA_PORTS, Vector#(NUM_OF_SERVERS,
            Vector#(NUM_OF_SERVERS, FIFO#(void))))
        schedule_host_flow_fifo <- replicateM(replicateM(replicateM(mkFIFO)));

    Vector#(NUM_OF_ALTERA_PORTS, Vector#(NUM_OF_SERVERS,
            Vector#(NUM_OF_SERVERS, Reg#(Bit#(1)))))
        host_pkt_allocated <- replicateM(replicateM(replicateM(mkReg(0))));

    function Bit#(1) compare (Bit#(1) a, Bit#(1) b);
        if (a == b)
            return 1;
        else
            return 0;
    endfunction
`endif

    for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
    begin
        rule figure_out_curr_timeslot (start_flag[i] == 1);
            if (counter[i] == 0)
            begin
                time_slot[i] <= (time_slot[i] + 1)
                    % fromInteger(valueof(NUM_OF_SERVERS)-1);
                if (time_slot[i] == fromInteger(valueof(NUM_OF_SERVERS)-2))
                    curr_epoch[i] <= curr_epoch[i] + 1;
                ServerIndex d = schedule_table[host_index[i]][time_slot[i]];
                interm_dst[i] <= d;
`ifdef SHOAL
                for (Integer j = 0; j < valueof(NUM_OF_SERVERS); j = j + 1)
                    schedule_host_flow_fifo[i][d][j].enq(?);
`endif

`ifndef SHOAL
                buffer_index[i] <= d;
`endif
                num_of_time_slots_used_reg[i] <= num_of_time_slots_used_reg[i] + 1;
            end
            if (counter[i] == timeslot_len - 1)
                counter[i] <= 0;
            else
                counter[i] <= counter[i] + 1;
        endrule

        for (Integer j = 0; j < valueof(NUM_OF_SERVERS); j = j + 1)
        begin
            rule req_host_cell (start_flag[i] == 1 && counter[i] == 3
                            && buffer_type[i] == HOST
                            && buffer_index[i] == fromInteger(j));
                cg[i].host_cell_req[j].put(?);
            endrule

            rule get_host_cell;
                let d <- cg[i].host_cell_res[j].get;
                cell_to_send_fifo[i].enq(d);
            endrule

            rule req_fwd_cell (start_flag[i] == 1 && counter[i] == 3
                            && buffer_type[i] == FWD
                            && buffer_index[i] == fromInteger(j));
                fwd_buffer[i][j].read_request.put(makeReadReq(READ));
            endrule

            rule get_fwd_cell;
                let d <- fwd_buffer[i][j].read_response.get;
                cell_to_send_fifo[i].enq(d);
            endrule
        end

        rule req_dummy_cell (start_flag[i] == 1 && counter[i] == 3
                        && buffer_type[i] == DUMMY);
            cg[i].dummy_cell_req.put(?);
        endrule

        rule get_dummy_cell;
            let d <- cg[i].dummy_cell_res.get;
            cell_to_send_fifo[i].enq(d);
        endrule

        rule send_cell (start_flag[i] == 1);
            let d <- toGet(cell_to_send_fifo[i]).get;

            Bit#(HEADER_SIZE) h = curr_header[i];
            if (d.data.sop == 1)
            begin
                Bit#(HEADER_SIZE) x = {host_index[i], interm_dst[i], '0};
                Integer s = valueof(BUS_WIDTH) - 1;
                Integer e = valueof(BUS_WIDTH) - valueof(HEADER_SIZE);
                h = d.data.payload[s:e] | x;
`ifdef SHOAL
                //piggyback rate limiting feedback
                Bit#(THROTTLE_BITS) b = maxBound; //did not recv any cell yet
                if (last_cell_recvd_from[i][interm_dst[i]].notEmpty)
                begin
                    let fwd_buffer_index
                        <- toGet(last_cell_recvd_from[i][interm_dst[i]]).get;

                    if (fwd_buffer_index == fromInteger(valueof(NUM_OF_SERVERS)))
                        b = maxBound-1; //last cell recvd was dummy OR host cell
                    else if (fwd_buffer_index
                                == fromInteger(valueof(NUM_OF_SERVERS)+1))
                        b = maxBound-2; //last cell recvd was corrupted
                    else
                    begin
                        Bit#(64) fwd_buffer_len
                            = fwd_buffer[i][fwd_buffer_index].elements;
                        let v = map(uncurry(compare),
                            zip(readVReg(host_pkt_allocated[i][fwd_buffer_index]),
                                replicate(1)));
                        let count = countElem(1, v);
                        b = truncate(fwd_buffer_len) + pack(zeroExtend(count));
                    end
                end
                h[11:1] = b;
`endif
                curr_header[i] <= h;
                host_pkt_transmitted_reg[i] <= host_pkt_transmitted_reg[i] + 1;
            end

            if (d.data.eop == 1)
                d.data.payload = {h, h, h, h, h, h, h, curr_time};
            else
                d.data.payload = {h, h, h, h, h, h, h, h};

            mac.mac_tx_write_req[i].put(d.data); //Put to MAC interface

            if (verbose && host_index[i] == 0)
                $display("[SCHED %d] t = %d dst = %d seq = %d sent = %d %d %x",
                    host_index[i], 0, interm_dst[i], d.data.payload[475:460],
                    d.data.sop, d.data.eop, d.data.payload);
        endrule
    end

/*------------------------------------------------------------------------------*/

                                /* Rx Path */

/*------------------------------------------------------------------------------*/

    Vector#(NUM_OF_ALTERA_PORTS, Reg#(ServerIndex))
        curr_src_mac <- replicateM(mkReg(fromInteger(valueof(NUM_OF_SERVERS))));
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(ServerIndex))
        curr_dst_mac <- replicateM(mkReg(fromInteger(valueof(NUM_OF_SERVERS))));
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(ServerIndex))
        curr_src_ip <- replicateM(mkReg(fromInteger(valueof(NUM_OF_SERVERS))));
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(ServerIndex))
        curr_dst_ip <- replicateM(mkReg(fromInteger(valueof(NUM_OF_SERVERS))));
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(1)))
        curr_dummy_bit <- replicateM(mkReg(0));

    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(HEADER_SIZE)))
        curr_rx_header <- replicateM(mkReg(0));

    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(1)))
        curr_corrupted_cell <- replicateM(mkReg(0));

    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(16)))
        curr_cell_size <- replicateM(mkReg(0));

    Vector#(NUM_OF_ALTERA_PORTS, FIFO#(Bit#(HEADER_SIZE)))
        update_throttle_value_fifo <- replicateM(mkFIFO);

    for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
    begin
        rule receive_cell (start_flag[i] == 1);
            let d <- mac.mac_rx_read_res[i].get; //Get from MAC interface

            ServerIndex src_mac = curr_src_mac[i];
            ServerIndex dst_mac = curr_dst_mac[i];
            ServerIndex src_ip = curr_src_ip[i];
            ServerIndex dst_ip = curr_dst_ip[i];
            Bit#(1) dummy_bit = curr_dummy_bit[i];

            Bit#(HEADER_SIZE) hd = curr_rx_header[i];

            Bit#(1) corrupted_cell = curr_corrupted_cell[i];

            //All the indicies assume BUS_WIDTH of 512; change them if you change
            //BUS_WIDTH

            Bit#(16) cell_size_cnt = curr_cell_size[i];

            if (d.sop == 1)
            begin
                corrupted_cell = 0;
                src_mac = d.payload[511:503];
                dst_mac = d.payload[502:494];
                src_ip = d.payload[493:485];
                dst_ip = d.payload[484:476];
                dummy_bit = d.payload[448];

                curr_src_mac[i] <= src_mac;
                curr_dst_mac[i] <= dst_mac;
                curr_src_ip[i] <= src_ip;
                curr_dst_ip[i] <= dst_ip;
                curr_dummy_bit[i] <= dummy_bit;

                hd = d.payload[511:448];
                curr_rx_header[i] <= hd;

                if (dst_mac != host_index[i])
                    num_of_wrong_dst_pkt_received_reg[i]
                        <= num_of_wrong_dst_pkt_received_reg[i] + 1;
`ifdef SHOAL
                else
                    //update throttle value
                    update_throttle_value_fifo[i].enq(hd);
`endif
                cell_size_cnt = fromInteger(valueof(BUS_WIDTH));
                curr_cell_size[i] <= cell_size_cnt;
            end
            else
            begin
                cell_size_cnt = cell_size_cnt + fromInteger(valueof(BUS_WIDTH));
                curr_cell_size[i] <= cell_size_cnt;
            end

            //check for corruption

            //assumes header size of 64 and BUS_WIDTH of 512
            Bit#(BUS_WIDTH) c = {hd, hd, hd, hd, hd, hd, hd, hd};

            if (corrupted_cell == 0)
            begin
                if (d.eop == 0)
                begin
                    if (d.payload != c)
                    begin
                        corrupted_cell = 1;
                        num_of_corrupted_pkt_received_reg[i]
                            <= num_of_corrupted_pkt_received_reg[i] + 1;
                    end
                end
                else if (d.eop == 1)
                begin
                    if (cell_size_cnt != fromInteger(valueof(CELL_SIZE))
                        || d.payload[511:64] != c[511:64])
                    begin
                        corrupted_cell = 1;
                        num_of_corrupted_pkt_received_reg[i]
                            <= num_of_corrupted_pkt_received_reg[i] + 1;
                    end

                    Bit#(64) t = d.payload[63:0];
                    if (t != 0 && latency_reg[i] == 0)
                        latency_reg[i] <= curr_time - t;

                    if (corrupted_cell == 0)
                    begin
                        if (dummy_bit == 0)
                        begin
                            if (dst_ip == host_index[i])
                                num_of_host_pkt_received_reg[i]
                                    <= num_of_host_pkt_received_reg[i] + 1;
                            else
                                num_of_fwd_pkt_received_reg[i]
                                    <= num_of_fwd_pkt_received_reg[i] + 1;
                        end
                    end
                end
            end

            curr_corrupted_cell[i] <= corrupted_cell;

`ifdef SHOAL
            //update last cell recvd
            if (d.eop == 1)
            begin
                if (dummy_bit == 1 || dst_ip == host_index[i])
                    last_cell_recvd_from[i][src_mac]
                        .enq(fromInteger(valueof(NUM_OF_SERVERS)));

                else if (corrupted_cell == 1)
                    last_cell_recvd_from[i][src_mac]
                        .enq(fromInteger(valueof(NUM_OF_SERVERS)+1));

                else
                    last_cell_recvd_from[i][src_mac].enq(dst_ip);
            end

            //put cell in the fwd buffer
            if (corrupted_cell == 0 && dummy_bit == 0 && dst_ip != host_index[i])
            begin
                if (!fwd_buffer[i][dst_ip].full)
                    fwd_buffer[i][dst_ip].write_request.put
                        (makeWriteReq(d.sop, d.eop, d.payload));
                //else pkt drop
            end
`endif

            if (verbose && host_index[i] == 1)
                $display("[SCHED %d] recvd = %d %d %x dst_mac = %d dst_ip = %d",
                    host_index[i], d.sop, d.eop, d.payload, dst_mac, dst_ip);
        endrule
    end

/*------------------------------------------------------------------------------*/

                                /* Shoal */

/*------------------------------------------------------------------------------*/
`ifdef SHOAL
    Vector#(NUM_OF_ALTERA_PORTS, Vector#(NUM_OF_SERVERS,
            Vector#(NUM_OF_SERVERS, FIFO#(Bit#(THROTTLE_BITS)))))
        new_throttle_value <- replicateM(replicateM(replicateM(mkFIFO)));

    Vector#(NUM_OF_ALTERA_PORTS, Vector#(NUM_OF_SERVERS,
            Vector#(NUM_OF_SERVERS, Reg#(HostFlowT))))
        host_flow_scheduling_info
            <- replicateM(replicateM(replicateM(mkReg(defaultValue))));

    Vector#(NUM_OF_ALTERA_PORTS, Vector#(NUM_OF_SERVERS, FIFOF#(HostFlowTokenT)))
      host_flow_ready_queue
        <- replicateM(replicateM(mkSizedBypassFIFOF(valueof(NUM_OF_SERVERS))));

    Vector#(NUM_OF_ALTERA_PORTS, Vector#(NUM_OF_SERVERS,
            Vector#(NUM_OF_SERVERS, FIFO#(void))))
        clear_host_pkt_allocated_fifo <- replicateM(replicateM(replicateM(mkFIFO)));

    Vector#(NUM_OF_ALTERA_PORTS, Vector#(NUM_OF_SERVERS,
            Vector#(NUM_OF_SERVERS, FIFO#(Bit#(THROTTLE_BITS)))))
        insert_into_token_queue_fifo <- replicateM(replicateM(replicateM(mkFIFO)));

    Vector#(NUM_OF_ALTERA_PORTS, Vector#(NUM_OF_SERVERS, FIFO#(void)))
        choose_right_buffer_to_send_from_fifo <- replicateM(replicateM(mkFIFO));

/*------------------------------------------------------------------------------*/

    for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
    begin
        for (Integer j = 0; j < valueof(NUM_OF_SERVERS); j = j + 1)
        begin //j represents the intermediate node
            for (Integer k = 0; k < valueof(NUM_OF_SERVERS); k = k + 1)
            begin //k represents the host flow index via j

    (* descending_urgency = "clear_host_pkt_allocated_bit, schedule_host_flow" *)
    (* descending_urgency = "update_with_new_throttle_value, schedule_host_flow" *)

                rule clear_host_pkt_allocated_bit;
                    let x <- toGet(clear_host_pkt_allocated_fifo[i][j][k]).get;
                    host_pkt_allocated[i][j][k] <= 0;
                endrule

                rule update_with_new_throttle_value;
                    let throttle_value <- toGet(new_throttle_value[i][j][k]).get;
                    //Update with new throttle value
                    HostFlowT h = HostFlowT {
                        throttle_value : throttle_value,
                        start_epoch    : curr_epoch[i],
                        schedulable    : 1
                    };
                    host_flow_scheduling_info[i][j][k] <= h;
                endrule

                rule schedule_host_flow;
                    let x <- toGet(schedule_host_flow_fifo[i][j][k]).get;
                    //schedule host flow
                    ServerIndex fwd_buffer_index = fromInteger(j);
                    Bit#(64) fwd_buffer_len
                        = fwd_buffer[i][fwd_buffer_index].elements;
                    let v = map(uncurry(compare),
                        zip(readVReg(host_pkt_allocated[i][j]), replicate(1)));
                    let count = countElem(1, v);
                    Bit#(THROTTLE_BITS) agg_queue_len
                        = truncate(fwd_buffer_len) + pack(zeroExtend(count));

                    Bit#(64) time_elapsed
                        = curr_epoch[i]
                            - host_flow_scheduling_info[i][j][k].start_epoch;
                    Bit#(THROTTLE_BITS) func =
                        (host_flow_scheduling_info[i][j][k].throttle_value
                            >= truncate(time_elapsed))
                        ? host_flow_scheduling_info[i][j][k].throttle_value
                            - truncate(time_elapsed)
                        : 0;

                    if (host_flow_scheduling_info[i][j][k].schedulable == 1
                        //&& pkt_scheduled[j] < flow_size[j]
                        && agg_queue_len >= func)
                    begin
                        insert_into_token_queue_fifo[i][j][k].enq(agg_queue_len);

                        HostFlowT h = HostFlowT {
                            throttle_value : host_flow_scheduling_info[i][j][k]
                                                .throttle_value,
                            start_epoch    : host_flow_scheduling_info[i][j][k]
                                                .start_epoch,
                            schedulable    : 0
                        };
                        host_flow_scheduling_info[i][j][k] <= h;

                        host_pkt_allocated[i][j][k] <= 1;
                    end

                    if (k == 0)
                        choose_right_buffer_to_send_from_fifo[i][j].enq(?);
                endrule

                rule insert_into_token_queue;
                    let len <- toGet(insert_into_token_queue_fifo[i][j][k]).get;

                    HostFlowTokenT tok = HostFlowTokenT {
                        host_flow_index : fromInteger(k),
                        time_to_send    : curr_epoch[i] + zeroExtend(len)
                    };
                    host_flow_ready_queue[i][j].enq(tok);
                    //pkt_scheduled[j] <= pkt_scheduled[j] + 1;
                endrule
            end

            rule choose_right_buffer_to_send_from;
                let d <- toGet(choose_right_buffer_to_send_from_fifo[i][j]).get;

                ServerIndex host_flow_to_send = fromInteger(valueof(NUM_OF_SERVERS));
                if (host_flow_ready_queue[i][j].notEmpty)
                begin
                    let x = host_flow_ready_queue[i][j].first;
                    ServerIndex host_flow_index = x.host_flow_index;
                    Bit#(64) time_to_send = x.time_to_send;

                    if (time_to_send <= curr_epoch[i])
                    begin
                        host_flow_ready_queue[i][j].deq;
                        clear_host_pkt_allocated_fifo[i][j][host_flow_index].enq(?);
                        host_flow_to_send = host_flow_index;
                    end
                end

                if (host_flow_to_send == fromInteger(valueof(NUM_OF_SERVERS)))
                begin
                    if (!fwd_buffer[i][j].empty)
                    begin
                        buffer_type[i] <= FWD;
                        buffer_index[i] <= fromInteger(j);
                    end
                    else
                    begin
                        buffer_type[i] <= DUMMY;
                    end
                end

                else
                begin
                    buffer_type[i] <= HOST;
                    buffer_index[i] <= host_flow_to_send;
                end

                last_cell_sent_to[i][j].enq(host_flow_to_send);
            endrule
        end
    end

/*------------------------------------------------------------------------------*/

    for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
    begin
        rule update_throttle_value;
            let hd <- toGet(update_throttle_value_fifo[i]).get;
            ServerIndex src_mac = hd[63:55];
            Bit#(THROTTLE_BITS) feedback = hd[11:1];

            if (feedback != maxBound)
            begin
                let buffer_index <- toGet(last_cell_sent_to[i][src_mac]).get;
                if (buffer_index != fromInteger(valueof(NUM_OF_SERVERS)))
                begin
                    if (feedback != maxBound-1) $display("ERROR");
                    if (feedback == maxBound-2)//last pkt sent was corrupted
                        new_throttle_value[i][src_mac][buffer_index].enq(0);
                    else
                        new_throttle_value[i][src_mac][buffer_index].enq(feedback);
                end
            end

        endrule
    end
`endif

/*------------------------------------------------------------------------------*/

                                /* Interface */

/*------------------------------------------------------------------------------*/

`ifdef WAIT_FOR_START_SIG
    for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
    begin
        rule start_scheduler;
            let d <- mac.start_scheduler[i].get;
            start_flag[i] <= 1;
        endrule
    end
`endif

    Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64))) temp1;
    Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64))) temp2;
    Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64))) temp3;
    Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64))) temp4;
    Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64))) temp5;
    Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64))) temp6;
    Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64))) temp7;
    Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64))) temp8;

    for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
    begin
        temp1[i] = toGet(time_slots_fifo[i]);
        temp2[i] = toGet(sent_host_pkt_fifo[i]);
        temp3[i] = toGet(sent_fwd_pkt_fifo[i]);
        temp4[i] = toGet(received_host_pkt_fifo[i]);
        temp5[i] = toGet(received_fwd_pkt_fifo[i]);
        temp6[i] = toGet(received_corrupted_pkt_fifo[i]);
        temp7[i] = toGet(received_wrong_dst_pkt_fifo[i]);
        temp8[i] = toGet(latency_fifo[i]);
    end

    method Action start(ServerIndex first_host_index, Bit#(8) t);
        timeslot_len <= t;
        for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
        begin
            host_index[i] <= (first_host_index
                * fromInteger(valueof(NUM_OF_ALTERA_PORTS))) + fromInteger(i);
`ifndef WAIT_FOR_START_SIG
            start_flag[i] <= 1;
`endif
        end
    endmethod

    method Action stop();
        for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
            start_flag[i] <= 0;
    endmethod

    method Action timeSlotsCount();
        for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
            time_slots_fifo[i].enq(num_of_time_slots_used_reg[i]);
    endmethod

	method Action sentHostPktCount();
        for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
            sent_host_pkt_fifo[i].enq(host_pkt_transmitted_reg[i]);
	endmethod

	method Action sentFwdPktCount();
        for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
            sent_fwd_pkt_fifo[i].enq(non_host_pkt_transmitted_reg[i]);
	endmethod

	method Action receivedHostPktCount();
        for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
            received_host_pkt_fifo[i].enq(num_of_host_pkt_received_reg[i]);
	endmethod

	method Action receivedFwdPktCount();
        for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
            received_fwd_pkt_fifo[i].enq(num_of_fwd_pkt_received_reg[i]);
	endmethod

	method Action receivedCorruptedPktCount();
        for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
            received_corrupted_pkt_fifo[i].enq
                (num_of_corrupted_pkt_received_reg[i]);
	endmethod

	method Action receivedWrongDstPktCount();
        for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
            received_wrong_dst_pkt_fifo[i].enq
                (num_of_wrong_dst_pkt_received_reg[i]);
	endmethod

	method Action latency();
        for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
            latency_fifo[i].enq(latency_reg[i]);
	endmethod

	interface Get time_slots_res = temp1;
	interface Get sent_host_pkt_res = temp2;
	interface Get sent_fwd_pkt_res = temp3;
	interface Get received_host_pkt_res = temp4;
	interface Get received_fwd_pkt_res = temp5;
	interface Get received_corrupted_pkt_res = temp6;
	interface Get received_wrong_dst_pkt_res = temp7;
	interface Get latency_res = temp8;
endmodule
