import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import GetPut::*;
import Clocks::*;
import DefaultValue::*;

`include "ConnectalProjectConfig.bsv"

import SwParams::*;

import AlteraMacWrap::*;
import EthMac::*;
`ifndef CW_PHY_SIM
import Ethernet::*;
import AlteraEthPhy::*;
`endif

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

interface PhySwitch;
    interface Vector#(NUM_OF_SWITCH_PORTS, Put#(Bit#(1))) tx_port_stats_req;
    interface Vector#(NUM_OF_SWITCH_PORTS, Put#(Bit#(1))) rx_port_stats_req;
    interface Vector#(NUM_OF_SWITCH_PORTS, Get#(PortStatsT)) tx_port_stats_res;
    interface Vector#(NUM_OF_SWITCH_PORTS, Get#(PortStatsT)) rx_port_stats_res;

    interface Vector#(NUM_OF_SWITCH_PORTS, Put#(Bit#(1))) latency_req;
    interface Vector#(NUM_OF_SWITCH_PORTS, Get#(Bit#(64))) latency_res;

    method Action start(Bit#(1) reconfig, Bit#(64) t);

`ifdef CW_PHY_SIM
    interface Vector#(NUM_OF_SWITCH_PORTS, Get#(Bit#(72))) phyTx;
    interface Vector#(NUM_OF_SWITCH_PORTS, Put#(Bit#(72))) phyRx;
`endif
endinterface

`ifndef CW_PHY_SIM
module mkPhySwitch#(EthPhyIfc phys,
            Clock txClock,
            Reset txReset,
            Reset tx_reset,
			Clock rxClock,
		    Reset rxReset,
            Reset rx_reset) (PhySwitch);
`else
module mkPhySwitch#(Clock txClock,
            Reset txReset,
            Reset tx_reset,
			Clock rxClock,
		    Reset rxReset,
            Reset rx_reset) (PhySwitch);
`endif

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
    Vector#(NUM_OF_SWITCH_PORTS, SyncFIFOIfc#(Bit#(1))) latency_req_fifo;
    Vector#(NUM_OF_SWITCH_PORTS, SyncFIFOIfc#(Bit#(64))) latency_res_fifo;
`ifdef CW_PHY_SIM
    Vector#(NUM_OF_SWITCH_PORTS, FIFO#(Bit#(72))) phyTx_fifo;
    Vector#(NUM_OF_SWITCH_PORTS, FIFO#(Bit#(72))) phyRx_fifo;
`endif

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
        latency_req_fifo[i]
            <- mkSyncFIFO(1, defaultClock, defaultReset, txClock);
        latency_res_fifo[i]
            <- mkSyncFIFO(1, txClock, txReset, defaultClock);
`ifdef CW_PHY_SIM
        phyTx_fifo[i]
            <- mkBypassFIFO(clocked_by txClock, reset_by txReset);
        phyRx_fifo[i]
            <- mkBypassFIFO(clocked_by rxClock, reset_by rxReset);
`endif
    end

    //Port stats variables
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(PortStatsT)) tx_stats;
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(PortStatsT)) rx_stats;

    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(1))) tx_count_blocks;
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(16))) tx_block_count;

    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(1))) rx_count_blocks;
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(16))) rx_block_count;

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
    Vector#(NUM_OF_SWITCH_PORTS, SyncFIFOIfc#(Bit#(72))) data;

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
        <- mkReg(0, clocked_by txClock, reset_by tx_reset);

    rule tx_clk;
        tx_counter <= tx_counter + 1;
    endrule

    Reg#(Bit#(64)) rx_counter
        <- mkReg(0, clocked_by rxClock, reset_by rx_reset);

    rule rx_clk;
        rx_counter <= rx_counter + 1;
    endrule

/*------------------------------------------------------------------------------*/

                            /* Initialization */

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
            circuit[i] <= schedule_table[i][0];
        end
        if (verbose)
            $display("t = %d Initial circuit configuration done..", rx_counter);
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
    end

/*------------------------------------------------------------------------------*/

                                /* Switching */

/*------------------------------------------------------------------------------*/

    Integer chunks = valueof(CELL_SIZE) / valueof(BITS_PER_CYCLE);

    Vector#(NUM_OF_SWITCH_PORTS, FIFO#(Bit#(72)))
        temp_rx_fifo <- replicateM(mkSizedFIFO(2,
            clocked_by rxClock, reset_by rx_reset));

    Vector#(NUM_OF_SWITCH_PORTS, Reg#(PortIndex))
        timeslot <- replicateM(mkReg(0, clocked_by rxClock, reset_by rx_reset));

    for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1) //rx port
    begin
        rule rx_stat_collection;
            let d <- eth_mac[i].packet_rx.get;

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

        rule circuit_reconfig;
            let d <- toGet(reconfigure[i]).get;
            circuit[i] <= schedule_table[i][timeslot[i]];
            timeslot[i] <= (timeslot[i] + 1)
                % fromInteger(valueof(NUM_OF_SWITCH_PORTS)-1);
            if (verbose)
                $display("t = %d i = %d j = %d",
                    rx_counter, i, schedule_table[i][timeslot[i]]);
        endrule

        rule receive_data;
`ifndef CW_PHY_SIM
            let d <- phys.rx[i].get;
`else
            let d <- toGet(phyRx_fifo[i]).get;
`endif
            /* received 1st block of new cell */
            if (reconfig_flag == 1 && d == 'h6a954aa552a954abfb)
            begin
                reconfigure[i].enq(?);
            end
            temp_rx_fifo[i].enq(d);
            if (verbose && d == 'h6a954aa552a954abfb)
                $display("[SW] t = %d Putting data into temp_rx_fifo", rx_counter);
            eth_mac[i].rx(d);
        endrule

/*------------------------------------------------------------------------------*/
        for (Integer j = 0; j < valueof(NUM_OF_SWITCH_PORTS); j = j + 1) //tx port
        begin
            rule send_data_to_tx (circuit[i] == fromInteger(j));
                let d <- toGet(temp_rx_fifo[i]).get;
                data[j].enq(d);
                if (verbose && d == 'h6a954aa552a954abfb)
                    $display("[SW] t = %d Sending to tx", rx_counter);
            endrule
        end
    end

/*------------------------------------------------------------------------------*/

    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(64)))
        latency_reg <- replicateM(mkReg(0, clocked_by txClock, reset_by tx_reset));

    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(64)))
        start_time <- replicateM(mkReg(0, clocked_by txClock, reset_by tx_reset));

    for (Integer j = 0; j < valueof(NUM_OF_SWITCH_PORTS); j = j + 1)
    begin

    (* descending_urgency = "transmit_start_signal, transmit_data, transmit_idle" *)

        rule transmit_start_signal (turn[j] < 10);
            turn[j] <= turn[j] + 1;
            case (turn[j])
`ifndef CW_PHY_SIM
                0: phys.tx[j].put('h6a954aa552a954abfb);
                1: phys.tx[j].put('h008000000000000000);
                2: phys.tx[j].put('h000000000000000000);
                3: phys.tx[j].put('h000000000000000000);
                4: phys.tx[j].put('h000000000000000000);
                5: phys.tx[j].put('h000000000000000000);
                6: phys.tx[j].put('h000000000000000000);
                7: phys.tx[j].put('h000000000000000000);
                8: phys.tx[j].put('h000000000000000000);
                9: phys.tx[j].put('h83c1e0ffd3689d6252);
`else
                0: phyTx_fifo[j].enq('h6a954aa552a954abfb);
                1: phyTx_fifo[j].enq('h008000000000000000);
                2: phyTx_fifo[j].enq('h000000000000000000);
                3: phyTx_fifo[j].enq('h000000000000000000);
                4: phyTx_fifo[j].enq('h000000000000000000);
                5: phyTx_fifo[j].enq('h000000000000000000);
                6: phyTx_fifo[j].enq('h000000000000000000);
                7: phyTx_fifo[j].enq('h000000000000000000);
                8: phyTx_fifo[j].enq('h000000000000000000);
                9: phyTx_fifo[j].enq('h83c1e0ffd3689d6252);
`endif
            endcase
            if (turn[j] == 0)
                start_time[j] <= tx_counter;
            if (verbose && turn[j] == 9)
                $display("Sent start signal to server = %d", j);
        endrule

        rule transmit_data;
            let d <- toGet(data[j]).get;
            if (verbose && d == 'h6a954aa552a954abfb)
                $display("[SW] t = %d Recvd from rx", tx_counter);
            if (d == 'h6a954aa552a954abfb && latency_reg[j] == 0)
                latency_reg[j] <= tx_counter - start_time[j];
`ifndef CW_PHY_SIM
            phys.tx[j].put(d);
`else
            phyTx_fifo[j].enq(d);
`endif
        endrule

        rule transmit_idle;
`ifndef CW_PHY_SIM
            phys.tx[j].put('h83c1e0f0783c1e0f07);
`else
            phyTx_fifo[j].enq('h83c1e0f0783c1e0f07);
`endif
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

        rule handle_latency_req;
            let d <- toGet(latency_req_fifo[i]).get;
            latency_res_fifo[i].enq(latency_reg[i]);
        endrule
    end

    Vector#(NUM_OF_SWITCH_PORTS, Put#(Bit#(1))) temp1;
    Vector#(NUM_OF_SWITCH_PORTS, Put#(Bit#(1))) temp2;
    Vector#(NUM_OF_SWITCH_PORTS, Get#(PortStatsT)) temp3;
    Vector#(NUM_OF_SWITCH_PORTS, Get#(PortStatsT)) temp4;
    Vector#(NUM_OF_SWITCH_PORTS, Put#(Bit#(1))) temp5;
    Vector#(NUM_OF_SWITCH_PORTS, Get#(Bit#(64))) temp6;
`ifdef CW_PHY_SIM
    Vector#(NUM_OF_SWITCH_PORTS, Get#(Bit#(72))) temp7;
    Vector#(NUM_OF_SWITCH_PORTS, Put#(Bit#(72))) temp8;
`endif

    for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1)
    begin
        temp1[i] = toPut(tx_port_stats_req_fifo[i]);
        temp2[i] = toPut(rx_port_stats_req_fifo[i]);
        temp3[i] = toGet(tx_port_stats_res_fifo[i]);
        temp4[i] = toGet(rx_port_stats_res_fifo[i]);
        temp5[i] = toPut(latency_req_fifo[i]);
        temp6[i] = toGet(latency_res_fifo[i]);
`ifdef CW_PHY_SIM
        temp7[i] = toGet(phyTx_fifo[i]);
        temp8[i] = toPut(phyRx_fifo[i]);
`endif
    end

    method Action start(Bit#(1) flag, Bit#(64) t);
        reconfig_flag <= flag;
        timeslot_len <= t;
        start_flag <= 1;
    endmethod

    interface tx_port_stats_req = temp1;
    interface rx_port_stats_req = temp2;
    interface tx_port_stats_res = temp3;
    interface rx_port_stats_res = temp4;
    interface latency_req = temp5;
    interface latency_res = temp6;
`ifdef CW_PHY_SIM
    interface phyTx = temp7;
    interface phyRx = temp8;
`endif
endmodule
