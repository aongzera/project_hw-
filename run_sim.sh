#!/bin/bash
################################################################################
# Simulation Script for OV7670 Camera Project
# 
# This script runs the testbenches using Icarus Verilog (iverilog)
# Install iverilog: sudo apt-get install iverilog gtkwave
# 
# Usage:
#   ./run_sim.sh vga      - Run VGA controller testbench
#   ./run_sim.sh filter   - Run image filter testbench
#   ./run_sim.sh all      - Run all testbenches
################################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "OV7670 Camera Project - Simulation Runner"
echo "=========================================="

# Check if iverilog is installed
if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}Error: iverilog not found!${NC}"
    echo "Install with: sudo apt-get install iverilog"
    exit 1
fi

# Function to run VGA testbench
run_vga_sim() {
    echo -e "\n${YELLOW}Running VGA Controller Testbench...${NC}"
    
    # Compile
    iverilog -o vga_sim.vvp \
        vga_controller.v \
        tb_vga_controller.v
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Compilation successful${NC}"
        
        # Run simulation
        vvp vga_sim.vvp
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Simulation completed${NC}"
            echo "  Waveform saved to: vga_controller.vcd"
            echo "  View with: gtkwave vga_controller.vcd"
        else
            echo -e "${RED}✗ Simulation failed${NC}"
        fi
    else
        echo -e "${RED}✗ Compilation failed${NC}"
    fi
}

# Function to run filter testbench
run_filter_sim() {
    echo -e "\n${YELLOW}Running Image Filter Testbench...${NC}"
    
    # Compile
    iverilog -o filter_sim.vvp \
        image_filter.v \
        tb_image_filter.v
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Compilation successful${NC}"
        
        # Run simulation
        vvp filter_sim.vvp
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Simulation completed${NC}"
            echo "  Waveform saved to: image_filter.vcd"
            echo "  View with: gtkwave image_filter.vcd"
        else
            echo -e "${RED}✗ Simulation failed${NC}"
        fi
    else
        echo -e "${RED}✗ Compilation failed${NC}"
    fi
}

# Parse command line argument
case "$1" in
    vga)
        run_vga_sim
        ;;
    filter)
        run_filter_sim
        ;;
    all)
        run_vga_sim
        run_filter_sim
        ;;
    *)
        echo "Usage: $0 {vga|filter|all}"
        echo ""
        echo "Examples:"
        echo "  $0 vga      - Run VGA controller testbench"
        echo "  $0 filter   - Run image filter testbench"
        echo "  $0 all      - Run all testbenches"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "Simulation Complete!"
echo "=========================================="
