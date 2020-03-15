# Maverick
Maverick is an open-source computer-aided design (CAD) flow for generating reconfigurable modules (RMs) which target PR regions in FPGA designs. Maverick builds upon existing open source tools (Yosys, RapidSmith2, and Project X-Ray) to form an end-to-end compilation flow. After an initial static design and PR region are
created with Xilinx’s Vivado PR flow, Maverick can then compile and configure RMs onto that PR region—without the use of vendor tools. Maverick currently supports Xilinx 7-Series devices and has specifically been tested on the ZYNQ XC7Z020-1CLG400C SoC.

A more detailed description of Maverick, ["Maverick: A Stand-Alone CAD Flow for Partially Reconfigurable FPGA Modules"](https://ieeexplore.ieee.org/document/8735509), was published at FCCM 2019. Even more information on Maverick can be found in [Dallon Glick's master's thesis on Maverick](https://scholarsarchive.byu.edu/etd/7746/).

# How To Use Maverick
Maverick consists of a "Static Design Phase" and a "Reconfigurable Module (RM) Phase".

## Static Design Phase

### Vivado
1. Use Vivado's PR flow to create an initial static design, containing a single PR region. Generate an initial full and partial bitstream.
2. Execute Tincr's "write_rm_rscp" command to generate static data files that describe the static design. 

### RapidSmith2
1. Use RapidSmith2's Partial Device Generator to create a partial device file for the PR region previously chosen.

### Project X-Ray
1. Generate a bitstream database that at least documents the targeted PR region.

## Reconfigurable Module (RM) Phase

### Yosys
1. Synthesize and tech-map the design.

### RapidSmith2 (with RS-CAD)
1. Import the tech-mapped design.
2. Pack, place, and route the design.
3. Export an FPGA Assembly (FASM) file.

### Project X-Ray
1. Convert the FASM file to a FRM file with FASM2FRAME.
2. Generate a new partial bistream with xc7PartialPatch.
