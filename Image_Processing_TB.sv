`timescale 1ns/1ps

module image_processing_tb;
    // Testbench signals
    reg [10:0] iX_Cont;
    reg [10:0] iY_Cont;
    reg [11:0] iDATA;
    reg iDVAL;
    reg iCLK;
    reg iRST;
    reg iSW;
    
    wire [11:0] oGrey_R;
    wire [11:0] oGrey_G;
    wire [11:0] oGrey_B;
    wire oDVAL;
    
    // Instantiate the DUT
    image_processing dut (
        .oGrey_R(oGrey_R),
        .oGrey_G(oGrey_G),
        .oGrey_B(oGrey_B),
        .oDVAL(oDVAL),
        .iX_Cont(iX_Cont),
        .iY_Cont(iY_Cont),
        .iDATA(iDATA),
        .iDVAL(iDVAL),
        .iCLK(iCLK),
        .iRST(iRST),
        .iSW(iSW)
    );
    
    // Clock generation
    always #5 iCLK = ~iCLK;
    
    // Testbench process
    initial begin
        // Initialize signals
        iCLK = 0;
        iRST = 1;
        iDVAL = 0;
        iX_Cont = 0;
        iY_Cont = 0;
        iDATA = 0;
        iSW = 0;
        
        // Apply reset
        #20 iRST = 0;
        #20 iRST = 1;
        
        // Iterate over time to ensure at least 1000ns of simulation
        repeat (10) begin // Loop to ensure sufficient time coverage
            for (iY_Cont = 0; iY_Cont < 32; iY_Cont = iY_Cont + 1) begin
                for (iX_Cont = 0; iX_Cont < 32; iX_Cont = iX_Cont + 1) begin
                    iDVAL = 1;
                    
                    // Alternate `iDATA` values to test different intensities
                    case (iX_Cont % 4)
                        0: iDATA = 12'h000;   // All zeros (Black)
                        1: iDATA = 12'hFFF;   // All ones (White)
                        2: iDATA = (iX_Cont * iY_Cont) % 4096; // Random pattern
                        3: iDATA = (iX_Cont + iY_Cont) * 8; // Gradual increase
                    endcase
                    
                    // Toggle `iSW` randomly to test different configurations
                    if (iX_Cont % 5 == 0) iSW = ~iSW;
                    
                    // Introduce variable delays for `iDVAL`
                    if (iY_Cont % 4 == 0) begin
                        iDVAL = 0;
                        #15;
                    end else begin
                        #10; // Normal clock cycle
                    end
                end
            end
        end
        
        // Stop simulation after sufficient coverage
        #1000 $stop;
    end
    
    // Monitor outputs
    initial begin
        $monitor("Time=%0t, X=%d, Y=%d, iDATA=%d, iSW=%b, oGrey_R=%d, oGrey_G=%d, oGrey_B=%d, oDVAL=%b", 
                 $time, iX_Cont, iY_Cont, iDATA, iSW, oGrey_R, oGrey_G, oGrey_B, oDVAL);
    end
    
endmodule

