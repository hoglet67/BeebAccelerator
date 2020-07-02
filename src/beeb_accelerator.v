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

   wire        clock64;
   wire        clk0;

   reg [3:0]   clk_div = 'b0;
   reg         Phi0_a;
   reg         Phi0_b;
   reg         Phi0_c;
   reg         Phi0_d;
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
   wire        is_internal;

   reg [7:0]   ram[0:65535];
   reg [7:0]   ram_dout;

   reg         ext_busy;
   reg         ext_cycle_start;
   wire        ext_cycle_end;

   reg [3:0]   rom_latch;

   wire [7:0]  page = cpu_AB[15:8];


   // 50->64MHz clock
   DCM
     #(
       .CLKFX_MULTIPLY   (32),
       .CLKFX_DIVIDE     (25),
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
      .CLKFX            (clock64),
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
     $readmemh("../src/ram.mem", ram);

   // Shadow ROM latch
   always @(posedge clock64)
     if (cpu_clken)
       if (cpu_WE && cpu_AB == 16'hFE30)
         rom_latch <= cpu_DO[3:0];

   // Internal 64KB Block RAM
   always @(posedge clock64)
     if (cpu_clken) begin
        if (cpu_WE_next & !cpu_AB_next[15])
          ram[cpu_AB_next] <= cpu_DO_next;
        ram_dout <= ram[cpu_AB_next];
     end

   // Clock delay chain; each step is 20ns
   always @(posedge clock64) begin
      Phi0_a <= PhiIn;
      Phi0_b <= Phi0_a;
      Phi0_c <= Phi0_b;
      Phi0_d <= Phi0_c;
      // 64/8=8.00MHz
      if (clk_div == 7)
        clk_div <= 'b0;
      else
        clk_div <= clk_div + 1'b1;
   end

   assign Phi1Out = !Phi0_b;
   assign Phi2Out =  Phi0_b;

   // Arlet's 65C02 Core
   cpu_65c02 cpu
     (
      .clk(clock64),
      .reset(cpu_reset),
      .AB(cpu_AB_next),
      .DI(cpu_DI),
      .DO(cpu_DO_next),
      .WE(cpu_WE_next),
      .IRQ(cpu_IRQ),
      .NMI(cpu_NMI),
      .RDY(cpu_clken)
      );

   // Determine if the access is internal or external
   assign is_internal = !((page >= 8'h30 && page < 8'h80 && cpu_WE)          | // Writes to Screen RAM are external
                          (page >= 8'h80 && page < 8'hC0 && rom_latch != 15) | // Accesses to ROMs other then BASIC are external
                          (page >= 8'hfc && page < 8'hff)                      // Accesses to IO are external
                          );

   // When to advance the internal core a tick
   assign cpu_clken = (is_internal && clk_div == 0) ? 1'b1 :
                      (ext_busy && ext_cycle_end) ? 1'b1 :
                      1'b0;

   // Offset the external cycle by a couple of ticks to give some address hold time
   assign ext_cycle_end = Phi0_d & !Phi0_c;

   always @(posedge clock64) begin
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
   end

   // Register the outputs of Arlet's core
   always @(posedge clock64) begin
      if (cpu_clken) begin
         cpu_AB <= cpu_AB_next;
         cpu_WE <= cpu_WE_next;
         cpu_DO <= cpu_DO_next;
      end
   end

   // Synchronise possible asynchronous inputs
   always @(posedge clock64) begin
      cpu_reset <= !Res_n;
      cpu_IRQ <= !IRQ_n;
      cpu_NMI <= !NMI_n;
   end

   assign cpu_DI = is_internal ? ram_dout : data_r;

   // Sample Data on the falling edge of Phi0_a
   always @(negedge PhiIn) begin
      data_r <= Data;
   end

   assign Data    = (Phi0_c & beeb_WE) ? beeb_DO : 8'bZ;
   assign Addr    = beeb_AB;
   assign R_W_n   = {2{!beeb_WE}};
   assign Sync    = 'b0;

   // 65C02 Outputs
   assign ML_n    = 'b1;
   assign VP_n    = 'b1;

   // Level Shifter Controls
   assign OERW_n  = 'b0;
   assign OEAH_n  = 'b0;
   assign OEAL_n  = 'b0;
   assign OED_n   = !(BE & PhiIn & Phi0_d);
   assign DIRD    = !beeb_WE;

   // Misc
   assign led1    = !sw1;
   assign led2    = !sw2;
   assign led3    = &{mode, id, trig, SO_n, Rdy};
   assign avr_TxD = avr_RxD;

endmodule
