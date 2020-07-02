module DCM
  (
   CLKIN,
   CLKFB,
   RST,
   DSSEN,
   PSINCDEC,
   PSEN,
   PSCLK,
   CLKFX,
   CLKFX180,
   CLKDV,
   CLK2X,
   CLK2X180,
   CLK0,
   CLK90,
   CLK180,
   CLK270,
   LOCKED,
   PSDONE,
   STATUS
   );

   parameter CLKFX_MULTIPLY = 0;
   parameter CLKFX_DIVIDE = 0;
   parameter CLKIN_PERIOD = 0;
   parameter CLK_FEEDBACK = "NONE";

   input CLKIN;
   input CLKFB;
   input RST;
   input DSSEN;
   input PSINCDEC;
   input PSEN;
   input PSCLK;
   output CLKFX;
   output CLKFX180;
   output CLKDV;
   output CLK2X;
   output CLK2X180;
   output CLK0;
   output CLK90;
   output CLK180;
   output CLK270;
   output LOCKED;
   output PSDONE;
   output STATUS;



   reg    clk;

   initial
     clk = 0;

   always #7.8125
     clk <= !clk;

   assign CLKFX = clk;
   assign CLKFX180 = !clk;

endmodule
