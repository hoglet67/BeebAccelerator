`timescale 1ns / 1ns
module beeb_accelerator_tb();

   reg clock = 'b0;
   reg PhiIn = 'b0;
   reg Res_n = 'b1;

   wire [15:0] Addr;
   wire [1:0]  R_W_n;
   wire [7:0]  Data;

   reg [7:0]   ext_memory[0:65535];
   reg [7:0]   mem_out;

   wire        RnW = R_W_n[0];

   integer     i;


   initial
     $readmemh("../src/ram.mem", ext_memory);

   always #10
     clock = !clock;

   always #250
     PhiIn = !PhiIn;

   initial begin
      $dumpvars();

      @(negedge PhiIn);
      Res_n = 'b0;
      @(negedge PhiIn);
      @(negedge PhiIn);
      @(negedge PhiIn);
      @(negedge PhiIn);
      @(negedge PhiIn);
      Res_n = 'b1;
      for (i = 0; i < 200000; i = i + 1)
        @(negedge PhiIn);
      $finish();

   end


   always @(negedge PhiIn)
     if (Addr != 16'hFFFF)
       if (RnW)
         $display("Rd: %04x = %02x", Addr, Data);
       else
         $display("Wr: %04x = %02x", Addr, Data);

   always @(negedge PhiIn)
     if (!RnW)
        ext_memory[Addr] <= Data;

   assign Data = (!RnW || !PhiIn)                               ? 8'hZZ :
                 (Addr[15:8] >= 8'hfc) && (Addr[15:8] <= 8'hfe) ? 8'h00 : ext_memory[Addr];


beeb_accelerator DUT
  (
   .clock(clock),

   // 6502 Signals
   .PhiIn(PhiIn),
   .Phi1Out(),
   .Phi2Out(),
   .IRQ_n(1'b1),
   .NMI_n(1'b1),
   .Sync(),
   .Addr(Addr),
   .R_W_n(R_W_n),
   .Data(Data),
   .SO_n(1'b0),
   .Res_n(Res_n),
   .Rdy(1'b1),

   // 65C02 Signals
   .BE(1'b1),
   .ML_n(),
   .VP_n(),

   // Level Shifter Controls
   .OERW_n(),
   .OEAH_n(),
   .OEAL_n(),
   .OED_n(),
   .DIRD(),

   // External trigger inputs
   .trig(2'b0),

   // ID/mode inputs
   .mode(1'b0),
   .id(4'b0),

   // Serial Console
   .avr_RxD(1'b0),
   .avr_TxD(),

   // Switches
   .sw1(1'b0),
   .sw2(1'b0),

   // LEDs
   .led1(),
   .led2(),
   .led3()

   );

endmodule
