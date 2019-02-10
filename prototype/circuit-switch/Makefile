DEV_ROOT ?= $(HOME)
CONNECTALDIR ?= $(DEV_ROOT)/connectal
PROJECT_DIR ?= $(DEV_ROOT)/shoal-prototype/circuit-switch
S2H_INTERFACES = CircuitSwTopRequest:CircuitSwTop.request
H2S_INTERFACES = CircuitSwTop:CircuitSwTopIndication
BSVFILES = $(PROJECT_DIR)/bsv/CircuitSwTop.bsv
CPPFILES = $(PROJECT_DIR)/cpp/test_hw.cpp

CONNECTALFLAGS += -D DataBusWidth=128
#CONNECTALFLAGS += -D NUMBER_OF_ALTERA_PORTS=3
CONNECTALFLAGS += --bsvpath=$(CONNECTALDIR)/bsv
CONNECTALFLAGS += --bsvpath=$(PROJECT_DIR)/../lib/bsv/
CONNECTALFLAGS += --bsvpath=$(PROJECT_DIR)/../lib/generated/
CONNECTALFLAGS += -D NicVersion=$(shell printf "%d" 0x`git rev-parse --short=8 HEAD`)
CONNECTALFLAGS += -D PcieHostIF
CONNECTALFLAGS += -D BYTE_ENABLES
FPGAMAKE_CONNECTALFLAGS += -P mkPcieHostTop

#######################################################
# DE5 Specific Settings
# #######################################################
AUTOTOP = --interface pins:CircuitSwTop.pins
PIN_TYPE = DE5Pins
PIN_TYPE_INCLUDE = DE5Pins
PIN_BINDINGS ?= PCIE:PCIE OSC:OSC SFPA:SFPA SFPB:SFPB SFPC:SFPC SFPD:SFPD SFP:SFP LED:LED I2C:I2C
PINOUT_FILE = $(PROJECT_DIR)/boards/de5.json

CONNECTALFLAGS += --nocache
CONNECTALFLAGS += --verilog=$(PROJECT_DIR)/../lib/verilog/si570/
CONNECTALFLAGS += --xci=$(IPDIR)/$(BOARD)/synthesis/mac_10gbe.qip
CONNECTALFLAGS += --xci=$(IPDIR)/$(BOARD)/synthesis/altera_xcvr_10gbaser_wrapper.qip
CONNECTALFLAGS += --xci=$(IPDIR)/$(BOARD)/synthesis/pll_156/altera_pll_156.qip

CONNECTALFLAGS += --tcl=constraint.sdc
CONNECTALFLAGS += --constraint=constraint.sdc
CONNECTALFLAGS += --implconstraint=constraint.sdc
CONNECTALFLAGS += --xci=$(IPDIR)/$(BOARD)/synthesis/sv_10g_pma/sv_10g_pma.qip
CONNECTALFLAGS += --xci=$(IPDIR)/$(BOARD)/synthesis/altera_clkctrl/altera_clkctrl.qip

#CONNECTALFLAGS += -D MAC_SW
CONNECTALFLAGS += -D PHY_SW
CONNECTALFLAGS += -D BOARD_de5

CONNECTALFLAGS += --bscflags="-show-range-conflict +RTS -K46777216 -RTS -demote-errors G0066:G0045 -suppress-warnings G0046:G0020:S0015:S0080:S0039 -steps-max-intervals 20"

prebuild::
	(cd $(BOARD); BUILDCACHE_CACHEDIR=$(BUILDCACHE_CACHEDIR) $(BUILDCACHE) quartus_sh -t $(PROJECT_DIR)/../lib/scripts/generate-mac.tcl)
	(cd $(BOARD); BUILDCACHE_CACHEDIR=$(BUILDCACHE_CACHEDIR) $(BUILDCACHE) quartus_sh -t $(PROJECT_DIR)/../lib/scripts/connectal-synth-phy.tcl)
	(cd $(BOARD); BUILDCACHE_CACHEDIR=$(BUILDCACHE_CACHEDIR) $(BUILDCACHE) quartus_sh -t $(PROJECT_DIR)/../lib/scripts/connectal-synth-pll.tcl)
	(cd $(BOARD); BUILDCACHE_CACHEDIR=$(BUILDCACHE_CACHEDIR) $(BUILDCACHE) $(QUARTUS_SH) -t $(PROJECT_DIR)/../lib/scripts/connectal-synth-pma.tcl)
	(cd $(BOARD); BUILDCACHE_CACHEDIR=$(BUILDCACHE_CACHEDIR) $(BUILDCACHE) $(QUARTUS_SH) -t $(PROJECT_DIR)/../lib/scripts/connectal-synth-misc.tcl)

include $(CONNECTALDIR)/Makefile.connectal
