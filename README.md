# OV7670 Camera to VGA Display System for Basys 3 FPGA

## Project Overview

This project implements a real-time video capture and processing pipeline on the Basys 3 FPGA board using the OV7670 camera module. The system captures video at 320x240 resolution and displays it on a VGA monitor at 640x480 (with pixel doubling).

## Features

- **Camera Interface**: OV7670 camera configuration via SCCB (I2C-like) protocol
- **Real-time Capture**: Captures RGB565 pixel data and converts to RGB444
- **Frame Buffer**: 76,800 pixels stored in Block RAM (320x240 resolution)
- **VGA Output**: Standard 640x480 @ 60Hz display with pixel doubling
- **Image Filters**: 8 different filters selectable via switches:
  - No filter (original image)
  - Grayscale conversion
  - Color inversion (negative)
  - Binary threshold
  - Red channel only
  - Green channel only
  - Blue channel only
  - Brightness boost

## Hardware Requirements

- Basys 3 FPGA Board (Artix-7)
- OV7670 Camera Module
- VGA Monitor and Cable
- Jumper wires for camera connection

## File Structure

```
camera_vga_top.v        - Top-level module
ov7670_config.v         - SCCB camera configuration
ov7670_capture.v        - Camera pixel capture
vga_controller.v        - VGA timing generator
frame_buffer.v          - Dual-port BRAM wrapper
image_filter.v          - Image processing filters
basys3_camera.xdc       - Pin constraints file
```

## Vivado Setup Instructions

### Step 1: Create New Project

1. Open Vivado
2. Create New Project
3. Select Basys 3 board (xc7a35tcpg236-1)
4. Add all `.v` source files
5. Add the `.xdc` constraints file

### Step 2: Generate Clock Wizard IP

The system requires two clocks:
- 25 MHz for VGA pixel clock
- 24 MHz for camera master clock

1. Go to **IP Catalog** → **Clocking** → **Clocking Wizard**
2. Configure:
   - **Primary Input Clock**: 100 MHz (sys_clk_pin)
   - **Output Clocks**:
     - clk_out1: 25.000 MHz (for VGA)
     - clk_out2: 24.000 MHz (for camera)
   - **Enable locked output port**
3. Generate the IP and name it `clk_wiz_0`

### Step 3: Generate Block Memory (Optional for Synthesis)

For better performance, use Vivado's Block Memory Generator:

1. Go to **IP Catalog** → **Memories & Storage** → **Block Memory Generator**
2. Configure:
   - **Memory Type**: True Dual Port RAM
   - **Port A Configuration**:
     - Width: 12 bits
     - Depth: 76800
     - Enable: Always Enabled
     - Write Mode: Write First
   - **Port B Configuration**: Same as Port A
3. Generate the IP and name it `blk_mem_gen_0`
4. In `frame_buffer.v`, comment out the behavioral model and uncomment the IP instantiation

### Step 4: Synthesize and Implement

1. Run Synthesis
2. Run Implementation
3. Generate Bitstream
4. Program Device

## Pin Connections

### Camera to Basys 3

| Camera Pin | Basys 3 Pin | Signal    |
|------------|-------------|-----------|
| D0         | P17         | Data bit 0|
| D1         | N17         | Data bit 1|
| D2         | M19         | Data bit 2|
| D3         | M18         | Data bit 3|
| D4         | L17         | Data bit 4|
| D5         | K17         | Data bit 5|
| D6         | C16         | Data bit 6|
| D7         | B16         | Data bit 7|
| HREF       | A17         | Horiz Ref |
| PCLK       | A16         | Pixel Clk |
| PWDN       | R18         | Power Down|
| RESET      | P18         | Reset     |
| VSYNC      | B15         | Vert Sync |
| XCLK       | C15         | Mstr Clock|
| SCL        | A14         | SCCB Clock|
| SDA        | A15         | SCCB Data |

### Power Connections

- Camera VCC → 3.3V
- Camera GND → GND

### Controls

- **BTNC (Center Button)**: System reset
- **SW0-SW2**: Filter selection (000 to 111)
- **LD0**: Configuration done indicator
- **LD1**: VSYNC indicator
- **LD2**: HREF indicator
- **LD3**: Write enable indicator

## How It Works

### 1. Camera Configuration (ov7670_config.v)

- Sends SCCB commands to configure camera registers
- Sets QVGA (320x240) resolution
- Configures RGB444 output mode
- Takes ~1 second to complete initialization

### 2. Camera Capture (ov7670_capture.v)

- Captures pixel data synchronized to PCLK
- Reads RGB565 format (2 bytes per pixel)
- Converts to RGB444 (12 bits per pixel)
- Writes to frame buffer at camera pixel rate

### 3. Frame Buffer (frame_buffer.v)

- Dual-port Block RAM
- Port A: Write at camera pixel clock (~24 MHz)
- Port B: Read at VGA pixel clock (25 MHz)
- Stores 76,800 pixels (320x240 × 12 bits)

### 4. VGA Controller (vga_controller.v)

- Generates 640x480 @ 60Hz timing signals
- Produces HSYNC and VSYNC signals
- Provides current pixel coordinates
- Pixel doubling: each captured pixel shown as 2×2 on display

### 5. Image Filters (image_filter.v)

- Processes pixels in real-time
- Combinational logic (no latency)
- Switch between 8 different effects

## Timing Analysis

### Clock Domains

1. **System Clock**: 100 MHz (from Basys 3 oscillator)
2. **VGA Clock**: 25 MHz (for 640x480 @ 60Hz)
3. **Camera Clock**: 24 MHz (camera master clock)
4. **Camera PCLK**: ~24 MHz (pixel clock from camera)

### Cross-Domain Considerations

- Frame buffer handles clock domain crossing
- Camera writes at PCLK rate
- VGA reads at 25 MHz pixel clock
- No synchronization needed due to dual-port RAM

## Resource Utilization (Estimated)

- **Block RAM**: ~8 blocks (for frame buffer)
- **LUTs**: ~500-800
- **FFs**: ~300-500
- **DSP Blocks**: 0

## Troubleshooting

### No Image on Monitor

1. Check VGA cable connection
2. Verify monitor supports 640x480 @ 60Hz
3. Check LED0 - should be ON when config done
4. Try pressing reset button (BTNC)

### Image Quality Issues

1. Check camera focus (some OV7670 modules have adjustable lens)
2. Verify camera is properly powered (3.3V)
3. Check all data line connections
4. Ensure adequate lighting

### Configuration Issues

1. Verify SCCB pull-up on SDA line
2. Check camera power supply stability
3. Try different camera modules if available
4. Monitor LED indicators during boot

## Testing Procedure

1. Program the FPGA with generated bitstream
2. Connect VGA cable to monitor
3. Press reset button (BTNC)
4. Wait ~1 second for camera configuration (LED0 lights up)
5. Image should appear on monitor
6. Toggle SW0-SW2 to test different filters

## Filter Selection

| SW2 | SW1 | SW0 | Filter             |
|-----|-----|-----|--------------------|
| 0   | 0   | 0   | Original (no filter)|
| 0   | 0   | 1   | Grayscale          |
| 0   | 1   | 0   | Negative           |
| 0   | 1   | 1   | Binary threshold   |
| 1   | 0   | 0   | Red channel only   |
| 1   | 0   | 1   | Green channel only |
| 1   | 1   | 0   | Blue channel only  |
| 1   | 1   | 1   | Brightness boost   |

## Expanding the Project

### Adding More Filters

Edit `image_filter.v` to add custom processing:
- Edge detection (Sobel, Prewitt)
- Blur/Sharpen
- Color space transformations
- Histogram equalization

### Increasing Resolution (Extra Credit)

To achieve 640×480 full resolution:
1. Modify camera configuration for VGA mode
2. Reduce color depth (e.g., 8-bit or 6-bit color)
3. Use line buffer instead of full frame buffer
4. Implement real-time processing without storage

### Adding More Controls

- Use additional switches for brightness/contrast
- Add buttons for freeze frame
- Implement histogram display on LEDs

## References

- [OV7670 Datasheet](http://web.mit.edu/6.111/www/f2016/tools/OV7670_2006.pdf)
- [OV7670 Implementation Guide](http://web.mit.edu/6.111/www/f2016/tools/OV7670_Implementation_Guide.pdf)
- [VGA Timing Specifications](http://tinyvga.com/vga-timing)
- [Basys 3 Reference Manual](https://reference.digilentinc.com/basys3/refmanual)

## License

This project is for educational purposes. Feel free to modify and extend it for your learning.

## Credits

Developed for Digital Logic / Embedded Systems Final Project
