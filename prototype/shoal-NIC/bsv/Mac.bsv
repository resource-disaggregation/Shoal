import FIFO::*;
import FIFOF::*;
import Vector::*;
import SpecialFIFOs::*;
import GetPut::*;
import Clocks::*;
import DefaultValue::*;

import Params::*;
import RingBufferTypes::*;

import AlteraMacWrap::*;
import EthMac::*;

`include "ConnectalProjectConfig.bsv"

interface Mac;
    interface Vector#(NUM_OF_ALTERA_PORTS, Get#(RingBufferDataT)) mac_rx_read_res;
    interface Vector#(NUM_OF_ALTERA_PORTS, Put#(RingBufferDataT)) mac_tx_write_req;

`ifdef WAIT_FOR_START_SIG
    interface Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(1))) start_scheduler;
    interface Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(1))) start_counting;
`endif

	interface Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64)))
        blocks_transmitted_from_mac;
	interface Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64)))
        blocks_received_by_mac;

    method Action getBlocksTransmittedFromMac();
    method Action getBlocksReceivedByMac();

    method Bit#(64) getTxClock();
    method Bit#(64) getRxClock();

    (* always_ready, always_enabled *)
    method Bit#(72) tx(Integer port_index);
    (* always_ready, always_enabled *)
    method Action rx(Integer port_index, Bit#(72) v);
endinterface

`ifdef NIC_SIM
module mkMac#(ServerIndex host_index,
            Clock txClock,
            Reset txReset,
            Reset tx_reset,
            Clock rxClock,
            Reset rxReset,
            Reset rx_reset) (Mac);
`endif

`ifdef HW_DE5
module mkMac#(Clock txClock,
            Reset txReset,
            Reset tx_reset,
            Clock rxClock,
            Reset rxReset,
            Reset rx_reset) (Mac);
`endif

    Bool verbose = False;

    Clock defaultClock <- exposeCurrentClock();
    Reset defaultReset <- exposeCurrentReset();

    Vector#(NUM_OF_ALTERA_PORTS, EthMacIfc) eth_mac;

	for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
	begin
		eth_mac[i] <- mkEthMac(defaultClock, txClock, rxClock, tx_reset);
	end

    //interface FIFOs
    Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(RingBufferDataT))
        mac_rx_read_res_fifo;
    Vector#(NUM_OF_ALTERA_PORTS, FIFO#(RingBufferDataT))
        mac_tx_write_req_fifo;

    for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
    begin
        mac_rx_read_res_fifo[i]
            <- mkSyncFIFO(2, rxClock, rx_reset, txClock);
        mac_tx_write_req_fifo[i]
            <- mkFIFO(clocked_by txClock, reset_by tx_reset);
    end

`ifdef WAIT_FOR_START_SIG
    Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(Bit#(1))) start_scheduler_fifo
        <- replicateM(mkSyncFIFO(1, rxClock, rx_reset, txClock));

    Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(Bit#(1))) start_counting_fifo
        <- replicateM(mkSyncFIFO(1, rxClock, rx_reset, txClock));
`endif

    Integer bus_chunks = valueof(BUS_WIDTH) / valueof(BITS_PER_CYCLE);

/*------------------------------------------------------------------------------*/

                                /* Clock */

/*------------------------------------------------------------------------------*/
    Reg#(Bit#(64)) tx_counter <- mkReg(0, clocked_by txClock, reset_by tx_reset);

    rule tx_clk;
        tx_counter <= tx_counter + 1;
    endrule

    Reg#(Bit#(64)) rx_counter <- mkReg(0, clocked_by rxClock, reset_by rx_reset);

    rule rx_clk;
        rx_counter <= rx_counter + 1;
    endrule
/*------------------------------------------------------------------------------*/

                                /* Tx Path */

/*------------------------------------------------------------------------------*/

    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(16)))
        turn <- replicateM(mkReg(0, clocked_by txClock, reset_by tx_reset));

    Vector#(NUM_OF_ALTERA_PORTS, Vector#(8, FIFO#(PacketDataT#(BITS_PER_CYCLE))))
        tx_data <- replicateM(replicateM
            (mkPipelineFIFO(clocked_by txClock, reset_by tx_reset)));

    //Tx stats
	Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(Bit#(64)))
        blocks_transmitted_from_mac_fifo
            <- replicateM(mkSyncFIFO(1, txClock, tx_reset, defaultClock));

    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(64)))
        num_of_blocks_transmitted_from_mac
            <- replicateM(mkReg(0, clocked_by txClock, reset_by tx_reset));

`ifdef NIC_SIM
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(64)))
        cell_count <- replicateM(mkReg(0, clocked_by txClock, reset_by tx_reset));

    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(1)))
        skip_blocks <- replicateM(mkReg(0, clocked_by txClock, reset_by tx_reset));
`endif

/*------------------------------------------------------------------------------*/

    for (Integer i = 0; i < fromInteger(valueof(NUM_OF_ALTERA_PORTS)); i = i + 1)
    begin
		rule handle_mac_tx_write_req;
            let d <- toGet(mac_tx_write_req_fifo[i]).get;

`ifdef NIC_SIM
            if (False)
                skip_blocks[i] <= 1;
            else
                skip_blocks[i] <= 0;

            cell_count[i] <= cell_count[i] + 1;
`endif

            Bit#(1) sop = 0;
            Bit#(1) eop = 0;

            for (Integer j = 0; j < bus_chunks; j = j + 1)
            begin
                if (j == 0) sop = d.sop;
                else sop = 0;
                if (j == bus_chunks-1) eop = d.eop;
                else eop = 0;

                Integer s = valueof(BUS_WIDTH) - 1 - (j * valueof(BITS_PER_CYCLE));
                Integer e = (valueof(BUS_WIDTH) - valueof(BITS_PER_CYCLE))
                    - (j * valueof(BITS_PER_CYCLE));

                PacketDataT#(BITS_PER_CYCLE) block = PacketDataT {
                    data : d.payload[s:e],
                    mask : 0,
                    sop  : sop,
                    eop  : eop
                };

                tx_data[i][j].enq(block);
            end
		endrule

        for (Integer j = 0; j < bus_chunks; j = j + 1)
        begin
            rule send_to_lower_layer (turn[i] == fromInteger(j));
                let d <- toGet(tx_data[i][j]).get;

`ifdef NIC_SIM
                if (host_index == 1 && skip_blocks[i] == 1)
                begin
                    if (j > 2)
                    begin
                        eth_mac[i].packet_tx.put(d);
                        if (verbose)
                            $display("[MAC %d] t = %d data sent to mac = %d %d %x",
                                host_index, tx_counter, d.sop, d.eop, d.data);
                    end
                end

                else
                begin
                    eth_mac[i].packet_tx.put(d);
                    if (verbose && i == 0)
                        $display("[MAC %d] t = %d data sent to mac = %d %d %x",
                            host_index, tx_counter, d.sop, d.eop, d.data);
                end
`endif

`ifdef HW_DE5
                eth_mac[i].packet_tx.put(d);
`endif

                num_of_blocks_transmitted_from_mac[i]
                    <= num_of_blocks_transmitted_from_mac[i] + 1;

                turn[i] <= (turn[i] + 1) & (fromInteger(bus_chunks) - 1); //mod 8
            endrule
        end
    end

/*------------------------------------------------------------------------------*/

                                /* Rx Path */

/*------------------------------------------------------------------------------*/

    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(BUS_WIDTH))) rx_data;
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(16))) offset;
    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(1))) sop;

    //Rx stats
	Vector#(NUM_OF_ALTERA_PORTS, SyncFIFOIfc#(Bit#(64)))
        blocks_received_by_mac_fifo;

    Vector#(NUM_OF_ALTERA_PORTS, Reg#(Bit#(64))) num_of_blocks_received_by_mac;

	for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
	begin
		rx_data[i] <- mkReg(0, clocked_by rxClock, reset_by rx_reset);
		offset[i] <- mkReg(fromInteger(bus_chunks),
            clocked_by rxClock, reset_by rx_reset);
		sop[i] <- mkReg(0, clocked_by rxClock, reset_by rx_reset);
        blocks_received_by_mac_fifo[i]
            <- mkSyncFIFO(1, rxClock, rx_reset, defaultClock);
        num_of_blocks_received_by_mac[i] <- mkReg(0,
            clocked_by rxClock, reset_by rx_reset);
	end

/*------------------------------------------------------------------------------*/

    for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
    begin
        rule stitch_blocks_together;
            let d <- eth_mac[i].packet_rx.get;

`ifdef NIC_SIM
            if (verbose && i == 1)
                $display("[MAC %d] t = %d recvd = %d %d %x",
                    host_index, rx_counter, d.sop, d.eop, d.data);
`endif

`ifdef WAIT_FOR_START_SIG
            /* start signal received */
            if (num_of_blocks_received_by_mac[i] == 0)
            begin
                if (d.sop == 0 && d.eop == 1)
                begin
                    start_scheduler_fifo[i].enq(1);
                    start_counting_fifo[i].enq(1);
`ifdef NIC_SIM
                    if (verbose)
                        $display("[MAC %d] t = %d Started Scheduler",
                            host_index, rx_counter);
`endif
                    num_of_blocks_received_by_mac[i]
                        <= num_of_blocks_received_by_mac[i] + 1;
                end
            end

            else
`else
            if (True)
`endif
            begin
                num_of_blocks_received_by_mac[i]
                    <= num_of_blocks_received_by_mac[i] + 1;

                Bit#(16) curr_offset = offset[i];
                Bit#(1) curr_sop = sop[i];

                if (d.sop == 1) curr_sop = 1;

                //stitch data blocks
                Bit#(BUS_WIDTH) curr_rx_data = rx_data[i];
                Bit#(BUS_WIDTH) data = '0;
                data = data | zeroExtend(d.data);
                data = data << ((curr_offset-1) << log2(valueof(BITS_PER_CYCLE)));
                if (curr_offset == fromInteger(bus_chunks))
                    rx_data[i] <= data;
                else
                begin
                    curr_rx_data = curr_rx_data | data;
                    rx_data[i] <= curr_rx_data;
                end

                //send stitched block
                if (d.eop == 1 || curr_offset == 1)
                begin
                    RingBufferDataT stitched_data = RingBufferDataT {
                        sop     : curr_sop,
                        eop     : d.eop,
                        payload : curr_rx_data
                    };
                    if (verbose && i == 1)
                        $display("Sending to sched %d %d %x",
                            stitched_data.sop, stitched_data.eop,
                            stitched_data.payload);
                    mac_rx_read_res_fifo[i].enq(stitched_data);
                    //reset state
                    offset[i] <= fromInteger(bus_chunks);
                    sop[i] <= 0;
                end
                else
                begin
                    offset[i] <= curr_offset - 1;
                    sop[i] <= curr_sop;
                end
            end
        endrule
    end

/*------------------------------------------------------------------------------*/

                            /* Interface Methods */

/*------------------------------------------------------------------------------*/

    Vector#(NUM_OF_ALTERA_PORTS, Get#(RingBufferDataT)) temp1;
    Vector#(NUM_OF_ALTERA_PORTS, Put#(RingBufferDataT)) temp2;
    Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64))) temp3;
    Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(64))) temp4;
`ifdef WAIT_FOR_START_SIG
    Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(1))) temp5;
    Vector#(NUM_OF_ALTERA_PORTS, Get#(Bit#(1))) temp6;
`endif

    for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
    begin
        temp1[i] = toGet(mac_rx_read_res_fifo[i]);
        temp2[i] = toPut(mac_tx_write_req_fifo[i]);
        temp3[i] = toGet(blocks_transmitted_from_mac_fifo[i]);
        temp4[i] = toGet(blocks_received_by_mac_fifo[i]);
`ifdef WAIT_FOR_START_SIG
        temp5[i] = toGet(start_scheduler_fifo[i]);
        temp6[i] = toGet(start_counting_fifo[i]);
`endif
    end

    method Bit#(72) tx(Integer port_index);
        let v = eth_mac[port_index].tx;
        return v;
    endmethod

    method Action rx(Integer port_index, Bit#(72) v);
        eth_mac[port_index].rx(v);
    endmethod

    method Action getBlocksTransmittedFromMac();
        for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
            blocks_transmitted_from_mac_fifo[i].enq
                (num_of_blocks_transmitted_from_mac[i]);
    endmethod

    method Action getBlocksReceivedByMac();
        for (Integer i = 0; i < valueof(NUM_OF_ALTERA_PORTS); i = i + 1)
            blocks_received_by_mac_fifo[i].enq(num_of_blocks_received_by_mac[i]);
    endmethod

    method Bit#(64) getTxClock();
        return tx_counter;
    endmethod

    method Bit#(64) getRxClock();
        return rx_counter;
    endmethod

    interface mac_rx_read_res = temp1;
    interface mac_tx_write_req = temp2;
    interface blocks_transmitted_from_mac = temp3;
    interface blocks_received_by_mac = temp4;
`ifdef WAIT_FOR_START_SIG
    interface start_scheduler = temp5;
    interface start_counting = temp6;
`endif

endmodule
