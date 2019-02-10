import FIFO::*;
import FIFOF::*;
import Vector::*;
import SpecialFIFOs::*;
import GetPut::*;
import Clocks::*;
import DefaultValue::*;

import SwParams::*;

import AlteraMacWrap::*;
import EthMac::*;

`include "ConnectalProjectConfig.bsv"

typedef struct {
    Bit#(64) sop; //number of sop recvd/transmitted
    Bit#(64) eop; //number of eop recvd/transmitted
    Bit#(64) blocks; //number of data blocks recvd/transmitted
    Bit#(64) cells; //number of cells recvd/transmitted
} PortStatsT deriving(Bits, Eq);

instance DefaultValue#(PortStatsT);
    defaultValue = PortStatsT {
        sop    : 0,
        eop    : 0,
        blocks : 0,
        cells  : 0
    };
endinstance

interface MacSwitch;
    interface Vector#(NUM_OF_SWITCH_PORTS, Put#(Bit#(1))) tx_port_stats_req;
    interface Vector#(NUM_OF_SWITCH_PORTS, Put#(Bit#(1))) rx_port_stats_req;
    interface Vector#(NUM_OF_SWITCH_PORTS, Get#(PortStatsT)) tx_port_stats_res;
    interface Vector#(NUM_OF_SWITCH_PORTS, Get#(PortStatsT)) rx_port_stats_res;

    method Action start(Bit#(1) reconfig, Bit#(64) t);

    (* always_ready, always_enabled *)
    method Bit#(72) tx(Integer port_index);
    (* always_ready, always_enabled *)
    method Action rx(Integer port_index, Bit#(72) v);
endinterface

module mkMacSwitch#(Clock txClock,
            Reset txReset,
            Reset tx_reset,
			Clock rxClock,
		    Reset rxReset,
            Reset rx_reset) (MacSwitch);

    Bool verbose = False;

    Clock defaultClock <- exposeCurrentClock();
    Reset defaultReset <- exposeCurrentReset();

    Reg#(Bit#(1)) start_flag <- mkReg(0, clocked_by rxClock, reset_by rx_reset);
    Reg#(Bit#(1)) reconfig_flag <- mkReg(1, clocked_by rxClock, reset_by rx_reset);

    //Interface FIFOs
    Vector#(NUM_OF_SWITCH_PORTS, SyncFIFOIfc#(Bit#(1))) tx_port_stats_req_fifo;
    Vector#(NUM_OF_SWITCH_PORTS, SyncFIFOIfc#(Bit#(1))) rx_port_stats_req_fifo;
    Vector#(NUM_OF_SWITCH_PORTS, SyncFIFOIfc#(PortStatsT)) tx_port_stats_res_fifo;
    Vector#(NUM_OF_SWITCH_PORTS, SyncFIFOIfc#(PortStatsT)) rx_port_stats_res_fifo;

    for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1)
    begin
        tx_port_stats_req_fifo[i]
            <- mkSyncFIFO(1, defaultClock, defaultReset, txClock);
        tx_port_stats_res_fifo[i]
            <- mkSyncFIFO(1, txClock, txReset, defaultClock);
        rx_port_stats_req_fifo[i]
            <- mkSyncFIFO(1, defaultClock, defaultReset, rxClock);
        rx_port_stats_res_fifo[i]
            <- mkSyncFIFO(1, rxClock, rxReset, defaultClock);
    end

    //Port stats variables
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(PortStatsT)) tx_stats;
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(PortStatsT)) rx_stats;

    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(1))) tx_count_blocks;
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(16))) tx_block_count;

    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(1))) rx_count_blocks;
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(16))) rx_block_count;

    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(BITS_PER_CYCLE))) tx_curr_header;
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(BITS_PER_CYCLE))) rx_curr_header;

    for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1)
    begin
        tx_stats[i]
            <- mkReg(defaultValue, clocked_by txClock, reset_by tx_reset);
        rx_stats[i]
            <- mkReg(defaultValue, clocked_by rxClock, reset_by rx_reset);

        tx_count_blocks[i]
            <- mkReg(0, clocked_by txClock, reset_by tx_reset);
        tx_block_count[i]
            <- mkReg(0, clocked_by txClock, reset_by tx_reset);

        rx_count_blocks[i]
            <- mkReg(0, clocked_by rxClock, reset_by rx_reset);
        rx_block_count[i]
            <- mkReg(0, clocked_by rxClock, reset_by rx_reset);

        tx_curr_header[i]
            <- mkReg(0, clocked_by txClock, reset_by tx_reset);
        rx_curr_header[i]
            <- mkReg(0, clocked_by rxClock, reset_by rx_reset);
    end

    //Altera Mac
    Vector#(NUM_OF_SWITCH_PORTS, EthMacIfc) eth_mac;

	for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1)
	begin
		eth_mac[i] <- mkEthMac(defaultClock, txClock, rxClock, tx_reset);
	end

    //Rx-Tx-inter-connecting SyncFIFOs
    Vector#(NUM_OF_SWITCH_PORTS, SyncFIFOIfc#(PacketDataT#(BITS_PER_CYCLE))) data;

    Vector#(NUM_OF_SWITCH_PORTS, Reg#(PortIndex)) circuit;

    Vector#(NUM_OF_SWITCH_PORTS, FIFO#(void)) reconfigure;

    for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1)
    begin
        reconfigure[i] <- mkBypassFIFO(clocked_by rxClock, reset_by rx_reset);
        circuit[i] <- mkReg(maxBound, clocked_by rxClock, reset_by rx_reset);
        data[i] <- mkSyncFIFO(8, rxClock, rxReset, txClock);
    end

/*------------------------------------------------------------------------------*/

                                   /* Clocks */

/*------------------------------------------------------------------------------*/

    //Clocks
    Reg#(Bit#(64)) tx_counter
        <- mkReg(1, clocked_by txClock, reset_by tx_reset);

    rule tx_clk;
        tx_counter <= tx_counter + 1;
    endrule

    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(1))) start_rx_counter
        <- replicateM(mkReg(0, clocked_by rxClock, reset_by rx_reset));
    Reg#(Bit#(64)) rx_counter
        <- mkReg(1, clocked_by rxClock, reset_by rx_reset);

    rule rx_clk (start_rx_counter[0] == 1
                || start_rx_counter[1] == 1
                || start_rx_counter[2] == 1
                || start_rx_counter[3] == 1);
        rx_counter <= rx_counter + 1;
    endrule

    Reg#(Bit#(64)) rx_counter1
        <- mkReg(1, clocked_by rxClock, reset_by rx_reset);

    rule rx_clk1;
        rx_counter1 <= rx_counter1 + 1;
    endrule

/*------------------------------------------------------------------------------*/

                            /* Reconfiguration */

/*------------------------------------------------------------------------------*/

    Reg#(Bit#(64)) timeslot_len
        <- mkReg(0, clocked_by rxClock, reset_by rx_reset);

    //schedule
	Vector#(NUM_OF_SWITCH_PORTS, Vector#(NUM_OF_SWITCH_PORTS, Reg#(PortIndex)))
        schedule_table <- replicateM(replicateM
            (mkReg(0, clocked_by rxClock, reset_by rx_reset)));

    Reg#(Bit#(1)) once <- mkReg(1, clocked_by rxClock, reset_by rx_reset);

    Reg#(Bit#(1)) init_circuit <- mkReg(0, clocked_by rxClock, reset_by rx_reset);

    SyncFIFOIfc#(Bit#(1)) start_signal_fifo
        <- mkSyncFIFO(1, rxClock, rxReset, txClock);

    rule populate_schedule_table (start_flag == 1 && once == 1);
        once <= 0;
        for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1) //Port
        begin
            for (Integer j = 0; j < valueof(NUM_OF_SWITCH_PORTS)-1; j = j + 1) //t
            begin
                schedule_table[i][j] <= (fromInteger(i) + fromInteger(j) + 1)
                        % fromInteger(valueof(NUM_OF_SWITCH_PORTS));
            end
        end
        init_circuit <= 1;
        start_signal_fifo.enq(1);
    endrule

    rule initial_circuit_configuration (init_circuit == 1);
        init_circuit <= 0;
        /* initial circuit configuration */
        for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1)
        begin
            circuit[i]<= schedule_table[i][0];
        end
        if (verbose)
            $display("t = %d Initial circuit configuration done..", rx_counter1);
    endrule

    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(16)))
        turn <- replicateM(mkReg(maxBound, clocked_by txClock, reset_by tx_reset));

    rule send_start_signal_init;
        let d <- toGet(start_signal_fifo).get;
        /* Send start signal on each port */
        for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1)
        begin
            turn[i] <= 0;
        end
    endrule

    for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1)
    begin
        rule send_start_signal (turn[i] < 8);
            turn[i] <= turn[i] + 1;
            Bit#(1) sop = 0;
            Bit#(1) eop = 0;
            Bit#(64) data = '0;
            if (turn[i] == 0)
            begin
                sop = 1;
                data[0] = 1; //dummy bit
            end
            if (turn[i] == 7)
                eop = 1;
            PacketDataT#(BITS_PER_CYCLE) d = PacketDataT {
                data : data,
                mask : 0,
                sop  : sop,
                eop  : eop
            };
            eth_mac[i].packet_tx.put(d);
            if (verbose && turn[i] == 7)
                $display("Sent start signal to server = %d", i);
        endrule
    end

/*------------------------------------------------------------------------------*/

                                /* Switching */

/*------------------------------------------------------------------------------*/

    Integer chunks = valueof(CELL_SIZE) / valueof(BITS_PER_CYCLE);

    Vector#(NUM_OF_SWITCH_PORTS, Reg#(PortIndex))
        timeslot <- replicateM(mkReg(1, clocked_by rxClock, reset_by rx_reset));

    for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1) //rx port
    begin
        rule circuit_config;
            let d <- toGet(reconfigure[i]).get;
            circuit[i] <= schedule_table[i][timeslot[i]];
            timeslot[i] <= (timeslot[i] + 1)
                % fromInteger(valueof(NUM_OF_SWITCH_PORTS)-1);
            if (verbose)
                $display("t = %d i = %d j = %d",
                    rx_counter1, i, schedule_table[i][timeslot[i]]);
        endrule

/*------------------------------------------------------------------------------*/
        for (Integer j = 0; j < valueof(NUM_OF_SWITCH_PORTS); j = j + 1) //tx port
        begin
            rule receive_data (circuit[i] == fromInteger(j));
`ifdef CW_SIM
                PacketDataT#(BITS_PER_CYCLE) d = defaultValue;
`else
                let d <- eth_mac[i].packet_rx.get;
`endif
                if (verbose && i == 0)
                    $display("[Rx %d] RxPort-%d txPort-%d data=%d %d %x",
                        rx_counter1, i, j, d.sop, d.eop, d.data);

                /* received 1st cell */
                if (start_rx_counter[i] == 0)
                begin
                    start_rx_counter[i] <= 1;
                    if (verbose)
                        $display("t = %d Received 1st cell i = %d", rx_counter1, i);
                end

                if (reconfig_flag == 1 && d.eop == 1)
                    reconfigure[i].enq(?);

                data[j].enq(d);

                /* rx port stats */
                Bit#(64) sop = rx_stats[i].sop;
                Bit#(64) eop = rx_stats[i].eop;
                Bit#(64) blocks = rx_stats[i].blocks;
                Bit#(64) cells = rx_stats[i].cells;

                if (d.sop == 1 && d.eop == 0)
                begin
                    sop = sop + 1;
                    rx_count_blocks[i] <= 1;
                    rx_block_count[i] <= 1;
                    rx_curr_header[i] <= d.data;
                end

                else if (d.sop == 0 && d.eop == 1)
                begin
                    eop = eop + 1;
                    if (rx_block_count[i] == fromInteger(chunks) - 1)
                        cells = cells + 1; //assumes fixed sized cells
                    rx_count_blocks[i] <= 0;
                end

                else
                begin
                    if (rx_count_blocks[i] == 1 && d.data == rx_curr_header[i])
                        rx_block_count[i] <= rx_block_count[i] + 1;
                end

                rx_stats[i] <= PortStatsT {
                    sop    : sop,
                    eop    : eop,
                    blocks : blocks + 1,
                    cells  : cells
                };
            endrule
        end
    end

/*------------------------------------------------------------------------------*/

    for (Integer j = 0; j < valueof(NUM_OF_SWITCH_PORTS); j = j + 1)
    begin
        rule transmit_data;
            let d <- toGet(data[j]).get;

            PacketDataT#(BITS_PER_CYCLE) block = PacketDataT {
                data : d.data,
                mask : 0,
                sop  : d.sop,
                eop  : d.eop
            };

`ifndef CW_SIM
            eth_mac[j].packet_tx.put(block);
`endif

            if (verbose && j == 1)
                $display("[Tx %d] txPort-%d data=%d %d %x",
                    tx_counter, j, d.sop, d.eop, d.data);

            /* tx port stats */
            Bit#(64) sop = tx_stats[j].sop;
            Bit#(64) eop = tx_stats[j].eop;
            Bit#(64) blocks = tx_stats[j].blocks;
            Bit#(64) cells = tx_stats[j].cells;

            if (d.sop == 1 && d.eop == 0)
            begin
                sop = sop + 1;
                tx_count_blocks[j] <= 1;
                tx_block_count[j] <= 1;
                tx_curr_header[j] <= d.data;
            end

            else if (d.sop == 0 && d.eop == 1)
            begin
                eop = eop + 1;
                if (tx_block_count[j] == fromInteger(chunks) - 1)
                    cells = cells + 1; //assumes fixed sized cells
                tx_count_blocks[j] <= 0;
            end

            else
            begin
                if (tx_count_blocks[j] == 1 && d.data == tx_curr_header[j])
                    tx_block_count[j] <= tx_block_count[j] + 1;
            end

            tx_stats[j] <= PortStatsT {
                sop    : sop,
                eop    : eop,
                blocks : blocks + 1,
                cells  : cells
            };
        endrule
    end

/*------------------------------------------------------------------------------*/

                                /* Interface */

/*------------------------------------------------------------------------------*/

    for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1)
    begin
        rule handle_tx_port_stats_req;
            let d <- toGet(tx_port_stats_req_fifo[i]).get;
            tx_port_stats_res_fifo[i].enq(tx_stats[i]);
        endrule

        rule handle_rx_port_stats_req;
            let d <- toGet(rx_port_stats_req_fifo[i]).get;
            rx_port_stats_res_fifo[i].enq(rx_stats[i]);
        endrule
    end

    Vector#(NUM_OF_SWITCH_PORTS, Put#(Bit#(1))) temp1;
    Vector#(NUM_OF_SWITCH_PORTS, Put#(Bit#(1))) temp2;
    Vector#(NUM_OF_SWITCH_PORTS, Get#(PortStatsT)) temp3;
    Vector#(NUM_OF_SWITCH_PORTS, Get#(PortStatsT)) temp4;

    for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1)
    begin
        temp1[i] = toPut(tx_port_stats_req_fifo[i]);
        temp2[i] = toPut(rx_port_stats_req_fifo[i]);
        temp3[i] = toGet(tx_port_stats_res_fifo[i]);
        temp4[i] = toGet(rx_port_stats_res_fifo[i]);
    end

    method Bit#(72) tx(Integer port_index);
        let v = eth_mac[port_index].tx;
        return v;
    endmethod

    method Action rx(Integer port_index, Bit#(72) v);
        eth_mac[port_index].rx(v);
    endmethod

    method Action start(Bit#(1) flag, Bit#(64) t);
        reconfig_flag <= flag;
        timeslot_len <= t;
        start_flag <= 1;
    endmethod

    interface tx_port_stats_req = temp1;
    interface rx_port_stats_req = temp2;
    interface tx_port_stats_res = temp3;
    interface rx_port_stats_res = temp4;
endmodule
