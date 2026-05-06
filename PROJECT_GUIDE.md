# Real-Time Video Capture & Processing — Project Guide

A plain-English walkthrough of how this project is split up, what each Verilog
file does, and which part of the requirement it covers.

---

## The Big Picture (data flow)

```
   ┌──────────┐  pclk/href/vsync/D[7:0]  ┌────────────┐  RGB444  ┌──────────────┐
   │  OV7670  │ ───────────────────────► │  CAPTURE   │ ───────► │ FRAME BUFFER │
   │  camera  │                          │ (FSM, RGB  │   write  │  (BRAM, dual │
   │          │                          │  packing)  │          │   port)      │
   └─────▲────┘                          └────────────┘          └──────┬───────┘
         │ XCLK 24 MHz                                                  │ read
         │                                ┌────────────┐                │
         │                                │ VGA TIMING │                ▼
         │                                │ (counters, │  ┌─────────────────────┐
         │           ┌────────────┐       │ hsync/vsync│  │  IMAGE FILTER       │
         └───────────│  SCCB CFG  │       │ generator) │  │ (grayscale / invert │
            SCL/SDA  │ (I2C-like  │       └─────┬──────┘  │  / threshold / ...) │
                     │ master)    │             │ x,y,    └──────────┬──────────┘
                     └────────────┘             │ active             │ filtered RGB
                                                │                    │
                                                └──────────┬─────────┘
                                                           ▼
                                                      VGA monitor
                                                  (R/G/B + HSYNC/VSYNC)
```

Everything is wired together by the **top module** (`camera_vga_top.v`).

---

## The 7 Parts of the Project

### 1. Camera configuration (SCCB / I²C)
Tell the OV7670 *what* to output (resolution, pixel format, color matrix, etc.).
Without this, the camera powers up in a default mode that is not 320×240
RGB and we cannot interpret the bytes coming out of it.

- **File:** `ov7670_config.v`
- **Job:** Acts as a tiny SCCB master. Walks through a 32-entry table of
  `{register_address, value}` pairs and writes each one to camera address
  `0x42` using a `START → addr → reg → data → STOP` sequence. Asserts
  `config_done` when finished.
- **Logic:** A clock divider drops 100 MHz → ~200 kHz `sioc` (SCL). A state
  machine (`IDLE / START / ADDR_WRITE / REG_WRITE / DATA_WRITE / STOP /
  NEXT_REG / DONE`) shifts the bits out on `siod` (SDA), one bit per SCCB
  clock period. `siod` is a tristate `inout` — `sda_oe=0` releases it for the
  ACK / don't-care bit.
- **Covers requirement:** *"Configure the OV7670 camera via the SCCB
  (I2C-like) protocol."*

### 2. Pixel capture (camera → memory)
Read the parallel pixel bytes coming out of the camera in real time and pack
them into one address per pixel for the frame buffer.

- **File:** `ov7670_capture.v`
- **Job:** Watches `vsync` and `href` to know where a frame and each line
  starts/ends. Two camera bytes form one RGB565 pixel; this module assembles
  the pair, truncates it to RGB444 (12 bits), and writes it to the frame
  buffer at address `pixel_y * 320 + pixel_x`.
- **Logic:** A small FSM (`WAIT_FRAME / CAPTURE_BYTE1 / CAPTURE_BYTE2`)
  alternates between latching byte 1 and byte 2. On the falling edge of
  `href` (end of a line) it resets `pixel_x` and increments `pixel_y`. On
  the falling edge of `vsync` (start of a frame) it resets both counters and
  arms `frame_active`.
- **Covers requirement:** *"correctly capture the incoming parallel pixel
  data and synchronization signals (PCLK, VSYNC, HREF)."*

### 3. Frame buffer (BRAM storage)
Bridge the **camera clock domain** (≈24 MHz `pclk`) and the **VGA clock
domain** (25 MHz). The camera writes pixels in raster order; the VGA side
reads them out in its own raster order — at a different rate.

- **File:** `frame_buffer.v`
- **Job:** True dual-port Block RAM, 76 800 × 12 bits (= 320×240 pixels of
  RGB444). Port A is write-only on the camera side; Port B is read-only on
  the VGA side. Each port has its own clock.
- **Logic:** `(* ram_style = "block" *)` tells Vivado to map this onto BRAM
  blocks (~26 of the 50 available on Basys 3). Synchronous write on Port A
  when `wea=1`. Synchronous read on Port B (1 cycle latency).
- **Covers requirement:** *"Memory Management (Frame Buffer): Store the
  captured image data in the Basys 3's internal Block RAM."*

### 4. VGA timing generator
Produce the 640×480 @ 60 Hz raster signals a VGA monitor expects. The
monitor doesn't know about our 320×240 — it only locks onto `hsync`/`vsync`
and samples the RGB pins during the 640×480 active window.

- **File:** `vga_controller.v`
- **Job:** Drives `hsync`, `vsync`, `active`, `x_pos`, `y_pos` from a 25 MHz
  pixel clock.
- **Logic:** Two counters — `h_count` (0→799) and `v_count` (0→524). All
  outputs are computed from a combinational *next-state* (`h_next`,
  `v_next`) so that `(x_pos, y_pos, hsync, vsync, active)` are all
  phase-aligned. `hsync`/`vsync` are active LOW only while the position is
  inside the sync window of the blanking interval. `active` is high inside
  the 640×480 visible window.
- **Covers requirement:** *"VGA Output: Generate the correct horizontal and
  vertical sync signals (HSYNC, VSYNC) to drive a VGA monitor."*

### 5. Pixel doubling (320×240 → 640×480)
The frame buffer only stores 320×240 pixels but the monitor wants 640×480.
We "double" each pixel: hold the same column for two `x` clocks, repeat the
same row for two `y` lines.

- **File:** Done inside `camera_vga_top.v` (one line):
  `assign read_addr = (vga_y[9:1] * 320) + vga_x[9:1];`
- **Job:** Strip the lowest bit of x and y when computing the read address.
  This naturally maps every 2×2 block of VGA pixels back to a single frame
  buffer pixel.
- **Covers requirement:** *"320×240 displayed at 640×480 via pixel
  doubling."*

### 6. Image processing filters
Modify each pixel between BRAM and VGA output, in real time, with the user
selecting the mode via Basys 3 slide switches.

- **File:** `image_filter.v`
- **Job:** Pure combinational. Takes 12-bit RGB444 in, 3-bit `filter_sel`
  in, returns 12-bit RGB444 out. Modes:
  - `000` Pass-through
  - `001` Grayscale (Y ≈ (R + 2G + B)/4)
  - `010` Color invert (negative)
  - `011` Threshold (binary black/white based on brightness)
  - `100/101/110` Red-only / Green-only / Blue-only
  - `111` Brightness boost (saturating add)
- **Logic:** A `case (filter_sel)` over the 8 modes. Grayscale uses a
  weighted shift-and-add approximation (no multiplier needed). Threshold
  sums the three channels and compares against a fixed mid-level. Channel
  isolation just zeros the other two channels.
- **Covers requirement:** *"three different hardware-based image filters …
  applied in real-time, togglable via switches."* (You only need three of
  the eight modes for full marks; the rest are bonus.)

### 7. Top-level integration & pin mapping
Glue everything into one Basys 3 bitstream.

- **Files:**
  - `camera_vga_top.v` — instantiates the clock wizard, `ov7670_config`,
    `ov7670_capture`, `frame_buffer`, `vga_controller`, `image_filter`, and
    wires them up. Also drives `camera_xclk = 24 MHz`, holds `camera_pwdn`
    low, `camera_reset` high, and uses LEDs as status (`config_done`,
    `vsync`, `href`, `write_enable`).
  - `basys3_camera.xdc` — physical pin assignment: camera connector, VGA
    connector, slide switches, LEDs, the 100 MHz system clock, and timing
    constraints (24 MHz pclk constraint, async clock-group statements
    between camera and system clocks).
- **Covers requirement:** *Hardware interfacing & physical board bringup.*

---

## Bonus part: Testbenches (Rubric: 5 pts)

| File | What it verifies |
|------|------------------|
| `tb_vga_controller.v` | 800×525 timing, HSYNC/VSYNC pulse positions, 307 200 active pixels per frame, pixel-doubling math |
| `tb_image_filter.v`   | Each `filter_sel` mode produces the expected output for a few sample pixels |

The rubric also asks for testbenches for the **SCCB master** and the
**memory addressing** — those are not in the repo yet and are easy points
to grab.

---

## Quick file map (reference)

| File | Type | What it is |
|------|------|------------|
| `camera_vga_top.v`     | RTL | Top module — wires all the pieces together |
| `ov7670_config.v`      | RTL | SCCB master that initializes the camera |
| `ov7670_capture.v`     | RTL | Camera-side FSM, builds RGB444 pixels into the BRAM |
| `frame_buffer.v`       | RTL | Dual-port BRAM (320×240 × 12 bits) |
| `vga_controller.v`     | RTL | 640×480@60 timing generator |
| `image_filter.v`       | RTL | 8-mode RGB444 pixel filter |
| `basys3_camera.xdc`    | Constraints | FPGA pin map + clock constraints |
| `tb_vga_controller.v`  | Sim | VGA timing testbench |
| `tb_image_filter.v`    | Sim | Filter modes testbench |
| `run_sim.sh`           | Script | Convenience runner for the testbenches |

---

## How a single pixel travels through the system

1. Light hits the camera sensor.
2. After the camera was configured (step 1), it shifts two bytes of RGB565
   onto `D[7:0]` over two `pclk` cycles.
3. `ov7670_capture.v` (step 2) latches both bytes, packs them into RGB444,
   and writes to address `pixel_y*320 + pixel_x` in BRAM.
4. Independently, `vga_controller.v` (step 4) sweeps `x_pos` 0→799 and
   `y_pos` 0→524 at 25 MHz.
5. The top module (step 5) maps `(x_pos>>1, y_pos>>1)` → BRAM read address.
6. BRAM returns the stored RGB444 one cycle later.
7. `image_filter.v` (step 6) transforms the pixel based on the slide
   switches.
8. The top module gates the result with `active` and drives the 12-bit RGB
   plus `hsync`/`vsync` out to the VGA connector.
9. The monitor displays it.
