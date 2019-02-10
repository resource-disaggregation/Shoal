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
import AlteraEthPhy::*;
import DE5Pins::*;

interface CircuitSwTopIndication;
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
    method Action display_latency_port_0_stats(Bit#(64) t);
    method Action display_latency_port_1_stats(Bit#(64) t);
    method Action display_latency_port_2_stats(Bit#(64) t);
    method Action display_latency_port_3_stats(Bit#(64) t);
endinterface

interface CircuitSwTopRequest;
    method Action startSwitching(Bit#(8) reconfig_flag, Bit#(64) timeslot);
	method Action printStats();
endinterface

interface CircuitSwTop;
    interface CircuitSwTopRequest request;
    interface `PinType pins;
endinterface

module mkCircuitSwTop#(CircuitSwTopIndication indication)(CircuitSwTop);
    //Clocks
    Clock defaultClock <- exposeCurrentClock();
    Reset defaultReset <- exposeCurrentReset();

    De5Clocks clocks <- mkDe5Clocks;

    Clock txClock = clocks.clock_156_25;
    Clock phyClock = clocks.clock_644_53;
    Clock mgmtClock = clocks.clock_50;
    Reset txReset <- mkAsyncReset(2, defaultReset, txClock);
    Reset phyReset <- mkAsyncReset(2, defaultReset, phyClock);
    Reset mgmtReset <- mkAsyncReset(2, defaultReset, mgmtClock);

    //DE5 Pins
    De5Leds leds <- mkDe5Leds(defaultClock, txClock, mgmtClock, phyClock);
    De5SfpCtrl#(4) sfpctrl <- mkDe5SfpCtrl();
    De5Buttons#(4) buttons <- mkDe5Buttons(clocked_by mgmtClock, reset_by mgmtReset);

    //Phy
    EthPhyIfc phys <- mkAlteraEthPhy(mgmtClock, phyClock, txClock, defaultReset,
                            clocked_by mgmtClock, reset_by mgmtReset);

    Clock rxClock = phys.rx_clkout;
    Reset rxReset <- mkAsyncReset(2, defaultReset, rxClock);

/*-------------------------------------------------------------------------------*/

    /* Reset signals and module initialization */

    MakeResetIfc tx_reset_ifc <- mkResetSync(0, False, defaultClock);
    Reset tx_rst_sig <- mkAsyncReset(0, tx_reset_ifc.new_rst, txClock);
    Reset tx_rst <- mkResetEither(txReset, tx_rst_sig, clocked_by txClock);

    MakeResetIfc rx_reset_ifc <- mkResetSync(0, False, defaultClock);
    Reset rx_rst_sig <- mkAsyncReset(0, rx_reset_ifc.new_rst, rxClock);
    Reset rx_rst <- mkResetEither(rxReset, rx_rst_sig, clocked_by rxClock);

`ifdef PHY_SW
    PhySwitch sw <- mkPhySwitch(phys, txClock, txReset, tx_rst,
        rxClock, rxReset, rx_rst);
`endif

`ifdef MAC_SW
    MacSwitch sw <- mkMacSwitch(txClock, txReset, tx_rst, rxClock, rxReset, rx_rst);
`endif

/*------------------------------------------------------------------------------*/
`ifdef MAC_SW
    /* PHY port to MAC port mapping for Altera PHY */

    for (Integer i = 0; i < valueof(NUM_OF_SWITCH_PORTS); i = i + 1)
    begin
        rule mac_phy_tx;
            phys.tx[i].put(sw.tx(i));
        endrule

        rule mac_phy_rx;
            let v <- phys.rx[i].get;
            sw.rx(i, v);
        endrule
    end
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

/* ------------------------------------------------------------------------------
*                               INTERFACE METHODS
* ------------------------------------------------------------------------------*/
	Reg#(Bit#(1)) fire_reset_state <- mkReg(0);
	Reg#(Bit#(64)) reset_len_count <- mkReg(0);

    Reg#(Bit#(1)) send_stat_request <- mkReg(0);
    SyncFIFOIfc#(Bit#(8)) reconfig_fifo
        <- mkSyncFIFO(1, defaultClock, defaultReset, rxClock);
    SyncFIFOIfc#(Bit#(64)) timeslot_fifo
        <- mkSyncFIFO(1, defaultClock, defaultReset, rxClock);

    Reg#(Bit#(1)) start_switching_flag <- mkReg(0);
    Reg#(Bit#(8)) reconfig_flag_val <- mkReg(0);
    Reg#(Bit#(64)) timeslot_val <- mkReg(0);

	rule reset_state (fire_reset_state == 1);
		tx_reset_ifc.assertReset;
        rx_reset_ifc.assertReset;
		reset_len_count <= reset_len_count + 1;
		if (reset_len_count == 1000)
		begin
			fire_reset_state <= 0;
			start_switching_flag <= 1;
		end
	endrule

    rule send_start_switching_req (start_switching_flag == 1);
        start_switching_flag <= 0;
        reconfig_fifo.enq(reconfig_flag_val);
        timeslot_fifo.enq(timeslot_val);
    endrule

    rule start_sw;
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
            sw.latency_req[i].put(1);
        end
    endrule

    interface CircuitSwTopRequest request;

        method Action startSwitching(Bit#(8) reconfig_flag, Bit#(64) timeslot);
			fire_reset_state <= 1;
            reset_len_count <= 0;
            reconfig_flag_val <= reconfig_flag;
            timeslot_val <= timeslot;
        endmethod

        method Action printStats();
            send_stat_request <= 1;
        endmethod

    endinterface

    interface pins = mkDE5Pins(defaultClock, defaultReset, clocks, phys,
                            leds, sfpctrl, buttons);
endmodule
