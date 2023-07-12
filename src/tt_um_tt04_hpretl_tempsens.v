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
//	- DONE Add LUT for result calibration
//	- DONE Add more testmodes
//	- DONE Simulate logic
//	- Simulate mixed-signal

`default_nettype none

`include "tempsense.v"
`include "seg7.v"
`include "bin2dec.v"

module tt_um_hpretl_tt04_tempsens (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

	assign uio_oe = 8'b1;		// all IOs used as outputs

	// size the design with these constants
	localparam N_VDAC = 7;
	localparam N_LUT = 7;
	localparam N_CTR = 14; // 2**N_CTR gives roughly a second tick @ clk=10kHz

	// pre-loaded LUT based on nominal simulation results; only even values div:2
	// stored, otherwise does not fit the TinyTapeout area
	localparam [(2**N_VDAC)*N_LUT:1] LUT_PRELOAD = {
		// output	// input
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00,		//
		7'd00		//
	};

	// definition of external inputs
	wire reset = ~rst_n;
	wire cal_clk = ui_in[0];
	wire cal_dat = ui_in[1];
	wire cal_ena = ui_in[2];
	wire [3:0] en_dbg = ui_in[7:4];

	/* verilator lint_off UNUSEDSIGNAL */
	wire dummy1 = ui_in[3];
	wire dummy2 = |uio_in;
	wire dummy3 = ena;
	/* verilator lint_on UNUSEDSIGNAL */

	// definition of external outputs
	wire [7:0] led_out;
	wire [6:0] led_segments;
	wire led_dot = show_ones;
	assign uo_out[7:0] = led_out; 

	// definition of internal wires and regs
	reg [N_CTR-1:0] ctr;
	reg [N_VDAC-1:0] tempsens_res_raw;
	wire [N_VDAC-1:0] tempsens_res;
	reg temp_delay_last;
	reg [(2**N_VDAC)*N_LUT:1] cal_lut;

	wire [1:0] meas_state = ctr[1:0];
	wire [N_VDAC-1:0] dac_value = {N_VDAC{1'b1}} - ctr[N_VDAC+1:2];
	wire idle_cycle = |ctr[N_CTR-1:N_VDAC+2];
	wire show_tens = ~ctr[N_CTR-1];
	wire show_ones = ctr[N_CTR-1];

	wire in_reset, in_precharge, in_transition, in_transition_ph0, in_transition_ph1, in_measurement, in_evaluation;

    wire tempsens_en, temp_delay, tempsens_measure;
	wire [N_VDAC-1:0] tempsens_dat;
	wire [3:0] digit;


	// debug vectors
	wire [7:0] dbg1 = {temp_delay, in_reset, in_precharge, in_transition, in_transition_ph0, in_transition_ph1, in_measurement, in_evaluation};
	wire [7:0] dbg2 = {1'b0, tempsens_dat}; 
	wire [7:0] dbg3 = {1'b0, tempsens_res_raw};
	wire [7:0] dbg4 = {ctr[7:0]};
	wire [7:0] dbg5 = {2'b0, ctr[N_CTR-1:8]};
	wire [7:0] dbg6 = {1'b0, dac_value};
	wire [7:0] dbg7 = {1'b0, tempsens_res};
	wire [7:0] dbg8 = {meas_state, cal_ena, tempsens_measure, tempsens_en, idle_cycle, show_ones, show_tens};


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
	assign uio_out =	(en_dbg == 4'd0) ? {led_dot, led_segments} :	
						(en_dbg == 4'd1) ? dbg1 :
						(en_dbg == 4'd2) ? dbg2 :
						(en_dbg == 4'd3) ? dbg3 :
						(en_dbg == 4'd4) ? dbg4 :
						(en_dbg == 4'd5) ? dbg5 :
						(en_dbg == 4'd6) ? dbg6 :
						(en_dbg == 4'd7) ? dbg7 :
						(en_dbg == 4'd8) ? dbg8 :
						{led_dot, led_segments};
	

	// state machine implementation for temperature sensor control
    always @(posedge clk) begin
        if (reset) begin
			ctr <= {N_CTR{1'b1}};
			tempsens_res_raw <= {N_VDAC{1'b0}};
			temp_delay_last <= 1'b1;
		end else begin
			ctr <= ctr + 1'b1;

			if (in_evaluation) begin
				if ((temp_delay_last == 1'b0) && (temp_delay == 1'b1)) begin
					tempsens_res_raw <= dac_value;
				end

				temp_delay_last <= temp_delay;
			end
		end
	end


	// loading of calibration LUT
	always @(posedge cal_clk) begin
		if (reset) begin
			cal_lut <= LUT_PRELOAD;
		end else begin
			cal_lut <= {cal_lut[((2**N_VDAC)*N_LUT)-1:1], cal_dat};
		end
	end


	// assign wire array to LUT implemented a shift register (for easy load)
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

endmodule // tt_um_hpretl_tt04_tempsens
