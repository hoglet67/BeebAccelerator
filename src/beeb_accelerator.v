// -----------------------------------------------------------------------------
// Copyright (c) 2020 David Banks
// -----------------------------------------------------------------------------
//   ____  ____
//  /   /\/   /
// /___/  \  /
// \   \   \/
//  \   \
//  /   /         Filename  : beeb_accelerator.v
// /___/   /\     Timestamp : 02/07/2020
// \   \  /  \
//  \___\/\___\
//
// Design Name: beeb_accelerator
// Device: XC6SLX9

module beeb_accelerator
(
 input         clock,

 // 6502 Signals
 input         PhiIn,
 output        Phi1Out,
 output        Phi2Out,
 input         IRQ_n,
 input         NMI_n,
 output        Sync,
 output [15:0] Addr,
 output [1:0]  R_W_n,
 inout [7:0]   Data,
 input         SO_n,
 input         Res_n,
 input         Rdy,

 // 65C02 Signals
 input         BE,
 output        ML_n,
 output        VP_n,

 // Level Shifter Controls
 output        OERW_n,
 output        OEAH_n,
 output        OEAL_n,
 output        OED_n,
 output        DIRD,

 // External trigger inputs
 input [1:0]   trig,

 // ID/mode inputs
 input         mode,
 input [3:0]   id,

 // Serial Console
 input         avr_RxD,
 output        avr_TxD,

 // Switches
 input         sw1,
 input         sw2,

 // LEDs
 output        led1,
 output        led2,
 output        led3

 );

   // 50 MHz
   //localparam  NPHI0_REGS = 3;
   //localparam  PHIOUT_TAP = 1;
   //localparam  DCM_MULT   = 2;
   //localparam  DCM_DIV    = 2;

   // 64 MHz - meets timing
   //localparam  NPHI0_REGS = 4;
   //localparam  PHIOUT_TAP = 1;
   //localparam  DCM_MULT   = 32;
   //localparam  DCM_DIV    = 25;

   // 80MHz - meets timing
   localparam  NPHI0_REGS = 5;
   localparam  PHIOUT_TAP = 1;
   localparam  DCM_MULT   = 8;
   localparam  DCM_DIV    = 5;

   // 100 MHz (doesn't meet timing, but seems stable in practice)
   //localparam  NPHI0_REGS = 6;
   //localparam  PHIOUT_TAP = 1;
   //localparam  DCM_MULT   = 4;
   //localparam  DCM_DIV    = 2;

   wire        cpu_clk;
   wire        clk0;

   reg [5:0]   clk_div = 'b0;
   reg [5:0]   cpu_div = 'b0;

   reg [NPHI0_REGS-1:0] Phi0_r;

   wire        cpu_clken;
   reg         cpu_reset;
   wire [15:0] cpu_AB_next;
   reg [15:0]  cpu_AB;
   reg [15:0]  beeb_AB;
   wire [7:0]  cpu_DI;
   reg [7:0]   data_r;
   wire [7:0]  cpu_DO_next;
   reg [7:0]   cpu_DO;
   reg [7:0]   beeb_DO;
   wire        cpu_WE_next;
   reg         cpu_WE;
   reg         beeb_WE;
   reg         cpu_IRQ;
   reg         cpu_NMI;
   reg         cpu_RDY;
   wire        cpu_SYNC;
   wire        is_internal;
   reg [3:0]   force_slowdown = 4'b0;

   reg [7:0]   ram[0:65535];
   reg [7:0]   ram_dout;

   reg         ext_busy;
   reg         ext_cycle_start;
   wire        ext_cycle_end;

   reg [3:0]   rom_latch;

   wire [7:0]  page = cpu_AB[15:8];

   reg         shadow = 1'b0;
   reg         vdu_op;

   wire        is_FE30 = (cpu_AB[15:4] == 12'hFE3) && (cpu_AB[3:2] == 2'b00);
   wire        is_FE34 = (cpu_AB[15:4] == 12'hFE3) && (cpu_AB[3:2] == 2'b01);
   wire        is_FE38 = (cpu_AB[15:4] == 12'hFE3) && (cpu_AB[3:2] == 2'b10);


   // PLL to generate CPU clock of 50 * DCM_MULT / DCM_DIV MHz
   DCM
     #(
       .CLKFX_MULTIPLY   (DCM_MULT),
       .CLKFX_DIVIDE     (DCM_DIV),
       .CLKIN_PERIOD     (20.000),
       .CLK_FEEDBACK     ("1X")
       )
   DCM1
     (
      .CLKIN            (clock),
      .CLKFB            (clk0),
      .RST              (1'b0),
      .DSSEN            (1'b0),
      .PSINCDEC         (1'b0),
      .PSEN             (1'b0),
      .PSCLK            (1'b0),
      .CLKFX            (cpu_clk),
      .CLKFX180         (),
      .CLKDV            (),
      .CLK2X            (),
      .CLK2X180         (),
      .CLK0             (clk0),
      .CLK90            (),
      .CLK180           (),
      .CLK270           (),
      .LOCKED           (),
      .PSDONE           (),
      .STATUS           ()
      );

   // Internal 64KB Block RAM - initialization data
   initial
     $readmemh("../src/ram_os12.mem", ram);

   // Writable Registers
   always @(posedge cpu_clk)
     if (cpu_clken) begin
        if (cpu_WE) begin
           if (is_FE30)
             rom_latch <= cpu_DO[3:0];
           if (is_FE34)
             shadow <= cpu_DO[7];
           if (is_FE38)
             cpu_div <= cpu_DO[5:0] - 1'b1;
        end
     end

   // Internal 64KB Block RAM
   always @(posedge cpu_clk)
     if (cpu_clken) begin
        if (cpu_WE_next && !cpu_AB_next[15] && (cpu_AB_next[14:12] < 3'b011 || !vdu_op || !shadow))
          ram[cpu_AB_next] <= cpu_DO_next;
        ram_dout <= ram[cpu_AB_next];
     end

   // Clock delay chain
   always @(posedge cpu_clk) begin
      // Synchronise/delay PhiIn
      Phi0_r <= { Phi0_r[NPHI0_REGS-2:0], PhiIn };
      // Internally the CPU runs at 64/CPU_DIV MHz
      if (clk_div == cpu_div)
        clk_div <= 'b0;
      else
        clk_div <= clk_div + 1'b1;
   end

   assign Phi1Out = !Phi0_r[PHIOUT_TAP];
   assign Phi2Out =  Phi0_r[PHIOUT_TAP];

   // Arlet's 65C02 Core
   cpu_65c02 cpu
     (
      .clk(cpu_clk),
      .reset(cpu_reset),
      .AB(cpu_AB_next),
      .DI(cpu_DI),
      .DO(cpu_DO_next),
      .WE(cpu_WE_next),
      .IRQ(cpu_IRQ),
      .NMI(cpu_NMI),
      .RDY(cpu_clken),
      .SYNC(cpu_SYNC)
      );

   // Determine if the access is internal or external
   assign is_internal = !((page >= 8'h30 && page < 8'h80 && (shadow ? vdu_op : cpu_WE)) | // Accesses to Screen RAM from the first half of the OS are external
                          (page >= 8'h80 && page < 8'hC0 && rom_latch != 15) | // Accesses to ROMs other then BASIC are external
                          (page >= 8'hfc && page < 8'hff)                      // Accesses to IO are external
                          ) | is_FE34 | is_FE38;

   // When to advance the internal core a tick
   assign cpu_clken = (is_internal && clk_div == 0 && !(|force_slowdown)) ? 1'b1 :
                      (ext_busy && ext_cycle_end) ? 1'b1 :
                      1'b0;

   // Offset the external cycle by a couple of ticks to give some address hold time
   assign ext_cycle_end = Phi0_r[NPHI0_REGS-1] & !Phi0_r[NPHI0_REGS-2];

   always @(posedge cpu_clk) begin
      ext_cycle_start <= ext_cycle_end;
      if (ext_cycle_start) begin
         if (is_internal) begin
            beeb_AB  <= 16'hFFFF;
            beeb_WE  <=  1'b0;
            beeb_DO  <=  8'hFF;
            ext_busy <=  1'b0;
         end else begin
            beeb_AB  <= cpu_AB;
            beeb_WE  <= cpu_WE;
            beeb_DO  <= cpu_DO;
            ext_busy <= 1'b1;
         end
      end
      // Following a write to the addressable latch, we need to slow the CPU for
      // a further few cycles, otherwise the keyboard and sound chips misbehave.
      // In the case of the sound chip, a software delay loop gives a write pulse
      // of 9us. A force_slowdown of ~15 minics this (assume bus cycles are 500ns).
      // In the case of the keyboard, a much smaller delay is acceptable, and we
      // we set force_slowdown to 1. When ever force_slowdown is non-zero, the
      // CPU runs at a maximum of 2MHz.
      if (ext_cycle_end)
        if (cpu_AB == 16'hfe40 && cpu_WE)
          if (cpu_DO[2:0] == 0)
            force_slowdown <= 'hf;
          else
            force_slowdown <= 'h1;
        else if (force_slowdown > 0)
          force_slowdown <= force_slowdown - 1'b1;
      // Writes to the speed register
   end

   // Register the outputs of Arlet's core
   always @(posedge cpu_clk) begin
      if (cpu_clken) begin
         cpu_AB <= cpu_AB_next;
         cpu_WE <= cpu_WE_next;
         cpu_DO <= cpu_DO_next;
         if (cpu_SYNC)
           vdu_op <= cpu_AB[15:13] == 3'b110;
      end
   end

   // Synchronise asynchronous inputs
   always @(posedge cpu_clk) begin
      cpu_reset <= !Res_n;
      cpu_IRQ <= !IRQ_n;
      cpu_NMI <= !NMI_n;
   end

   // CPU Din Multiplexor
   assign cpu_DI = is_FE34     ? {shadow, 7'b0}    :
                   is_FE38     ? {2'b0, cpu_div}   :
                   is_FE30     ? {4'b0, rom_latch} :
                   is_internal ? ram_dout          :
                   data_r;

   // Sample Data on the falling edge of Phi2 (ref A in the datasheet)
   always @(negedge Phi2Out) begin
      data_r <= Data;
   end

   assign Data    = (beeb_WE & PhiIn) ? beeb_DO : 8'bZ;
   assign Addr    = beeb_AB;
   assign R_W_n   = {2{!beeb_WE}};
   assign Sync    = cpu_SYNC;

   // 65C02 Outputs
   assign ML_n    = 'b1;
   assign VP_n    = 'b1;

   // Level Shifter Controls
   assign OERW_n  = 'b0;
   assign OEAH_n  = 'b0;
   assign OEAL_n  = 'b0;
   assign OED_n   = !(BE & PhiIn);
   assign DIRD    = !beeb_WE;

   // Misc
   assign led1    = !sw1;
   assign led2    = !sw2;
   assign led3    = &{mode, id, trig, SO_n, Rdy};
   assign avr_TxD = avr_RxD;

endmodule
