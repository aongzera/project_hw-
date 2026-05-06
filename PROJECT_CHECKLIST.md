# Project Checklist - OV7670 Camera to VGA System

Use this checklist to track your progress and ensure you meet all project requirements.

## Phase 1: Initial Progress (Due: One week after announcement)

### Group Formation
- [ ] Form group of 3-4 students
- [ ] Submit team member list to instructor
- [ ] Assign roles (hardware, coding, testing, documentation)

### Filter Planning
- [ ] Choose 3 image filters to implement
- [ ] Document filter selection:
  1. Filter 1: ___________________________
  2. Filter 2: ___________________________
  3. Filter 3: ___________________________
- [ ] Submit initial progress document

**📝 Note**: The provided code includes 8 filters. Pick any 3 for your submission.

---

## Hardware Setup

### Camera Connection
- [ ] Verify camera module pins and voltage (3.3V ONLY!)
- [ ] Connect all data lines (D0-D7) correctly
- [ ] Connect control signals (HREF, PCLK, VSYNC, XCLK)
- [ ] Connect SCCB interface (SCL, SDA with pull-up)
- [ ] Connect power (VCC=3.3V, GND)
- [ ] Connect reset and power-down pins
- [ ] Double-check all connections with multimeter

### VGA Connection
- [ ] Connect VGA cable to monitor
- [ ] Verify monitor supports 640x480 @ 60Hz
- [ ] Test with simple VGA pattern first

### Basys 3 Setup
- [ ] Board powered and recognized by computer
- [ ] USB cable connected
- [ ] Switches and buttons functional

---

## Vivado Project Setup

### Project Creation
- [ ] Create new RTL project in Vivado
- [ ] Select correct FPGA part (xc7a35tcpg236-1)
- [ ] Add all .v source files
- [ ] Add constraints file (.xdc)
- [ ] Verify file hierarchy

### IP Core Generation
- [ ] Generate Clock Wizard (clk_wiz_0)
  - [ ] 25 MHz output for VGA
  - [ ] 24 MHz output for camera
  - [ ] Locked signal enabled
- [ ] Generate Block Memory (optional but recommended)
  - [ ] True Dual Port RAM
  - [ ] 12-bit width, 76800 depth
  - [ ] Both ports configured identically

### Synthesis and Implementation
- [ ] Run syntax check (no errors)
- [ ] Run synthesis successfully
- [ ] Review resource utilization report
- [ ] Run implementation successfully
- [ ] Check timing constraints (no violations)
- [ ] Generate bitstream

---

## Testing and Debugging

### Module-Level Testing
- [ ] VGA controller testbench passes
- [ ] Image filter testbench passes
- [ ] Simulate camera capture (if possible)

### System Integration Testing
- [ ] Program FPGA with bitstream
- [ ] Verify configuration complete (LED0 ON)
- [ ] Camera captures frames (LED1-3 activity)
- [ ] VGA displays image on monitor
- [ ] All 3+ filters work correctly
- [ ] Can switch between filters using switches

### Performance Validation
- [ ] Frame rate stable (~30 fps expected)
- [ ] No visible tearing or artifacts
- [ ] Image quality acceptable
- [ ] Colors appear correct (try color chart)

---

## Code Quality

### Source Code
- [ ] All modules properly commented
- [ ] Signal names are descriptive
- [ ] Code follows consistent style
- [ ] No hardcoded magic numbers (use parameters)
- [ ] State machines documented with diagrams
- [ ] Timing parameters clearly explained

### Testbenches
- [ ] Comprehensive testbenches for major modules
- [ ] Test cases cover edge cases
- [ ] Simulation waveforms demonstrate correctness
- [ ] All tests pass before synthesis

---

## Documentation

### System Block Diagram
- [ ] Create complete system block diagram
- [ ] Show all major modules
- [ ] Indicate clock domains
- [ ] Show data flow paths
- [ ] Label bit widths on buses
- [ ] Include in presentation

### Final Report Contents
- [ ] Introduction/Overview
- [ ] System architecture description
- [ ] Module descriptions (each major block)
- [ ] State machine diagrams
- [ ] Timing analysis
- [ ] Test results and validation
- [ ] Challenges faced and solutions
- [ ] Resource utilization analysis
- [ ] Conclusion and future work
- [ ] References

### AI Usage Declaration (CRITICAL)
- [ ] Document if/where AI was used
- [ ] Be specific: "Used ChatGPT for VGA timing generation"
- [ ] List all AI tools used (ChatGPT, Copilot, etc.)
- [ ] Failure to disclose = severe penalty

**Example Declaration:**
```
AI Tools Used:
- ChatGPT: Generated initial VGA controller timing logic
- GitHub Copilot: Autocomplete for standard SCCB I2C protocol
- Claude: Helped debug frame buffer addressing calculation
```

---

## Demo Preparation

### Pre-Demo Checklist (Day Before)
- [ ] Test complete system from fresh bitstream
- [ ] Verify all filters work
- [ ] Practice presentation (5-7 minutes)
- [ ] Prepare to answer technical questions
- [ ] Bring backup hardware (extra camera if possible)
- [ ] Have block diagram ready (printed or slides)
- [ ] Know your resource utilization numbers
- [ ] Understand all clock domains

### Demo Day Setup
- [ ] Arrive early to set up
- [ ] Test system before instructor arrives
- [ ] Have code pulled up on laptop
- [ ] Block diagram visible
- [ ] Can explain each module's function
- [ ] Ready to answer questions about:
  - [ ] How camera interface works
  - [ ] Frame buffer implementation
  - [ ] VGA timing generation
  - [ ] Filter algorithms
  - [ ] Clock domain crossing

### Questions to Prepare For
- [ ] "Why did you choose these filters?"
- [ ] "How does the frame buffer handle clock domains?"
- [ ] "What's the pixel data format through each stage?"
- [ ] "How would you implement [different filter]?"
- [ ] "What was the most challenging part?"
- [ ] "How would you achieve 640x480 resolution?"

---

## Extra Credit Opportunities

### Full VGA Resolution (640x480)
- [ ] Camera configured for VGA mode
- [ ] Memory architecture redesigned
- [ ] Line buffer or reduced color depth
- [ ] Successfully demonstrated

### Neural Network Detection/Classification
- [ ] NN framework selected (FINN, etc.)
- [ ] Model compiled to hardware
- [ ] Detection implemented and working
- [ ] Non-trivial task (face/hand detection)

### Advanced Upscaling (1280x960)
- [ ] Bilinear or bicubic filter implemented
- [ ] Hardware interpolation logic
- [ ] Quality superior to nearest-neighbor

### Custom Extra Credit
- [ ] Idea proposed to instructor
- [ ] Approval received
- [ ] Implementation completed
- [ ] Demonstrated successfully

---

## Final Submission Checklist

### Files to Submit
- [ ] All source code (.v files)
- [ ] Testbench files
- [ ] Constraints file (.xdc)
- [ ] Final report (PDF)
- [ ] Block diagram (high resolution)
- [ ] Simulation waveforms (screenshots)
- [ ] Resource utilization report
- [ ] AI usage declaration

### Report Quality
- [ ] Professional formatting
- [ ] No spelling/grammar errors
- [ ] All figures labeled and referenced
- [ ] Code snippets formatted properly
- [ ] Page numbers included
- [ ] Table of contents (if >10 pages)

---

## Grading Breakdown Reference

| Category | Points | Status |
|----------|--------|--------|
| Phase 1 Submission | 5 | ☐ |
| Simulation & Testbenches | 5 | ☐ |
| Hardware Interface & Base Resolution | 10 | ☐ |
| Three Image Filters | 10 | ☐ |
| Project Demonstration | 5 | ☐ |
| Code Quality & Report | 5 | ☐ |
| **Total** | **40** | |
| Extra Credit | +5 | ☐ |

---

## Time Management

Suggested timeline (adjust based on your schedule):

**Week 1:**
- [ ] Phase 1 submission
- [ ] Hardware connections
- [ ] Vivado project setup

**Week 2:**
- [ ] Camera interface working
- [ ] VGA output functional
- [ ] Frame buffer implemented

**Week 3:**
- [ ] Filters implemented
- [ ] System integration
- [ ] Testing and debugging

**Week 4:**
- [ ] Report writing
- [ ] Demo preparation
- [ ] Final testing

---

## Success Criteria

Minimum for passing:
✓ Camera captures video
✓ VGA displays on monitor
✓ At least 3 filters work
✓ Code is readable and commented
✓ Demo successful
✓ Report complete

For excellent grade:
✓ All of above
✓ Additional creative filters
✓ Comprehensive documentation
✓ Clean, modular code
✓ Extra credit attempted

---

**Good luck with your project!** 🎓🚀
