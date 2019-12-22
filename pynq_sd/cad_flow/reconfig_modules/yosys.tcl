#yosys -import
#######Yosys#############

proc map_luts {} {
    #yosys abc -luts 2:2,3,6:5,10,20 \[-dff\]
    yosys abc -luts 2:2,3,6:5,10,20
    yosys clean
    yosys techmap -map +/xilinx/lut_map.v
}

proc map_cells {} {
    yosys techmap -map +/xilinx/cells_map.v
    #yosys dffinit -ff FDRE Q INIT -ff FDCE Q INIT -ff FDPE Q INIT
    yosys dffinit -ff FDRE Q INIT -ff FDCE Q INIT -ff FDPE Q INIT -ff FDSE Q INIT -ff FDRE_1 Q INIT -ff FDCE_1 Q INIT -ff FDPE_1 Q INIT -ff FDSE_1 Q INIT
    yosys clean
}

proc check {} {
    yosys hierarchy -check
    yosys stat
    yosys check -noinit
}


proc fine_synth {} {
    yosys opt -fast -full
    yosys memory_map
    yosys dffsr2dff
    yosys dff2dffe
    yosys opt -full
    
    #yosys techmap -map +/techmap.v -map +/xilinx/arith_map.v
    #yosys opt -fast
    
    yosys techmap -map +/techmap.v -map +/xilinx/arith_map.v -map +/xilinx/ff_map.v
    yosys hierarchy -check
    yosys opt -fast
}

proc verilog_frontend {} {
    # Read the supported primitives using the Verilog frontend:
	yosys read_verilog -lib +/xilinx/cells_sim.v
	yosys read_verilog -lib +/xilinx/cells_xtra.v
    
    # Don't do BRAMs as X-Ray can't handle them.
	#yosys read_verilog -lib +/xilinx/brams_bb.v
    
    # drams_bb.v contents are now in cells_sim.v
	#yosys read_verilog -lib +/xilinx/drams_bb.v
    
    # Read the HDL:
    #foreach file $verilog_files {
    #    yosys read_verilog $sv_flag $file
    #}
    
# Read the design using the Verilog frontend:
    if {$::env(SV) == 1 } {
        yosys read_verilog -sv $::env(YOSYS_SOURCE_PATH)/*.sv
    } else {
        yosys read_verilog $::env(YOSYS_SOURCE_PATH)/*.v
    }

    # Elaborate the design hierarchy.
    # Mark top module
	yosys hierarchy -check -top $::env(TOP)
    
}


## Writes an RM RSCP. 
# Assuming Yosys for now. Later add options to synth with yosys or vivado.
proc write_rm_rscp {top rm_dir static_resources} {
    set verilog_files [list]
    set sv_flag ""
    if {$rm_dir == ""} {
        set rm_dir [pwd]
    }
    
    #TODO: Error if no static_resources file specified, etc.
    
    if {[glob -nocomplain $rm_dir/*.sv] != ""} {
	    puts "Reading SV files..."
	    set verilog_files [glob $rm_dir/*.sv]
        set sv_flag "-sv"
    }
    if {[glob -nocomplain $rm_dir/*.v] != ""} {
	    puts "Reading Verilog files..."
	    set verilog_files [glob $rm_dir/*.v]
    }
    
    yosys_verilog_frontend $verilog_files $sv_flag
    
}

# Verilog Frontend
verilog_frontend

# Convert processes (always blocks) to netlist elements (d-type flip flops and muxes)
yosys proc

# Flatten the design
yosys flatten

# Coarse synthesis
yosys synth -run coarse

# Replace undefined (x) constants and undriven nets with defined 0 constants.
# This will prevent Yosys creating more than one GND net. 
# (although maybe it needs to have a pass that merges GND nets)
# If this isn't done, setting only some outputs to 0 and not others will result in two nets by the name of "GND_NET"
yosys setundef -zero -undriven

#BRAM Mapping
#yosys memory_bram -rules +/xilinx/brams.txt
#yosys techmap -map +/xilinx/brams_map.v

#DRAM Mapping
yosys memory_bram -rules +/xilinx/drams.txt
yosys techmap -map +/xilinx/drams_map.v

fine_synth
map_luts
map_cells
check

yosys write_edif -pvector bra $::env(NAME).rscp/netlist.edf
