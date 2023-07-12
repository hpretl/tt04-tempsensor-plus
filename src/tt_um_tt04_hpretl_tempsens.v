//	Copyright 2023 Harald Pretl
//
//	Licensed under the Apache License, Version 2.0 (the "License");
//	you may not use this file except in compliance with the License.
//	You may obtain a copy of the License at
//
//		http://www.apache.org/licenses/LICENSE-2.0
//
//	Unless required by applicable law or agreed to in writing, software
//	distributed under the License is distributed on an "AS IS" BASIS,
//	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//	See the License for the specific language governing permissions and
//	limitations under the License.

//	TODO
//	- Simulate logic
//	- Simulate mixed-signal

`default_nettype none

`include "tempsense.v"
`include "seg7.v"
`include "bin2dec.v"

module tt_um_tt04_hpretl_tempsens (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // Will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

	assign uio_oe = 8'b1;		// all IOs used as outputs

	// size the design with these constants
	localparam N_VDAC = 7; // number of bits of voltage DAC
	localparam N_LUT = 7; // wordsize of LUT (should match N_VDAC)
	localparam N_CTR = 14; // 2**N_CTR gives roughly a second tick @ clk=10kHz
	localparam N_PRECTR = 10; // Use a pre-counter if clk=10MHz

	// pre-loaded LUT based on nominal simulation results
	`include "tempsens_precal.v"
		
	// definition of inputs
	wire reset = ~rst_n;
	wire cal_clk = ui_in[0];
	wire cal_dat = ui_in[1];
	wire cal_ena = ui_in[2];
	wire use_prectr = ui_in[3];
	wire [3:0] en_dbg = ui_in[7:4];

	/* verilator lint_off UNUSEDSIGNAL */
	wire dummy1 = |uio_in;
	wire dummy2 = ena;
	/* verilator lint_on UNUSEDSIGNAL */

	// definition of outputs
	wire [7:0] led_out;
	wire [6:0] led_segments;
	wire led_dot = show_ones;
	assign uo_out[7:0] = led_out; 

	// declaration of internal wires and regs
	reg [N_CTR-1:0] ctr;
	reg [N_PRECTR-1:0] prectr;
	reg [N_VDAC-1:0] tempsens_res_raw;
	wire [N_VDAC-1:0] tempsens_res;
	reg temp_delay_last;
	reg [(2**N_VDAC)*N_LUT:1] cal_lut;

	// we use ctr as efficient state coder:
	// 1:0 = measurement state
	// N_VDAC+1:2 = value we set at DAC
	// MSB:N_VDAC+2 = if at least one bit is set then in the idle period
	// MSB of ctr switches the LED digit and the LED dot
	wire [1:0] meas_state = ctr[1:0];
	wire [N_VDAC-1:0] dac_value = {N_VDAC{1'b1}} - ctr[N_VDAC+1:2];
	wire idle_cycle = |ctr[N_CTR-1:N_VDAC+2];
	wire show_tens = ~ctr[N_CTR-1];
	wire show_ones = ctr[N_CTR-1];

	// state flags
	wire in_reset, in_precharge, in_transition, in_transition_ph0, in_transition_ph1, in_measurement, in_evaluation;

    wire tempsens_en, temp_delay, tempsens_measure;
	wire [N_VDAC-1:0] tempsens_dat;
	wire [3:0] digit;


	// assemble the debug vectors
	wire [7:0] dbg01 = {temp_delay, in_reset, in_precharge, in_transition, in_transition_ph0, in_transition_ph1, in_measurement, in_evaluation};
	wire [7:0] dbg02 = {1'b0, tempsens_dat}; 
	wire [7:0] dbg03 = {1'b0, tempsens_res_raw};
	wire [7:0] dbg04 = {ctr[7:0]};
	wire [7:0] dbg05 = {2'b0, ctr[N_CTR-1:8]};
	wire [7:0] dbg06 = {1'b0, dac_value};
	wire [7:0] dbg07 = {1'b0, tempsens_res};
	wire [7:0] dbg08 = {meas_state, cal_ena, tempsens_measure, tempsens_en, idle_cycle, show_ones, show_tens};
	wire [7:0] dbg09 = {prectr[7:0]};
	wire [7:0] dbg10 = {use_prectr,5'b0,prectr[N_PRECTR-1:8]};


	// measurement state machine (meas_state)
	localparam PRECHARGE	= 2'b00;
	localparam TRANSITION	= 2'b01;
	localparam MEASURE		= 2'b10;
	localparam EVALUATE		= 2'b11;


	// VDAC max and min value
	localparam VMAX = {N_VDAC{1'b1}};
	localparam VMIN = {N_VDAC{1'b0}};


	// create state signals based on state of state machine
	assign in_reset = (ctr == {N_CTR{1'b1}});
	assign in_precharge = (meas_state == PRECHARGE)				&& !in_reset && !idle_cycle;
	assign in_transition = (meas_state == TRANSITION) 			&& !in_reset && !idle_cycle;
	assign in_transition_ph0 = in_transition && (clk == 1'b1) 	&& !in_reset && !idle_cycle;
	assign in_transition_ph1 = in_transition && (clk == 1'b0) 	&& !in_reset && !idle_cycle;
	assign in_measurement = (meas_state == MEASURE) 			&& !in_reset && !idle_cycle;
	assign in_evaluation = (meas_state == EVALUATE) 			&& !in_reset && !idle_cycle;


	// create temperature sensor input signal based on state signals, gate output to
	assign tempsens_en = in_reset ? 1'b0 : 1'b1;
	assign tempsens_dat =		in_precharge		? VMAX :
								in_transition_ph0	? VMIN :
								in_transition_ph1	? VMIN :
								in_measurement		? dac_value :
								in_evaluation		? dac_value :
								VMAX;
	assign tempsens_measure = 	in_precharge		? 1'b0 :
								in_transition_ph0	? 1'b0 :
								in_transition_ph1	? 1'b1 :
								in_measurement 		? 1'b1 :
								in_evaluation		? 1'b1 :
								1'b0;


	// display decimal number (tens or ones) on number LED; use new IO for debug signals
	assign led_out = 	{led_dot, led_segments};
	assign uio_out =	(en_dbg == 4'd00) ? {led_dot, led_segments} :	
						(en_dbg == 4'd01) ? dbg01 :
						(en_dbg == 4'd02) ? dbg02 :
						(en_dbg == 4'd03) ? dbg03 :
						(en_dbg == 4'd04) ? dbg04 :
						(en_dbg == 4'd05) ? dbg05 :
						(en_dbg == 4'd06) ? dbg06 :
						(en_dbg == 4'd07) ? dbg07 :
						(en_dbg == 4'd08) ? dbg08 :
						(en_dbg == 4'd09) ? dbg09 :
						(en_dbg == 4'd10) ? dbg10 :
						{led_dot, led_segments};
	

	// here we work on clk for temperature sensor control
    always @(posedge clk) begin
        if (reset) begin
			ctr <= {N_CTR{1'b1}};
			prectr <= {N_PRECTR{1'b1}};
			tempsens_res_raw <= {N_VDAC{1'b0}};
			temp_delay_last <= 1'b1;
		end else begin
			prectr <= prectr + 1'b1;
			if (use_prectr)
				if (prectr == {N_PRECTR{1'b0}})
					// if we use a pre-counter, the counter only counts up
					// when pre-counter overflows
					ctr <= ctr + 1'b1;
			else
				// if we don't use a pre-counter, we count on every clk
				ctr <= ctr + 1'b1;

			if (in_evaluation) begin
				if ((temp_delay_last == 1'b0) && (temp_delay == 1'b1))
					// we just saw a flip of the temperature-sensitive delay, so
					// this is the DAC value we searched and is our result
					tempsens_res_raw <= dac_value;

				temp_delay_last <= temp_delay;
			end
		end
	end


	// loading of calibration LUT (pre-load with fixed values on reset)
	always @(posedge cal_clk) begin
		if (reset)
			cal_lut <= LUT_PRELOAD;
		else
			// we load the LUT serially as a giant shift register (to save pins)
			cal_lut <= {cal_lut[((2**N_VDAC)*N_LUT)-1:1], cal_dat};
	end


	// assign wire array to LUT implemented a shift register (for easy load)
	// with wire array using the LUT is easier
	wire [N_LUT-1:0] cal_lut_entries[0:(2**N_VDAC)-1];
	genvar i;
	generate
		for (i=0; i < 2**N_VDAC; i=i+1) begin : lut_assign
			assign cal_lut_entries[i] = cal_lut[(N_LUT*(i+1)) -: N_LUT];
		end
	endgenerate


	// apply calibration LUT when enabled
	assign tempsens_res = cal_ena ? cal_lut_entries[tempsens_res_raw] : tempsens_res_raw;


    // instantiate temperature-dependent delay (this is the core circuit)
    tempsense #(.DAC_RESOLUTION(N_VDAC), .CAP_LOAD(16)) temp1 (
        .i_dac_data(tempsens_dat),
        .i_dac_en(tempsens_en),
        .i_precharge_n(tempsens_measure),
        .o_tempdelay(temp_delay)
    );


	// binary to decimal decoder to show measurement result on 7-segment LED
	bin2dec dec1 (
		.i_bin(tempsens_res),
		.i_tens(show_tens),
		.i_ones(show_ones),
		.o_dec(digit)
	);


    // instantiate segment display decoder
    seg7 seg1 (
        .i_disp(digit),
        .o_segments(led_segments)
    );

endmodule // tt_um_tt04_hpretl_tempsens
