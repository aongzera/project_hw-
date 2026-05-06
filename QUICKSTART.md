# Quick Start Guide - OV7670 Camera to VGA

## 🚀 Getting Started in 5 Steps

### Step 1: Hardware Setup (5 minutes)

**Connect Camera to Basys 3:**

Essential connections (refer to pin table in README.md):
- Data lines: D0-D7 → Camera data pins
- Control: HREF, PCLK, VSYNC, XCLK
- SCCB: SCL, SDA (note: SDA needs pull-up resistor if not on module)
- Power: 3.3V and GND
- RESET and PWDN pins

**Connect VGA Monitor:**
- Use VGA cable from Basys 3 VGA port to monitor

### Step 2: Create Vivado Project (10 minutes)

```bash
1. Open Vivado 2023.x or newer
2. Create New Project → RTL Project
3. Add all .v files as design sources
4. Add basys3_camera.xdc as constraints
5. Select Basys 3 board (xc7a35tcpg236-1)
```

### Step 3: Generate Required IP Cores (5 minutes)

**Clock Wizard:**
```
IP Catalog → Clocking → Clocking Wizard
- Name: clk_wiz_0
- Input: 100 MHz
- Output 1: 25.000 MHz (VGA)
- Output 2: 24.000 MHz (Camera)
- Enable locked port: ✓
Generate → OK
```

**Block Memory (Optional - for better performance):**
```
IP Catalog → Memories → Block Memory Generator
- Name: blk_mem_gen_0
- Memory Type: True Dual Port RAM
- Port A & B: Width=12, Depth=76800
Generate → OK

Then in frame_buffer.v:
- Comment out behavioral model (lines 30-50)
- Uncomment IP instantiation (lines 60-75)
```

### Step 4: Build and Program (10 minutes)

```bash
1. Run Synthesis (wait ~2 minutes)
2. Run Implementation (wait ~3 minutes)
3. Generate Bitstream (wait ~2 minutes)
4. Program Device:
   - Connect Basys 3 via USB
   - Open Hardware Manager
   - Auto Connect
   - Program Device → Select .bit file
```

### Step 5: Test! (2 minutes)

```
1. Press BTNC (center button) to reset
2. Wait ~1 second for camera config (LED0 turns ON)
3. Image appears on monitor!
4. Toggle SW0-SW2 to change filters
```

---

## 🔍 Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| No image | Check LED0 (config done). If OFF, check camera power/connections |
| Black screen | Verify VGA cable, try pressing BTNC reset |
| Wavy/unstable | Camera PCLK may be noisy - check connections |
| Wrong colors | Verify all D0-D7 data lines are connected correctly |

---

## 📊 Expected Resource Usage

After synthesis, you should see approximately:
- **LUTs**: 600-900 (out of 20,800)
- **FFs**: 400-600 (out of 41,600)
- **BRAM**: 7-9 blocks (out of 50)
- **Max Frequency**: Should easily meet 100 MHz

If you see **timing violations**:
1. Check clock constraints in .xdc
2. Ensure false_path is set for clock domain crossings
3. Reduce clock frequencies if needed

---

## 🎯 Testing Each Component Individually

### Test VGA Controller Only
```verilog
// In camera_vga_top.v, temporarily replace camera with test pattern:
assign write_data = {x_pos[3:0], y_pos[3:0], 4'hF};  // Color gradient
assign write_addr = (y_pos * 320) + x_pos;
assign write_enable = 1;
```

### Test Camera Capture Only
```verilog
// Monitor LEDs:
// LED0: Config done
// LED1: VSYNC activity
// LED2: HREF activity  
// LED3: Write enable (should blink rapidly when capturing)
```

---

## 🎨 Filter Selection Reference

| SW2 | SW1 | SW0 | Effect |
|:---:|:---:|:---:|--------|
| 0 | 0 | 0 | Original |
| 0 | 0 | 1 | **Grayscale** ← Try this first! |
| 0 | 1 | 0 | Negative |
| 0 | 1 | 1 | B&W Threshold |
| 1 | 0 | 0 | Red only |
| 1 | 0 | 1 | Green only |
| 1 | 1 | 0 | Blue only |
| 1 | 1 | 1 | Brighter |

---

## 🏆 Tips for Demo Day

1. **Bring backup hardware**: Extra camera module, VGA cable
2. **Pre-program FPGA**: Have working .bit file ready
3. **Test all filters**: Show at least 3 different filters working
4. **Explain block diagram**: Be ready to draw/show data flow
5. **Know your timing**: Be able to explain clock domains

---

## 📈 For Extra Credit: 640x480 Resolution

To upgrade to full VGA resolution:

1. **Reduce color depth**: Change to 6-bit color (2 bits per channel)
   - Modify frame_buffer to 6 bits wide
   - Adjust RGB conversion in ov7670_capture.v

2. **Line buffer approach** (recommended):
   - Store only 2-3 lines instead of full frame
   - Process and display in real-time
   - Reduces BRAM usage significantly

3. **Camera reconfiguration**:
   - Change OV7670 to VGA mode (640x480)
   - Update register values in ov7670_config.v

---

## 🐛 Common Beginner Mistakes

❌ **Don't**: Connect camera to 5V (it's 3.3V only!)  
❌ **Don't**: Forget to enable clock wizard locked signal  
❌ **Don't**: Use single-port RAM instead of dual-port  
❌ **Don't**: Mix up camera data bit ordering  

✅ **Do**: Double-check all pin connections  
✅ **Do**: Test VGA output first with simple pattern  
✅ **Do**: Monitor LEDs for debug info  
✅ **Do**: Comment your code well for the report!  

---

## 📚 Next Steps

Once basic system works:
1. Add more creative filters
2. Implement edge detection (Sobel operator)
3. Try motion detection (frame difference)
4. Add freeze frame button
5. Attempt full 640x480 resolution

Good luck with your project! 🎓
