package require tincr

proc max_property {list property} {
    set max -1
    foreach i $list {
        set curr_prop [get_property $property $i]
        if {($max == -1) || ($curr_prop > $max)} {
            set max $curr_prop
        }
    }
    return $max
}
proc min_property {list property} {
    set min -1
    foreach i $list {
        set curr_prop [get_property $property $i]
        if {($min == -1) || ($curr_prop < $min)} {
            set min $curr_prop
        }
    }
    return $min
}

#TODO: Work with top_left + bott_right and bott_left + top_right
#TODO: Optimize
#TODO: Support RAMB18, DSP48, RAMB36 (RAMB18 is different from RAMB18E1 for ex)
proc create_pblock_ranges {bott_left_tile top_right_tile} {

    set bott_left_row [get_property ROW $bott_left_tile]
    set bott_left_col [get_property COLUMN $bott_left_tile]
    set top_right_row [get_property ROW $top_right_tile]
    set top_right_col [get_property COLUMN $top_right_tile]
    
    puts "$bott_left_row $bott_left_col $top_right_row $top_right_col"
    # 103 70 53 81

    # smallest row val is with top right
    # biggest col is with top right
    
    #set sites [get_sites -of_objects [get_tiles -filter { ROW <= $top_right_row && ROW >= $bott_left_row && COLUMN >= $bott_left_col && COLUMN <= $top_right_col} ]]
    set tiles [get_tiles -filter "ROW >= $top_right_row && ROW <= $bott_left_row && COLUMN >= $bott_left_col && COLUMN <= $top_right_col" ]
    
    set slice_range ""
    set ramb18_range ""
    set ramb36_range ""
    
    # Find the bottom-left and top-right slices
    set slices [get_sites -of_objects $tiles -filter {SITE_TYPE == "SLICEL" || SITE_TYPE == "SLICEM"}]
    if {[llength $slices] != 0} {
        set min_rpm_x [min_property $slices "RPM_X"]
        set min_rpm_y [min_property $slices "RPM_Y"]
        set max_rpm_x [max_property $slices "RPM_X"]
        set max_rpm_y [max_property $slices "RPM_Y"]
        set bott_left_slice [get_sites -filter "RPM_X == $min_rpm_x && RPM_Y == $min_rpm_y"]
        set top_right_slice [get_sites -filter "RPM_X == $max_rpm_x && RPM_Y == $max_rpm_y"]
        set slice_range "${bott_left_slice}:${top_right_slice}"
    }


    # Find the bottom-left and top-right RAMB18E1/FIFO18E1 sites
    set ramb18_sites [get_sites -of_objects $tiles -filter {SITE_TYPE == "RAMB18E1" || SITE_TYPE == "FIFO18E1"}]    
    if {[llength $ramb18_sites] != 0} {
        set min_rpm_x [min_property $ramb18_sites "RPM_X"]
        set min_rpm_y [min_property $ramb18_sites "RPM_Y"]
        set max_rpm_x [max_property $ramb18_sites "RPM_X"]
        set max_rpm_y [max_property $ramb18_sites "RPM_Y"]
        set bott_left_ramb18 [get_sites -filter "RPM_X == $min_rpm_x && RPM_Y == $min_rpm_y"]
        set top_right_ramb18 [get_sites -filter "RPM_X == $max_rpm_x && RPM_Y == $max_rpm_y"]
        set ramb18_range "${bott_left_ramb18}:${top_right_ramb18}"
    }    
    
    # Find the bottom-left and top-right RAMB36E1/FIFO36E1/RAMBFIFO36E1 sites
    set ramb36_sites [get_sites -of_objects $tiles -filter {SITE_TYPE == "RAMB36E1" || SITE_TYPE == "FIFO36E1" || SITE_TYPE == "RAMBFIFO36E1"}]    
    if {[llength $ramb36_sites] != 0} {
        set min_rpm_x [min_property $ramb36_sites "RPM_X"]
        set min_rpm_y [min_property $ramb36_sites "RPM_Y"]
        set max_rpm_x [max_property $ramb36_sites "RPM_X"]
        set max_rpm_y [max_property $ramb36_sites "RPM_Y"]
        set bott_left_ramb36 [get_sites -filter "RPM_X == $min_rpm_x && RPM_Y == $min_rpm_y"]
        set top_right_ramb36 [get_sites -filter "RPM_X == $max_rpm_x && RPM_Y == $max_rpm_y"] 
        set ramb36_range "${bott_left_ramb36}:${top_right_ramb36}"
    }
    
    return "${slice_range}${ramb18_range}${ramb36_range}"
}

proc synth_static {device design} {
	puts "Linking $device ..."
    link_design -part $device

	if {[glob -nocomplain $design/src/static/*.sv] != ""} {
	    puts "Reading SV files..."
	    read_verilog -sv [glob $design/src/static/*.sv]
    }
    if {[glob -nocomplain $design/src/static/*.v] != ""} {
	    puts "Reading Verilog files..."
	    read_verilog [glob $design/src/static/*.v]
    }
    if {[glob -nocomplain $design/src/static/*.vhd] != ""} {
	    puts "Reading VHDL files..."
	    read_vhdl [glob $design/src/static/*.vhd]
    }
    
    #puts "Reading IP..."
    #include_ips $design

    puts "Synthesizing static design..."
    synth_design -top top -flatten_hierarchy full 
	
	puts "Writing static checkpoint"
	write_checkpoint -force $design/DCP/synthesized/static.dcp
	
	close_project
}

##
# Create the initial configuration in order to created the routed static checkpoint
proc create_routed_static {design rp_name bott_left_tile_name top_right_tile_name initial_rm} {
	# Load synthesized static design
	open_checkpoint $design/DCP/synthesized/static.dcp

	# Assign blackbox RM to the RP
    # Read the EDIF instead of the checkpoint. Vivado is inconsistent with the way it renames bus-ports in ooc vs. in-context
    # Read the EDIF so the bus ports will match in both sides (static and RM). Otherwise, one side's names will be reversed, which is confusing
    update_design -cells ${rp_name} -from_file $design/DCP/synthesized/${initial_rm}.edf
	
	# Configure cell instance as reconfigurable
	set_property HD.RECONFIGURABLE 1 [get_cells ${rp_name}]

    # Set up the PBlock for the reconfigurable partition
	create_pblock rp_0
	add_cells_to_pblock [get_pblocks rp_0] [get_cells -quiet [list get_cells ${rp_name}]]
	
    set bott_left_tile [get_tiles $bott_left_tile_name]
    set top_right_tile [get_tiles $top_right_tile_name]
    set pblock_ranges [create_pblock_ranges $bott_left_tile $top_right_tile]
    resize_pblock rp_0 -add $pblock_ranges
    #resize_pblock rp_0 -add SLICE_X36Y50:SLICE_X39Y99
	set_property RESET_AFTER_RECONFIG true [get_pblocks rp_0]
	set_property SNAPPING_MODE ON [get_pblocks rp_0]

	# Add constraints
    puts "Read static constraints"
	read_xdc $design/constraints.xdc

	# Place & route
	puts "Place and route initial configuration"
	place_design
	route_design

	# Save implemented design
	write_checkpoint -force $design/DCP/routed/full_${initial_rm}.dcp
    
    #write_bitstream -force -file $design/DCP/routed/full_${initial_rm}.bit
	
    # Isolate the static design
	# Set cell instance to be a black block
	update_design -cells ${rp_name} -black_box 
    
	write_checkpoint -force $design/DCP/routed/static.dcp
    
    # Save a base bitstream. This is helpful if you want to patch bitstreams later
   #write_bitstream -force -file $design/bitstreams/base.bit
	close_project
}

proc synth_initial_rm {device design rm_name partial_device} {
    puts "synth initial rm $rm_name"
	
	if {[glob -nocomplain ${design}/src/reconfig/${rm_name}/*.sv] != ""} {
	    puts "Reading SV files..."
        read_verilog -sv [glob ${design}/src/reconfig/${rm_name}/*.sv]
    }
	
    if {[glob -nocomplain ${design}/src/reconfig/${rm_name}/*.v] != ""} {
	    puts "Reading Verilog files..."
        puts "location : ${design}/src/reconfig/${rm_name}"
        read_verilog [glob ${design}/src/reconfig/${rm_name}/*.v]
    }
	
    if {[glob -nocomplain ${design}/src/reconfig/${rm_name}/*.vhd] != ""} {
	    puts "Reading VHDL files..."
		read_vhdl [glob ${design}/src/reconfig/${rm_name}/*.vhd]	
    }    
    #TODO: Error if no files are read.
    
	synth_design -mode out_of_context -flatten_hierarchy full -top $design -part $device
	write_checkpoint -force $design/DCP/synthesized/${rm_name}.dcp
    write_edif -force $design/DCP/synthesized/${rm_name}.edf
    close_project
}

proc synth_rm {design rp_name rm_name device partial_device cad_step} {
    # Must already know the pblock the RM will be contained in.
    set static_design "checkpoint_static"
    
    if {$cad_step != ""} {
        open_checkpoint $design/DCP/routed/static.dcp
        set static_design [get_designs]
        puts "static_design = $static_design"
    }
    
	if {[glob -nocomplain ${design}/src/reconfig/${rm_name}/*.sv] != ""} {
	    puts "Reading SV files..."
		set rm_list [glob ${design}/src/reconfig/${rm_name}/*.sv]
		foreach rm $rm_list {
            if {$cad_step == ""} {
                link_design -part $device
            }
		    read_verilog -sv $rm
		}
    }
	
    if {[glob -nocomplain ${design}/src/reconfig/${rm_name}/*.v] != ""} {
	    puts "Reading Verilog files..."
		set rm_list [glob ${design}/src/reconfig/${rm_name}/*.v]
		foreach rm $rm_list {
            if {$cad_step == ""} {
                link_design -part $device
            }
		    read_verilog $rm
		}
    }
	
    if {[glob -nocomplain ${design}/src/reconfig/${rm_name}/*.vhd] != ""} {
	    puts "Reading VHDL files..."
	    set rm_list [glob ${design}/src/reconfig/${rm_name}/*.vhd]
		foreach rm $rm_list {
            if {$cad_step == ""} {
                link_design -part $device
            }
			read_vhdl $rm
		}		
    }

    #TODO: Error if no files read
    
	synth_design -mode out_of_context -flatten_hierarchy full -top $design -part $device
    
    if {$cad_step == "placement"} {
        set partial_design [get_designs -regexp ^(?!$static_design).*$]
        set all_designs [get_designs]
        puts "all designs $all_designs"
        puts "partial_design = $partial_design"

        current_design $static_design

        # Assign RM blocks to RPs
        update_design -cell $rp_name -from_design $partial_design
		place_design
        
        #TODO: Rework procedures so writing and opening this checkpoint can be skipped.
        write_checkpoint -cell $rp_name -force $design/DCP/synthesized/temp_${rm_name}.dcp
        close_project
        open_checkpoint $design/DCP/synthesized/temp_${rm_name}.dcp
        
    } elseif {$cad_step == "routing"} {
        set partial_design [get_designs -regexp ^(?!$static_design).*$]
        current_design $static_design

        # Assign RM blocks to RPs
        update_design -cell $rp_name -from_design $partial_design
        place_design
        route_design
    }
    
	write_checkpoint -force $design/DCP/synthesized/${rm_name}.dcp
	tincr::write_rm_rscp $partial_device $design/DCP/routed/static.dcp $rp_name $design/RSCP/${rm_name} 
	close_project    
}

## Synthesizes all RMs that have a sub-directory within $design/src/reconfig.
# 
# @param design name of the entire design
# @param partial_device name of the partial device 
#
proc synth_rms {design rp_name device partial_device cad_step} {
    # The source for each RM is assumed to be in its own sub-directory.
    # TODO: Error if no sub-directories?
    
    cd $design/src/reconfig
    set rm_dirs [glob -type d *]
    cd ../../..
    
    foreach rm_dir $rm_dirs {
        synth_rm $design $rp_name $rm_dir $device $partial_device $cad_step
    }
}

## Compiles a static design and saves an RSCP.
#   USAGE: synth [-quiet] design rp_name partial_device
#
# @param design the name of the design (alu, etc.)
# @param partial_device the name of the partial device (the file you will be using in RS2)
# @param rp_name the name of the reconfigurable partition to create RM tcp's for.
# @param init_rm the name of the reconfigurable module to use in the initial configuration
# @param cad_step Which cad step to have Vivado impelement up to (synthesis, placement, or routing)
# compile rp_top xc7z020clg400-1 pynq_xray rp_top CLBLL_L_X40Y0 CLBLM_R_X43Y49 timer_game synthesis
proc compile {design device partial_device rp_name bott_left_tile top_right_tile init_rm cad_step} {
    # TODO: If cad_step != synthesis, placement, or routing, display a warning and default to synthesis.

    puts "Closing any designs that are currently open..."
    puts ""
    close_project -quiet
	
	puts "Synthesizing static design..."
	synth_static $device $design
	puts ""
	
	puts "Creating routed static design..."
	synth_initial_rm $device $design $init_rm $partial_device
	create_routed_static $design $rp_name $bott_left_tile $top_right_tile $init_rm
	puts ""
	
	puts "Synthesizing and saving RM RSCPs..."
    # TODO: Don't synthesize the initial RM again.
	synth_rms $design $rp_name $device $partial_device $cad_step
}