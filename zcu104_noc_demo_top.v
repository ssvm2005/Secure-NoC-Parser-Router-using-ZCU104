`timescale 1ns / 1ps

// ================================================================
// ZCU104 HARDWARE DEMONSTRATION WRAPPER
//
// Phase-1 Secure NoC Router
//
// Router configuration:
//      DW     = 16
//      NPORTS = 4
//
// Physical controls:
//      SW[3:2] = SOURCE PORT
//      SW[1:0] = DESTINATION PORT
//
//      BTN_SEND_N  = active-low SEND button
//      BTN_RESET_N = active-low RESET button
//
// Port encoding:
//      2'b00 = NORTH
//      2'b01 = SOUTH
//      2'b10 = EAST
//      2'b11 = WEST
//
// LEDs:
//      LED[3:0] = last detected output destination
//
//      LED[0] = NORTH
//      LED[1] = SOUTH
//      LED[2] = EAST
//      LED[3] = WEST
//
//      If ACL drop occurs:
//          LED[3:0] = 4'b1111
//
//      If parity error occurs:
//          LED[3:0] = 4'b1010
//
// Packet format:
//
//      HEADER
//      PAYLOAD[0]
//      PAYLOAD[1]
//      PAYLOAD[2]
//      PAYLOAD[3]
//      PARITY
//
// Header:
//
//      {8'h00, payload_len[3:0], dest[1:0], qos[1:0]}
//
// ================================================================

module zcu104_noc_demo_top (
    // ZCU104 125 MHz differential PL clock
    input wire       clk_p,
    input wire       clk_n,

    // ZCU104 user pushbuttons
    input wire       btn_reset,
    input wire       btn_send,

    // ZCU104 DIP switches
    input wire [3:0] sw,

    // ZCU104 user LEDs
    output wire [3:0] led
);

// ============================================================
// ZCU104 DIFFERENTIAL 125 MHz CLOCK
// CLK_125_P / CLK_125_N
// ============================================================

wire clk;

IBUFDS #(
    .DIFF_TERM("FALSE"),
    .IBUF_LOW_PWR("TRUE")
) u_ibufds_clk (
    .I (clk_p),
    .IB(clk_n),
    .O (clk)
);

// ============================================================
// ZCU104 PUSHBUTTON POLARITY
// Physical buttons are active HIGH.
// Existing FSM uses active-LOW signals.
// ============================================================
//      BTN_SEND  = physical SEND button (active-high)
//      BTN_RESET = physical RESET button (active-high)
//
// Internally converted to active-low:
//      btn_send_n
//      btn_reset_n
wire btn_reset_n;
wire btn_send_n;

assign btn_reset_n = ~btn_reset;
assign btn_send_n  = ~btn_send;

    // ============================================================
    // CONSTANTS
    // ============================================================

    localparam integer DW     = 16;
    localparam integer NPORTS = 4;

    // Four-payload-flit demonstration packet
    localparam [3:0] PAYLOAD_LEN = 4'd4;

    // Low QoS = 00
    localparam [1:0] QOS_LEVEL = 2'b00;


    // ============================================================
    // SWITCH DECODING
    // ============================================================

    wire [1:0] source_port;
    wire [1:0] destination_port;

    assign source_port      = sw[3:2];
    assign destination_port = sw[1:0];


    // ============================================================
    // PACKET DATA
    // ============================================================

    /*
     * Header format from the actual Phase-1 parser:
     *
     * [15:8] = 8'h00
     * [7:4]  = payload length
     * [3:2]  = destination
     * [1:0]  = QoS
     */

    wire [15:0] packet_header;

    assign packet_header = {
        8'h00,
        PAYLOAD_LEN,
        destination_port,
        QOS_LEVEL
    };


    // ------------------------------------------------------------
    // Fixed payloads for the physical demonstration
    // ------------------------------------------------------------

    wire [15:0] payload0;
    wire [15:0] payload1;
    wire [15:0] payload2;
    wire [15:0] payload3;

    assign payload0 = 16'h1001;
    assign payload1 = 16'h1002;
    assign payload2 = 16'h1003;
    assign payload3 = 16'h1004;


    // ============================================================
    // PARITY GENERATION
    // ============================================================

    /*
     * The actual parser uses:
     *
     * running_parity <= header;
     * running_parity <= running_parity ^ payload;
     *
     * Therefore the final parity flit is:
     *
     * HEADER ^ PAYLOAD0 ^ PAYLOAD1 ^ PAYLOAD2 ^ PAYLOAD3
     */

    wire [15:0] packet_parity;

    assign packet_parity =
            packet_header ^
            payload0 ^
            payload1 ^
            payload2 ^
            payload3;


    // ============================================================
    // ROUTER INPUT SIGNALS
    // ============================================================

    reg [NPORTS-1:0]     valid_in;
    reg [NPORTS-1:0]     is_header_in;
    reg [NPORTS*DW-1:0] data_in;

    // Router output-buffer read enables
    reg [NPORTS-1:0] read_enb_out;


    // ============================================================
    // ROUTER OUTPUT SIGNALS
    // ============================================================

    wire [NPORTS*DW-1:0] data_out;
    wire [NPORTS-1:0]    out_valid;

    wire busy;
    wire parity_error;
    wire acl_drop_flag;
    wire [1:0] invalid_addr_flag;


    // ============================================================
    // SEND BUTTON EDGE DETECTION
    // ============================================================

    /*
     * Physical SEND button is assumed active-low.
     *
     * Button:
     *
     *      1 = released
     *      0 = pressed
     *
     * We generate a one-clock pulse when the button is pressed.
     */

    reg btn_send_n_d;

    wire send_pulse;

    always @(posedge clk or negedge btn_reset_n) begin

        if (!btn_reset_n)

            btn_send_n_d <= 1'b1;

        else

            btn_send_n_d <= btn_send_n;

    end

    assign send_pulse = btn_send_n_d & ~btn_send_n;


    // ============================================================
    // PACKET GENERATOR FSM
    // ============================================================

    localparam [3:0]
        ST_IDLE        = 4'd0,
        ST_HEADER      = 4'd1,
        ST_PAYLOAD0    = 4'd2,
        ST_PAYLOAD1    = 4'd3,
        ST_PAYLOAD2    = 4'd4,
        ST_PAYLOAD3    = 4'd5,
        ST_PARITY      = 4'd6,
        ST_WAIT_OUTPUT = 4'd7,
        ST_READ_OUTPUT = 4'd8,
        ST_DONE        = 4'd9;

    reg [3:0] state;


    // ============================================================
    // OUTPUT STATUS LATCH
    // ============================================================

    reg [3:0] led_status;

    /*
     * We latch the output result instead of directly connecting
     * LEDs to out_valid because out_valid may only remain high
     * for a short time.
     */

    assign led = led_status;


    // ============================================================
    // PACKET GENERATOR / CONTROLLER
    // ============================================================

    always @(posedge clk or negedge btn_reset_n) begin

        if (!btn_reset_n) begin

            state        <= ST_IDLE;

            valid_in     <= 4'b0000;
            is_header_in <= 4'b0000;

            data_in      <= 64'b0;

            read_enb_out <= 4'b0000;

            led_status   <= 4'b0000;

        end

        else begin

            // ----------------------------------------------------
            // Default values
            // ----------------------------------------------------

            valid_in     <= 4'b0000;
            is_header_in <= 4'b0000;

            read_enb_out <= 4'b0000;


            // ----------------------------------------------------
            // FSM
            // ----------------------------------------------------

            case (state)


                // =================================================
                // IDLE
                // =================================================

                ST_IDLE: begin

                    if (send_pulse) begin

                        state <= ST_HEADER;

                    end

                end


                // =================================================
                // HEADER
                // =================================================

                ST_HEADER: begin

                    /*
                     * Put the header into the selected source port.
                     */

                    case (source_port)

                        2'd0: begin

                            data_in[15:0] <= packet_header;

                            valid_in[0] <= 1'b1;

                            is_header_in[0] <= 1'b1;

                        end


                        2'd1: begin

                            data_in[31:16] <= packet_header;

                            valid_in[1] <= 1'b1;

                            is_header_in[1] <= 1'b1;

                        end


                        2'd2: begin

                            data_in[47:32] <= packet_header;

                            valid_in[2] <= 1'b1;

                            is_header_in[2] <= 1'b1;

                        end


                        2'd3: begin

                            data_in[63:48] <= packet_header;

                            valid_in[3] <= 1'b1;

                            is_header_in[3] <= 1'b1;

                        end

                    endcase

                    state <= ST_PAYLOAD0;

                end


                // =================================================
                // PAYLOAD 0
                // =================================================

                ST_PAYLOAD0: begin

                    case (source_port)

                        2'd0:
                            begin
                                data_in[15:0] <= payload0;
                                valid_in[0] <= 1'b1;
                            end

                        2'd1:
                            begin
                                data_in[31:16] <= payload0;
                                valid_in[1] <= 1'b1;
                            end

                        2'd2:
                            begin
                                data_in[47:32] <= payload0;
                                valid_in[2] <= 1'b1;
                            end

                        2'd3:
                            begin
                                data_in[63:48] <= payload0;
                                valid_in[3] <= 1'b1;
                            end

                    endcase

                    state <= ST_PAYLOAD1;

                end


                // =================================================
                // PAYLOAD 1
                // =================================================

                ST_PAYLOAD1: begin

                    case (source_port)

                        2'd0:
                            begin
                                data_in[15:0] <= payload1;
                                valid_in[0] <= 1'b1;
                            end

                        2'd1:
                            begin
                                data_in[31:16] <= payload1;
                                valid_in[1] <= 1'b1;
                            end

                        2'd2:
                            begin
                                data_in[47:32] <= payload1;
                                valid_in[2] <= 1'b1;
                            end

                        2'd3:
                            begin
                                data_in[63:48] <= payload1;
                                valid_in[3] <= 1'b1;
                            end

                    endcase

                    state <= ST_PAYLOAD2;

                end


                // =================================================
                // PAYLOAD 2
                // =================================================

                ST_PAYLOAD2: begin

                    case (source_port)

                        2'd0:
                            begin
                                data_in[15:0] <= payload2;
                                valid_in[0] <= 1'b1;
                            end

                        2'd1:
                            begin
                                data_in[31:16] <= payload2;
                                valid_in[1] <= 1'b1;
                            end

                        2'd2:
                            begin
                                data_in[47:32] <= payload2;
                                valid_in[2] <= 1'b1;
                            end

                        2'd3:
                            begin
                                data_in[63:48] <= payload2;
                                valid_in[3] <= 1'b1;
                            end

                    endcase

                    state <= ST_PAYLOAD3;

                end


                // =================================================
                // PAYLOAD 3
                // =================================================

                ST_PAYLOAD3: begin

                    case (source_port)

                        2'd0:
                            begin
                                data_in[15:0] <= payload3;
                                valid_in[0] <= 1'b1;
                            end

                        2'd1:
                            begin
                                data_in[31:16] <= payload3;
                                valid_in[1] <= 1'b1;
                            end

                        2'd2:
                            begin
                                data_in[47:32] <= payload3;
                                valid_in[2] <= 1'b1;
                            end

                        2'd3:
                            begin
                                data_in[63:48] <= payload3;
                                valid_in[3] <= 1'b1;
                            end

                    endcase

                    state <= ST_PARITY;

                end


                // =================================================
                // PARITY
                // =================================================

                ST_PARITY: begin

                    case (source_port)

                        2'd0:
                            begin
                                data_in[15:0] <= packet_parity;
                                valid_in[0] <= 1'b1;
                            end

                        2'd1:
                            begin
                                data_in[31:16] <= packet_parity;
                                valid_in[1] <= 1'b1;
                            end

                        2'd2:
                            begin
                                data_in[47:32] <= packet_parity;
                                valid_in[2] <= 1'b1;
                            end

                        2'd3:
                            begin
                                data_in[63:48] <= packet_parity;
                                valid_in[3] <= 1'b1;
                            end

                    endcase

                    state <= ST_WAIT_OUTPUT;

                end


                // =================================================
                // WAIT FOR OUTPUT
                // =================================================

                ST_WAIT_OUTPUT: begin

                    /*
                     * Wait until at least one output FIFO contains
                     * data.
                     */

                    if (|out_valid) begin

                        // -----------------------------------------
                        // ACL DROP
                        // -----------------------------------------

                        if (acl_drop_flag) begin

                            led_status <= 4'b1111;

                        end

                        // -----------------------------------------
                        // PARITY ERROR
                        // -----------------------------------------

                        else if (parity_error) begin

                            led_status <= 4'b1010;

                        end

                        // -----------------------------------------
                        // NORMAL ROUTING
                        // -----------------------------------------

                        else begin

                            led_status <= out_valid;

                        end

                        state <= ST_READ_OUTPUT;

                    end

                end


                // =================================================
                // READ OUTPUT
                // =================================================

                ST_READ_OUTPUT: begin

                    /*
                     * Drain all output FIFOs that currently contain
                     * data.
                     *
                     * Since out_valid = !ob_empty in the router,
                     * asserting read_enb_out here causes the output
                     * FIFO to advance.
                     */

                    read_enb_out <= out_valid;

                    /*
                     * Return to idle after one read cycle.
                     */

                    state <= ST_DONE;

                end


                // =================================================
                // DONE
                // =================================================

                ST_DONE: begin

                    /*
                     * Wait until all output FIFOs are empty.
                     *
                     * This is useful because a 4-payload packet
                     * produces multiple output flits.
                     */

                    if (!(|out_valid)) begin

                        state <= ST_IDLE;

                    end
                    else begin

                        read_enb_out <= out_valid;

                    end

                end


                // =================================================
                // DEFAULT
                // =================================================

                default: begin

                    state <= ST_IDLE;

                end

            endcase

        end

    end


    // ============================================================
    // SECURE NoC ROUTER
    //
    // IMPORTANT:
    //
    // Do NOT use:
    //
    // secure_noc_router_top #(...)
    //
    // because the router uses `DW and `NPORTS macros rather than
    // module parameters.
    // ============================================================

    secure_noc_router_top u_router (

        .clk(clk),

        .resetn(btn_reset_n),

        .valid_in(valid_in),

        .is_header_in(is_header_in),

        .data_in(data_in),

        .read_enb_out(read_enb_out),

        .data_out(data_out),

        .out_valid(out_valid),

        .busy(busy),

        .parity_error(parity_error),

        .acl_drop_flag(acl_drop_flag),

        .invalid_addr_flag(invalid_addr_flag)

    );


endmodule
