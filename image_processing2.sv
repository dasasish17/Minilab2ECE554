`timescale 1ns/1ps
// --------------------------------------------------------------------
// Copyright (c) 20057 by Terasic Technologies Inc.
// --------------------------------------------------------------------
//
// Permission:
//
//   Terasic grants permission to use and modify this code for use
//   in synthesis for all Terasic Development Boards and Altera Development 
//   Kits made by Terasic.  Other use of this code, including the selling 
//   ,duplication, or modification of any portion is strictly prohibited.
//
// Disclaimer:
//
//   This VHDL/Verilog or C/C++ source code is intended as a design reference
//   which illustrates how these types of functions can be implemented.
//   It is the user's responsibility to verify their design for
//   consistency and functionality through the use of formal
//   verification methods.  Terasic provides no warranty regarding the use 
//   or functionality of this code.
//
// --------------------------------------------------------------------
//
// Major Functions:    Image Processing Unit
//                     1. Converts raw sensor data to RGB (via RAW2RGB)
//                     2. Computes a grey value from the RGB data
//                     3. Optionally applies Sobel edge detection (vertical/horizontal)
// 
// Revision History :
// --------------------------------------------------------------------
//   Ver  :| Author       :| Mod. Date :| Changes Made:
//   V1.0 :| ChatGPT      :| 02/07/2025:| Initial Revision
// --------------------------------------------------------------------

module image_processing2 (
    input  wire         clk,         // Processing clock
    input  wire         rst,         // Active-low reset
    input  wire [11:0]  iDATA,       // Raw sensor data from camera
    input  wire         iDVAL,       // Raw data valid signal
    input  wire [10:0]  X_Cont,      // Horizontal pixel counter (0 to IMAGE_WIDTH-1)
    input  wire [10:0]  Y_Cont,      // Vertical line counter
    input  wire         mode_switch, // 0: grey output, 1: edge detection mode
    input  wire         is_vertical, // When edge detection is active: 1 = vertical, 0 = horizontal
    output reg  [11:0]  oDATA,       // Processed pixel (grey or edge magnitude)
    output reg          oDVAL        // Processed data valid
);

    parameter IMAGE_WIDTH = 640;  // Image width in pixels

    //==================================================================
    // RAW2RGB Conversion
    //==================================================================
    // The RAW2RGB module converts raw Bayer-pattern sensor data into
    // separate 12-bit R, G, and B components.
    wire [11:0] red, green, blue;
    wire        raw_valid;
    RAW2RGB u_raw2rgb (
        .iX_Cont(X_Cont),
        .iY_Cont(Y_Cont),
        .iDATA(iDATA),
        .iDVAL(iDVAL),
        .iCLK(clk),
        .iRST(rst),
        .oRed(red),
        .oGreen(green),
        .oBlue(blue),
        .oDVAL(raw_valid)
    );

    //==================================================================
    // Grey Conversion
    //==================================================================
    // Compute the grey value as: (red + 2×green + blue) / 4.
    // (The multiplication by 2 is achieved via a left-shift by 1, and
    // division by 4 is a right-shift by 2.)
    reg [11:0] newGray;
    always @(posedge clk or negedge rst) begin
        if (!rst)
            newGray <= 12'd0;
        else if (raw_valid)
            newGray <= (red + (green << 1) + blue) >> 2;
    end

    //==================================================================
    // Line Buffering for 3×3 Window
    //==================================================================
    // Three line buffers store three consecutive rows of grey data.
    // These buffers allow us to form a 3×3 window for the Sobel operator.
    // (Note: In a full design you might use block RAM or FIFO modules.)
    reg [11:0] line_buffer [0:2][0:IMAGE_WIDTH-1];

    // Detect the start of a new row. We assume X_Cont resets to 0 at a new row.
    reg [10:0] prev_X;
    reg        row_start;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            prev_X   <= 0;
            row_start <= 0;
        end else begin
            prev_X <= X_Cont;
            if (prev_X == IMAGE_WIDTH-1 && X_Cont == 0)
                row_start <= 1;
            else
                row_start <= 0;
        end
    end

    // On a new row, shift the line buffers upward.
    // Also, store the current grey pixel into the current row buffer.
    integer j;
    always @(posedge clk) begin
        if (row_start) begin
            for(j = 0; j < IMAGE_WIDTH; j = j + 1) begin
                line_buffer[0][j] <= line_buffer[1][j];
                line_buffer[1][j] <= line_buffer[2][j];
            end
        end
        if (raw_valid && (X_Cont < IMAGE_WIDTH))
            line_buffer[2][X_Cont] <= newGray;
    end

    //==================================================================
    // 3×3 Window Formation
    //==================================================================
    // Form a 3×3 window from the three line buffers. This window is only
    // valid when X_Cont is between 1 and IMAGE_WIDTH-2 and when Y_Cont is
    // at least 2.
    reg [11:0] window [0:2][0:2];
    always @(posedge clk) begin
        if ((X_Cont >= 1) && (X_Cont < IMAGE_WIDTH-1) && (Y_Cont >= 2)) begin
            window[0][0] <= line_buffer[0][X_Cont-1];
            window[0][1] <= line_buffer[0][X_Cont];
            window[0][2] <= line_buffer[0][X_Cont+1];

            window[1][0] <= line_buffer[1][X_Cont-1];
            window[1][1] <= line_buffer[1][X_Cont];
            window[1][2] <= line_buffer[1][X_Cont+1];

            window[2][0] <= line_buffer[2][X_Cont-1];
            window[2][1] <= line_buffer[2][X_Cont];
            window[2][2] <= line_buffer[2][X_Cont+1];
        end
    end

    //==================================================================
    // Edge Detection (Sobel Operator)
    //==================================================================
    // When mode_switch is high, the module applies the Sobel operator.
    // Depending on is_vertical, it computes either:
    //   - Gx (horizontal edge detection), or
    //   - Gy (vertical edge detection).
    // Otherwise, the grey value is output.
    reg signed [15:0] Gx, Gy;
    reg       [15:0] edge_value;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            oDATA      <= 12'd0;
            oDVAL      <= 1'b0;
            Gx         <= 16'd0;
            Gy         <= 16'd0;
            edge_value <= 16'd0;
        end else if (raw_valid) begin
            if (mode_switch && (X_Cont >= 1) && (X_Cont < IMAGE_WIDTH-1) && (Y_Cont >= 2)) begin
                if (is_vertical) begin
                    // Vertical edge detection (Gy):
                    // Gy = (-1 * window[0][0]) + (-2 * window[0][1]) + (-1 * window[0][2])
                    //      + (1 * window[2][0]) + (2 * window[2][1]) + (1 * window[2][2])
                    Gy <= - $signed(window[0][0])
                          - ($signed(window[0][1]) << 1)
                          - $signed(window[0][2])
                          + $signed(window[2][0])
                          + ($signed(window[2][1]) << 1)
                          + $signed(window[2][2]);
                    edge_value <= (Gy < 0) ? -Gy : Gy;
                end else begin
                    // Horizontal edge detection (Gx):
                    // Gx = (-1 * window[0][0]) + (1 * window[0][2])
                    //      + (-2 * window[1][0]) + (2 * window[1][2])
                    //      + (-1 * window[2][0]) + (1 * window[2][2])
                    Gx <= - $signed(window[0][0])
                          + $signed(window[0][2])
                          - ($signed(window[1][0]) << 1)
                          + ($signed(window[1][2]) << 1)
                          - $signed(window[2][0])
                          + $signed(window[2][2]);
                    edge_value <= (Gx < 0) ? -Gx : Gx;
                end
                if (edge_value > 16'd4095)
                    oDATA <= 12'hFFF;
                else
                    oDATA <= edge_value[11:0];
            end else begin
                // When not in edge detection mode (or outside the valid window),
                // output the grey value.
                oDATA <= newGray;
            end
            oDVAL <= raw_valid;
        end else begin
            oDVAL <= 1'b0;
        end
    end

endmodule
