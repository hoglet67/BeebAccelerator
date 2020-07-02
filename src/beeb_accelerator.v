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

   reg         Phi0_a;
   reg         Phi0_b;
   reg         Phi0_c;
   reg         Phi0_d;
   wire        cpu_clk;
   reg         cpu_reset;
   wire [15:0] cpu_AB_next;
   reg [15:0]  cpu_AB;
   reg [7:0]   cpu_DI;
   wire [7:0]  cpu_DO_next;
   reg [7:0]   cpu_DO;
   wire        cpu_WE_next;
   reg         cpu_WE;
   reg         cpu_IRQ;
   reg         cpu_NMI;
   reg         cpu_RDY;

   always @(posedge clock) begin
      Phi0_a <= PhiIn;
      Phi0_b <= Phi0_a;
      Phi0_c <= Phi0_b;
      Phi0_d <= Phi0_c;
   end

   assign Phi1Out = !Phi0_b;
   assign Phi2Out =  Phi0_b;
   assign cpu_clk = !Phi0_d;

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
      .RDY(cpu_RDY)
      );

   always @(posedge cpu_clk) begin
      cpu_reset <= !Res_n;
      cpu_IRQ <= !IRQ_n;
      cpu_NMI <= !NMI_n;
      cpu_AB  <= cpu_AB_next;
      cpu_WE  <= cpu_WE_next;
      cpu_DO  <= cpu_DO_next;
   end

   // 6502: Sample Rdy on the rising edge of Phi0
   // 65C02: Sample Rdy on the falling edge of Phi0
   always @(negedge PhiIn) begin
      cpu_RDY <= Rdy;
   end

   // Sample Data on the falling edge of Phi0_a
   always @(negedge PhiIn) begin
      cpu_DI <= Data;
   end

   assign Data    = (Phi0_c & cpu_WE) ? cpu_DO : 8'bZ;
   assign Addr    = cpu_AB;
   assign R_W_n   = {2{!cpu_WE}};
   assign Sync    = 'b0;

   // 65C02 Outputs
   assign ML_n    = 'b1;
   assign VP_n    = 'b1;

   // Level Shifter Controls
   assign OERW_n  = 'b0;
   assign OEAH_n  = 'b0;
   assign OEAL_n  = 'b0;
   assign OED_n   = !(BE & PhiIn & Phi0_d);
   assign DIRD    = !cpu_WE;

   // Misc
   assign led1    = !sw1;
   assign led2    = !sw2;
   assign led3    = &{mode, id, trig, SO_n};
   assign avr_TxD = avr_RxD;

endmodule
