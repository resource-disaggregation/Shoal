import FIFO::*;
import FIFOF::*;
import Vector::*;
import GetPut::*;
import Connectable::*;
import DefaultValue::*;
import Clocks::*;

`include "ConnectalProjectConfig.bsv"

import SwParams::*;
`ifdef PHY_SW
import PhySwitch::*;
`endif
`ifdef MAC_SW
import MacSwitch::*;
`endif

import Ethernet::*;
import AlteraMacWrap::*;
import EthMac::*;
`ifdef PHY_SW
import AlteraEthPhy::*;
`endif

interface CircuitSwTopSimIndication;
    method Action display_tx_port_0_stats
        (Bit#(64) sop, Bit#(64) eop, Bit#(64) blocks, Bit#(64) cells);
    method Action display_tx_port_1_stats
        (Bit#(64) sop, Bit#(64) eop, Bit#(64) blocks, Bit#(64) cells);
    method Action display_tx_port_2_stats
        (Bit#(64) sop, Bit#(64) eop, Bit#(64) blocks, Bit#(64) cells);
    method Action display_tx_port_3_stats
        (Bit#(64) sop, Bit#(64) eop, Bit#(64) blocks, Bit#(64) cells);
    method Action display_rx_port_0_stats
        (Bit#(64) sop, Bit#(64) eop, Bit#(64) blocks, Bit#(64) cells);
    method Action display_rx_port_1_stats
        (Bit#(64) sop, Bit#(64) eop, Bit#(64) blocks, Bit#(64) cells);
    method Action display_rx_port_2_stats
        (Bit#(64) sop, Bit#(64) eop, Bit#(64) blocks, Bit#(64) cells);
    method Action display_rx_port_3_stats
        (Bit#(64) sop, Bit#(64) eop, Bit#(64) blocks, Bit#(64) cells);
`ifdef PHY_SW
    method Action display_latency_port_0_stats(Bit#(64) t);
    method Action display_latency_port_1_stats(Bit#(64) t);
    method Action display_latency_port_2_stats(Bit#(64) t);
    method Action display_latency_port_3_stats(Bit#(64) t);
`endif
endinterface

interface CircuitSwTopSimRequest;
    method Action startSwitching(Bit#(8) reconfig_flag, Bit#(64) timeslot);
	method Action printStats();
endinterface

interface CircuitSwTopSim;
    interface CircuitSwTopSimRequest request;
endinterface

module mkCircuitSwTopSim#(CircuitSwTopSimIndication indication)(CircuitSwTopSim);
    // Clocks
    Clock defaultClock <- exposeCurrentClock();
    Reset defaultReset <- exposeCurrentReset();

    Clock txClock <- mkAbsoluteClock(0, 15);
    Reset txReset <- mkAsyncReset(2, defaultReset, txClock);

`ifdef PHY_SW
    Clock mgmtClock <- mkAbsoluteClock(0, 15);
    Reset mgmtReset <- mkAsyncReset(2, defaultReset, mgmtClock);

    Clock phyClock <- mkAbsoluteClock(0, 64);
    Reset phyReset <- mkAsyncReset(2, defaultReset, phyClock);

    //Phy
    EthPhyIfc phys <- mkAlteraEthPhy(mgmtClock, phyClock, txClock, defaultReset, clocked_by mgmtClock, reset_by mgmtReset);

    Clock rxClock = phys.rx_clkout;
    Reset rxReset <- mkAsyncReset(2, defaultReset, rxClock);
`endif

`ifdef MAC_SW
    Clock rxClock <- mkAbsoluteClock(0, 64);
    Reset rxReset <- mkAsyncReset(2, defaultReset, rxClock);
`endif

/*-------------------------------------------------------------------------------*/

`ifdef PHY_SW
    PhySwitch sw <- mkPhySwitch(phys, txClock, txReset, txReset,
        rxClock, rxReset, rxReset);
`endif

`ifdef MAC_SW
    MacSwitch sw <- mkMacSwitch(txClock, txReset, txReset, rxClock, rxReset, rxReset);
`endif

/* ------------------------------------------------------------------------------
*                               INDICATION RULES
* ------------------------------------------------------------------------------*/
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(PortStatsT))
        tx_port_stats <- replicateM(mkReg(defaultValue));
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(1)))
        fire_send_tx_port_stats_to_connectal <- replicateM(mkReg(0));

    rule get_tx_port_0_stats_from_sw;
        let d <- sw.tx_port_stats_res[0].get;
        tx_port_stats[0] <= d;
        fire_send_tx_port_stats_to_connectal[0] <= 1;
    endrule

    rule send_tx_port_0_stats_to_connectal
            (fire_send_tx_port_stats_to_connectal[0] == 1);
        fire_send_tx_port_stats_to_connectal[0] <= 0;
        indication.display_tx_port_0_stats(tx_port_stats[0].sop,
                                        tx_port_stats[0].eop,
                                        tx_port_stats[0].blocks,
                                        tx_port_stats[0].cells);
    endrule
/*------------------------------------------------------------------------------*/
    rule get_tx_port_1_stats_from_sw;
        let d <- sw.tx_port_stats_res[1].get;
        tx_port_stats[1] <= d;
        fire_send_tx_port_stats_to_connectal[1] <= 1;
    endrule

    rule send_tx_port_1_stats_to_connectal
            (fire_send_tx_port_stats_to_connectal[1] == 1);
        fire_send_tx_port_stats_to_connectal[1] <= 0;
        indication.display_tx_port_1_stats(tx_port_stats[1].sop,
                                        tx_port_stats[1].eop,
                                        tx_port_stats[1].blocks,
                                        tx_port_stats[1].cells);
    endrule
/*------------------------------------------------------------------------------*/
    rule get_tx_port_2_stats_from_sw;
        let d <- sw.tx_port_stats_res[2].get;
        tx_port_stats[2] <= d;
        fire_send_tx_port_stats_to_connectal[2] <= 1;
    endrule

    rule send_tx_port_2_stats_to_connectal
            (fire_send_tx_port_stats_to_connectal[2] == 1);
        fire_send_tx_port_stats_to_connectal[2] <= 0;
        indication.display_tx_port_2_stats(tx_port_stats[2].sop,
                                        tx_port_stats[2].eop,
                                        tx_port_stats[2].blocks,
                                        tx_port_stats[2].cells);
    endrule
/*------------------------------------------------------------------------------*/
    rule get_tx_port_3_stats_from_sw;
        let d <- sw.tx_port_stats_res[3].get;
        tx_port_stats[3] <= d;
        fire_send_tx_port_stats_to_connectal[3] <= 1;
    endrule

    rule send_tx_port_3_stats_to_connectal
            (fire_send_tx_port_stats_to_connectal[3] == 1);
        fire_send_tx_port_stats_to_connectal[3] <= 0;
        indication.display_tx_port_3_stats(tx_port_stats[3].sop,
                                        tx_port_stats[3].eop,
                                        tx_port_stats[3].blocks,
                                        tx_port_stats[3].cells);
    endrule
/*------------------------------------------------------------------------------*/
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(PortStatsT))
        rx_port_stats <- replicateM(mkReg(defaultValue));
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(1)))
        fire_send_rx_port_stats_to_connectal <- replicateM(mkReg(0));

    rule get_rx_port_0_stats_from_sw;
        let d <- sw.rx_port_stats_res[0].get;
        rx_port_stats[0] <= d;
        fire_send_rx_port_stats_to_connectal[0] <= 1;
    endrule

    rule send_rx_port_0_stats_to_connectal
            (fire_send_rx_port_stats_to_connectal[0] == 1);
        fire_send_rx_port_stats_to_connectal[0] <= 0;
        indication.display_rx_port_0_stats(rx_port_stats[0].sop,
                                        rx_port_stats[0].eop,
                                        rx_port_stats[0].blocks,
                                        rx_port_stats[0].cells);
    endrule
/*------------------------------------------------------------------------------*/
    rule get_rx_port_1_stats_from_sw;
        let d <- sw.rx_port_stats_res[1].get;
        rx_port_stats[1] <= d;
        fire_send_rx_port_stats_to_connectal[1] <= 1;
    endrule

    rule send_rx_port_1_stats_to_connectal
            (fire_send_rx_port_stats_to_connectal[1] == 1);
        fire_send_rx_port_stats_to_connectal[1] <= 0;
        indication.display_rx_port_1_stats(rx_port_stats[1].sop,
                                        rx_port_stats[1].eop,
                                        rx_port_stats[1].blocks,
                                        rx_port_stats[1].cells);
    endrule
/*------------------------------------------------------------------------------*/
    rule get_rx_port_2_stats_from_sw;
        let d <- sw.rx_port_stats_res[2].get;
        rx_port_stats[2] <= d;
        fire_send_rx_port_stats_to_connectal[2] <= 1;
    endrule

    rule send_rx_port_2_stats_to_connectal
            (fire_send_rx_port_stats_to_connectal[2] == 1);
        fire_send_rx_port_stats_to_connectal[2] <= 0;
        indication.display_rx_port_2_stats(rx_port_stats[2].sop,
                                        rx_port_stats[2].eop,
                                        rx_port_stats[2].blocks,
                                        rx_port_stats[2].cells);
    endrule
/*------------------------------------------------------------------------------*/
    rule get_rx_port_3_stats_from_sw;
        let d <- sw.rx_port_stats_res[3].get;
        rx_port_stats[3] <= d;
        fire_send_rx_port_stats_to_connectal[3] <= 1;
    endrule

    rule send_rx_port_3_stats_to_connectal
            (fire_send_rx_port_stats_to_connectal[3] == 1);
        fire_send_rx_port_stats_to_connectal[3] <= 0;
        indication.display_rx_port_3_stats(rx_port_stats[3].sop,
                                        rx_port_stats[3].eop,
                                        rx_port_stats[3].blocks,
                                        rx_port_stats[3].cells);
    endrule
/*------------------------------------------------------------------------------*/
`ifdef PHY_SW
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(64)))
        latency_stats <- replicateM(mkReg(0));
    Vector#(NUM_OF_SWITCH_PORTS, Reg#(Bit#(1)))
        fire_send_latency_stats_to_connectal <- replicateM(mkReg(0));

    rule get_latency_port_0_stats_from_sw;
        let d <- sw.latency_res[0].get;
        latency_stats[0] <= d;
        fire_send_latency_stats_to_connectal[0] <= 1;
    endrule

    rule send_latency_port_0_stats_to_connectal
            (fire_send_rx_port_stats_to_connectal[0] == 1);
        fire_send_latency_stats_to_connectal[0] <= 0;
        indication.display_latency_port_0_stats(latency_stats[0]);
    endrule
/*------------------------------------------------------------------------------*/
    rule get_latency_port_1_stats_from_sw;
        let d <- sw.latency_res[1].get;
        latency_stats[1] <= d;
        fire_send_latency_stats_to_connectal[1] <= 1;
    endrule

    rule send_latency_port_1_stats_to_connectal
            (fire_send_rx_port_stats_to_connectal[1] == 1);
        fire_send_latency_stats_to_connectal[1] <= 0;
        indication.display_latency_port_1_stats(latency_stats[1]);
    endrule
/*------------------------------------------------------------------------------*/
    rule get_latency_port_2_stats_from_sw;
        let d <- sw.latency_res[2].get;
        latency_stats[2] <= d;
        fire_send_latency_stats_to_connectal[2] <= 1;
    endrule

    rule send_latency_port_2_stats_to_connectal
            (fire_send_rx_port_stats_to_connectal[2] == 1);
        fire_send_latency_stats_to_connectal[2] <= 0;
        indication.display_latency_port_2_stats(latency_stats[2]);
    endrule
/*------------------------------------------------------------------------------*/
    rule get_latency_port_3_stats_from_sw;
        let d <- sw.latency_res[3].get;
        latency_stats[3] <= d;
        fire_send_latency_stats_to_connectal[3] <= 1;
    endrule

    rule send_latency_port_3_stats_to_connectal
            (fire_send_rx_port_stats_to_connectal[3] == 1);
        fire_send_latency_stats_to_connectal[3] <= 0;
        indication.display_latency_port_3_stats(latency_stats[3]);
    endrule
`endif

/* ------------------------------------------------------------------------------
*                               INTERFACE METHODS
* ------------------------------------------------------------------------------*/
    Reg#(Bit#(1)) send_stat_request <- mkReg(0);
    SyncFIFOIfc#(Bit#(8)) reconfig_fifo
        <- mkSyncFIFO(1, defaultClock, defaultReset, rxClock);
    SyncFIFOIfc#(Bit#(64)) timeslot_fifo
        <- mkSyncFIFO(1, defaultClock, defaultReset, rxClock);

    rule start_switching;
        let d <- toGet(reconfig_fifo).get;
        let t <- toGet(timeslot_fifo).get;
        sw.start(truncate(d), t);
    endrule

    rule send_stat_request_to_sw (send_stat_request == 1);
        send_stat_request <= 0;
        for (Integer i = 0; i < valueOf(NUM_OF_SWITCH_PORTS); i = i + 1)
        begin
            sw.tx_port_stats_req[i].put(1);
            sw.rx_port_stats_req[i].put(1);
`ifdef PHY_SW
            sw.latency_req[i].put(1);
`endif
        end
    endrule

    interface CircuitSwTopSimRequest request;

        method Action startSwitching(Bit#(8) reconfig_flag, Bit#(64) timeslot);
            reconfig_fifo.enq(reconfig_flag);
            timeslot_fifo.enq(timeslot);
        endmethod

        method Action printStats();
            send_stat_request <= 1;
        endmethod

    endinterface

endmodule
