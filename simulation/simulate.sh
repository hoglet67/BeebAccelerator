#!/bin/bash

iverilog beeb_accelerator_tb.v ../src/beeb_accelerator.v ../src/cpu_65c02.v ../src/ALU.v dcm.v
./a.out
gtkwave -g -a signals.gtkw dump.vcd
